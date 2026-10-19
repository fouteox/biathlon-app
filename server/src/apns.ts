// APNs provider API, token-based authentication.
// https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
// https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns

export type APNsEnvironment = "sandbox" | "production";

const HOSTS: Record<APNsEnvironment, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
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
  /** UNIX time in seconds after which APNs stops trying to deliver. */
  expiration: number;
}

export type PushOutcome =
  | { kind: "sent" }
  /** The token is no longer valid for the topic: forget the device. */
  | { kind: "unregistered" }
  /** The provider token was rejected: sign a new one and retry once. */
  | { kind: "expiredProviderToken" }
  | { kind: "retry"; reason: string }
  | { kind: "failed"; reason: string };

export async function sendPush(request: PushRequest, providerToken: string): Promise<PushOutcome> {
  const headers: Record<string, string> = {
    authorization: `bearer ${providerToken}`,
    "apns-push-type": "alert",
    "apns-topic": request.topic,
    "apns-priority": "10",
    "apns-expiration": String(request.expiration),
  };
  if (request.collapseId) headers["apns-collapse-id"] = request.collapseId;
  let response: Response;
  try {
    response = await fetch(`${HOSTS[request.environment]}/3/device/${request.deviceToken}`, {
      method: "POST",
      headers,
      body: JSON.stringify(request.payload),
    });
  } catch (error) {
    return { kind: "retry", reason: String(error) };
  }
  if (response.status === 200) return { kind: "sent" };
  const reason = await errorReason(response);
  return classify(response.status, reason);
}

export function classify(status: number, reason: string): PushOutcome {
  if (status === 410) return { kind: "unregistered" };
  if (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic")) {
    return { kind: "unregistered" };
  }
  // InvalidProviderToken also covers a cached token signed with a key that was since rotated.
  if (status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken")) {
    return { kind: "expiredProviderToken" };
  }
  if (status === 429 || status >= 500) return { kind: "retry", reason: `${status} ${reason}` };
  return { kind: "failed", reason: `${status} ${reason}` };
}

/**
 * Checks that this runtime reaches APNs over HTTP/2. Without a provider
 * token, APNs answers 403 with a JSON `MissingProviderToken` reason, and it
 * only does so over HTTP/2.
 */
export async function probe(environment: APNsEnvironment, topic: string): Promise<{ http2: boolean; detail: string }> {
  try {
    const response = await fetch(`${HOSTS[environment]}/3/device/00`, {
      method: "POST",
      headers: { "apns-topic": topic, "apns-push-type": "alert" },
      body: "{}",
    });
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
