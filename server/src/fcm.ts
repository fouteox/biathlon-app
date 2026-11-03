import type { PushOutcome } from "./apns";
import { buildAndroidNotification, type AlertInput } from "./payload";

/**
 * Firebase Cloud Messaging, HTTP v1 API (https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages,
 * read on 2026-11-03). Devices are addressed by their Firebase Installation ID (`fid`), which
 * replaces the deprecated registration token.
 */

/** An alert to one Android device. */
export interface FCMPush {
  fid: string;
  /** One alert of a kind per race: a newer one replaces it, delivered or in the drawer. */
  collapseKey: string;
  /** UNIX time in seconds after which FCM stops trying to deliver. */
  expiration: number;
  alert: AlertInput;
}

/** Firebase Installation IDs are short URL-safe strings; Google gives no exact format. */
const FID_PATTERN = /^[A-Za-z0-9_-]{1,256}$/;

export function isInstallationId(value: unknown): value is string {
  return typeof value === "string" && FID_PATTERN.test(value);
}

/** The `Message` of `push`, sent at `now` (milliseconds). */
export function buildMessage(push: FCMPush, now: number) {
  return {
    fid: push.fid,
    android: {
      collapseKey: push.collapseKey,
      // A visible alert the user asked for: delivered at once, waking the device.
      priority: "HIGH",
      ttl: `${Math.max(0, push.expiration - Math.floor(now / 1000))}s`,
      notification: { ...buildAndroidNotification(push.alert), tag: push.collapseKey },
    },
    // Read by the app to reschedule its reminder, as the iOS payload's.
    data: { raceId: push.alert.raceId, startTime: push.alert.startTime },
  };
}

/** Sends `push`; any failure to reach FCM is a retry. */
export async function sendFCM(
  push: FCMPush,
  projectId: string,
  accessToken: string,
  now: number,
  signal?: AbortSignal,
): Promise<PushOutcome> {
  let response: Response;
  try {
    response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ message: buildMessage(push, now) }),
      signal,
    });
  } catch (error) {
    return { kind: "retry", reason: String(error) };
  }
  if (response.ok) return { kind: "sent" };
  const errorCode = await response
    .json<FCMErrorBody>()
    .then((body) => body.error?.details?.find((detail) => detail.errorCode)?.errorCode ?? body.error?.status ?? "")
    .catch(() => "");
  return classifyFCM(response.status, errorCode);
}

interface FCMErrorBody {
  error?: { status?: string; details?: { errorCode?: string }[] };
}

/**
 * FCM's error codes (https://firebase.google.com/docs/reference/fcm/rest/v1/ErrorCode): an
 * installation unknown to FCM, or registered with another sender, is forgotten; a rejected access
 * token is signed again; quotas and outages are retried. Any other 400 is this server's mistake,
 * which deleting the device would hide.
 */
export function classifyFCM(status: number, errorCode: string): PushOutcome {
  if (status === 404 && errorCode === "UNREGISTERED") return { kind: "unregistered" };
  if (status === 403 && errorCode === "SENDER_ID_MISMATCH") return { kind: "unregistered" };
  if (status === 401) return { kind: "expiredProviderToken" };
  if (status === 429 || status >= 500) return { kind: "retry", reason: `${status} ${errorCode}` };
  return { kind: "failed", reason: `${status} ${errorCode}` };
}
