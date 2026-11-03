import type { PushOutcome } from "./apns";
import type { LiveState } from "./live";
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

/**
 * A race's state, to the app's Live Update (Android's Live Activity) on the devices subscribed to
 * the race's topic (`raceTopic`): FCM has no broadcast channel, and a topic reaches all of them
 * in one request (https://firebase.google.com/docs/cloud-messaging/android/topic-messaging).
 */
export interface TopicPush {
  raceId: string;
  event: "update" | "end";
  state: LiveState;
  /** When the state was published, in seconds since 1970, for the app to ignore an older one arriving late. */
  timestamp: number;
  /** For an end, when the app removes the final state, in seconds since 1970 (`dismissalDate`, live.ts). */
  dismissalDate?: number;
}

/** The topic of a race's Live Update. Topic names take letters, digits and `-_.~%`; IBU race ids are letters and digits. */
export function raceTopic(raceId: string): string {
  return `race-${raceId}`;
}

/**
 * How long FCM keeps an update for a device that is offline: before the start, the state the
 * topic opens with is the only one for 30 minutes, until the race goes live. A newer one replaces
 * it (`collapseKey`).
 */
const TOPIC_UPDATE_TTL_S = 60 * 60;

/**
 * The `Message` of `push`, sent at `now` (milliseconds): data only, which the app draws into its
 * notification, at high priority since it shows one (https://firebase.google.com/docs/cloud-messaging/android/message-priority).
 * FCM data values are strings. An end is kept until its dismissal date, and no later.
 */
export function buildTopicMessage(push: TopicPush, now: number) {
  const topic = raceTopic(push.raceId);
  const expiration = push.dismissalDate ?? Math.floor(now / 1000) + TOPIC_UPDATE_TTL_S;
  return {
    topic,
    android: {
      collapseKey: topic,
      priority: "HIGH",
      ttl: `${Math.max(0, expiration - Math.floor(now / 1000))}s`,
    },
    data: {
      raceId: push.raceId,
      event: push.event,
      state: JSON.stringify(push.state),
      timestamp: String(push.timestamp),
      ...(push.dismissalDate === undefined ? {} : { dismissalDate: String(push.dismissalDate) }),
    },
  };
}

/** Sends a `Message` (`buildMessage`, `buildTopicMessage`); any failure to reach FCM is a retry. */
export async function sendFCM(
  message: object,
  projectId: string,
  accessToken: string,
  signal?: AbortSignal,
): Promise<PushOutcome> {
  let response: Response;
  try {
    response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ message }),
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
