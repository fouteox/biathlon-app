import type { ChangeKind } from "./changes";

/**
 * Alert texts are resolved on the device from the app's Localizable.xcstrings
 * through `title-loc-key` / `loc-key`, so the server never translates.
 * The keys must exist in the app's String Catalog.
 */
export const LOC_KEYS = {
  cancelled: { title: "push.cancelled.title", body: "push.cancelled.body" },
  rescheduled: { title: "push.rescheduled.title", body: "push.rescheduled.body" },
  /** The alert of a Live Activity started for a favorite (liveStarts.ts). */
  liveActivityStart: { title: "push.liveActivity.title", body: "push.liveActivity.body" },
} as const;

export interface AlertInput {
  kind: ChangeKind;
  raceId: string;
  raceName: string;
  /** ISO 8601, UTC. */
  startTime: string;
  locale: string;
  timeZone: string;
}

export function buildPayload(input: AlertInput) {
  const keys = LOC_KEYS[input.kind];
  const bodyArgs = input.kind === "rescheduled" ? [input.raceName, formatTime(input)] : [input.raceName];
  return {
    aps: {
      alert: {
        "title-loc-key": keys.title,
        "loc-key": keys.body,
        "loc-args": bodyArgs,
      },
      sound: "default",
      "thread-id": input.raceId,
    },
    // Read by the app to reschedule its local reminder.
    raceId: input.raceId,
    startTime: input.startTime,
  };
}

/** The new start time, in the device's locale and time zone (e.g. "15:45" or "3:45 PM"). */
export function formatTime(input: Pick<AlertInput, "startTime" | "locale" | "timeZone">): string {
  const date = new Date(input.startTime);
  const options: Intl.DateTimeFormatOptions = { hour: "numeric", minute: "2-digit" };
  try {
    return new Intl.DateTimeFormat(input.locale, { ...options, timeZone: input.timeZone }).format(date);
  } catch {
    return new Intl.DateTimeFormat("en", { ...options, timeZone: "UTC" }).format(date) + " UTC";
  }
}
