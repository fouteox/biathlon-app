// APNs provider API, token-based authentication.
// https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
// https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
// https://developer.apple.com/documentation/usernotifications/sending-channel-management-requests-to-apns
// https://developer.apple.com/documentation/usernotifications/sending-broadcast-push-notification-requests-to-apns

export type APNsEnvironment = "sandbox" | "production";

export const ENVIRONMENTS: readonly APNsEnvironment[] = ["production", "sandbox"];

export function isEnvironment(value: unknown): value is APNsEnvironment {
  return ENVIRONMENTS.includes(value as APNsEnvironment);
}

/** Device pushes and broadcasts. */
const HOSTS: Record<APNsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

/**
 * Broadcast channel management, on its own ports. Workers honor custom ports in
 * `fetch` since the `allow_custom_ports` compatibility date (2024-09-02).
 */
const CHANNEL_HOSTS: Record<APNsEnvironment, string> = {
  sandbox: "https://api-manage-broadcast.sandbox.push.apple.com:2195",
  production: "https://api-manage-broadcast.push.apple.com:2196",
};

/**
 * Apple: refresh the token no more than once every 20 minutes and no less
 * than once every 60 minutes. Reusing it for 45 minutes stays inside both bounds.
 */
export const PROVIDER_TOKEN_LIFETIME_S = 45 * 60;

export interface ProviderKey {
  /** Contents of the .p8 file downloaded from the developer account. */
  pem: string;
  keyId: string;
  teamId: string;
}

/** Signs an ES256 JWT with the `alg`, `kid`, `iss` and `iat` fields Apple requires. */
export async function makeProviderToken(key: ProviderKey, issuedAt: number): Promise<string> {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: key.keyId }));
  const claims = base64url(JSON.stringify({ iss: key.teamId, iat: issuedAt }));
  const signingInput = `${header}.${claims}`;
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(key.pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto returns the raw r||s signature, which is the JWS ES256 format.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

export interface PushRequest {
  deviceToken: string;
  environment: APNsEnvironment;
  topic: string;
  payload: unknown;
  collapseId?: string;
  /** An alert unless given: `liveactivity` for an ActivityKit push, whose topic ends in `.push-type.liveactivity`. */
  pushType?: "alert" | "liveactivity";
  /** UNIX time in seconds after which APNs stops trying to deliver. */
  expiration: number;
}

export type PushOutcome =
  | { kind: "sent" }
  /** The device token or the channel is no longer valid: forget it. */
  | { kind: "unregistered" }
  /** The provider token was rejected: sign a new one and retry once. */
  | { kind: "expiredProviderToken" }
  | { kind: "retry"; reason: string }
  | { kind: "failed"; reason: string };

export async function sendPush(request: PushRequest, providerToken: string): Promise<PushOutcome> {
  const headers: Record<string, string> = {
    "apns-push-type": request.pushType ?? "alert",
    "apns-topic": request.topic,
    "apns-priority": "10",
    "apns-expiration": String(request.expiration),
  };
  if (request.collapseId) headers["apns-collapse-id"] = request.collapseId;
  const { outcome } = await apnsRequest(
    `${HOSTS[request.environment]}/3/device/${request.deviceToken}`,
    "POST",
    headers,
    providerToken,
    request.payload,
  );
  return outcome;
}

export interface BroadcastRequest {
  environment: APNsEnvironment;
  /** The app's bundle ID. */
  bundleId: string;
  channelId: string;
  payload: unknown;
}

/**
 * Publishes a Live Activity update to every device subscribed to the channel.
 * Priority 10: each broadcast carries a change people follow the race for. Channels
 * store no messages, which only accept an expiration of 0.
 */
export async function broadcast(request: BroadcastRequest, providerToken: string): Promise<PushOutcome> {
  const headers = {
    "apns-push-type": "liveactivity",
    "apns-channel-id": request.channelId,
    "apns-priority": "10",
    "apns-expiration": "0",
  };
  const url = `${HOSTS[request.environment]}/4/broadcasts/apps/${request.bundleId}`;
  return (await apnsRequest(url, "POST", headers, providerToken, request.payload)).outcome;
}

export type ChannelOutcome = { kind: "created"; channelId: string } | Exclude<PushOutcome, { kind: "sent" }>;

/**
 * Creates a Live Activity channel that stores no messages: Apple's choice for
 * frequently updated sports scores, with a higher publishing budget.
 */
export async function createChannel(
  environment: APNsEnvironment,
  bundleId: string,
  providerToken: string,
): Promise<ChannelOutcome> {
  const url = `${CHANNEL_HOSTS[environment]}/1/apps/${bundleId}/channels`;
  const body = { "message-storage-policy": 0, "push-type": "LiveActivity" };
  const { outcome, response } = await apnsRequest(url, "POST", {}, providerToken, body);
  if (outcome.kind !== "sent") return outcome;
  const channelId = response?.headers.get("apns-channel-id");
  return channelId ? { kind: "created", channelId } : { kind: "failed", reason: "no apns-channel-id header" };
}

/** Deletes a channel. "unregistered" means it was already gone. */
export async function deleteChannel(
  environment: APNsEnvironment,
  bundleId: string,
  channelId: string,
  providerToken: string,
): Promise<PushOutcome> {
  const url = `${CHANNEL_HOSTS[environment]}/1/apps/${bundleId}/channels`;
  return (await apnsRequest(url, "DELETE", { "apns-channel-id": channelId }, providerToken)).outcome;
}

/** Sends one authenticated request; any 2xx status is a success. */
async function apnsRequest(
  url: string,
  method: "POST" | "DELETE",
  headers: Record<string, string>,
  providerToken: string,
  payload?: unknown,
): Promise<{ outcome: PushOutcome; response?: Response }> {
  let response: Response;
  try {
    response = await fetch(url, {
      method,
      headers: { ...headers, authorization: `bearer ${providerToken}` },
      body: payload === undefined ? undefined : JSON.stringify(payload),
    });
  } catch (error) {
    return { outcome: { kind: "retry", reason: String(error) } };
  }
  if (response.ok) return { outcome: { kind: "sent" }, response };
  return { outcome: classify(response.status, await errorReason(response)), response };
}

const UNREGISTERED_REASONS = new Set(["BadDeviceToken", "DeviceTokenNotForTopic", "ChannelNotRegistered", "BadChannelId"]);

export function classify(status: number, reason: string): PushOutcome {
  if (status === 410) return { kind: "unregistered" };
  if (status === 400 && UNREGISTERED_REASONS.has(reason)) return { kind: "unregistered" };
  // InvalidProviderToken also covers a cached token signed with a key that was since rotated.
  if (status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken")) {
    return { kind: "expiredProviderToken" };
  }
  if (status === 429 || status >= 500) return { kind: "retry", reason: `${status} ${reason}` };
  return { kind: "failed", reason: `${status} ${reason}` };
}

/**
 * Checks that this runtime reaches APNs over HTTP/2, for device pushes and for
 * channel management (on port 2195 or 2196). Without a provider token, APNs answers
 * 403 with a JSON `MissingProviderToken` reason, and it only does so over HTTP/2.
 */
export async function probe(environment: APNsEnvironment, topic: string) {
  return {
    pushes: await probeURL(`${HOSTS[environment]}/3/device/00`, "POST", {
      "apns-topic": topic,
      "apns-push-type": "alert",
    }),
    channels: await probeURL(`${CHANNEL_HOSTS[environment]}/1/apps/${topic}/all-channels`, "GET", {}),
  };
}

async function probeURL(url: string, method: string, headers: Record<string, string>) {
  try {
    const response = await fetch(url, { method, headers, body: method === "POST" ? "{}" : undefined });
    const reason = await errorReason(response);
    return { http2: reason === "MissingProviderToken", detail: `${response.status} ${reason}` };
  } catch (error) {
    return { http2: false, detail: String(error) };
  }
}

async function errorReason(response: Response): Promise<string> {
  try {
    const body = await response.json<{ reason?: string }>();
    return body.reason ?? "";
  } catch {
    return "";
  }
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return bytes.buffer;
}

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
