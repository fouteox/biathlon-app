import type { ChangeKind } from "./changes";
import { eventId } from "./ibu";

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
  const bodyArgs = input.kind === "rescheduled" ? rescheduledArgs(input) : [input.raceName];
  return {
    aps: {
      alert: {
        "title-loc-key": keys.title,
        "loc-key": keys.body,
        "loc-args": bodyArgs,
      },
      sound: "default",
      // One group per event: a whole event cancelled stacks as one group of alerts.
      "thread-id": eventId(input.raceId),
    },
    // Read by the app to reschedule its local reminder.
    raceId: input.raceId,
    startTime: input.startTime,
  };
}

/** A race can be postponed to another day, so the alert names the day with the time. */
function rescheduledArgs(input: AlertInput): string[] {
  const { day, time } = formatStart(input);
  return [input.raceName, day, time];
}

/**
 * The new start's day and time, in the device's locale and time zone
 * (e.g. "jeudi" and "15:45", or "Thursday" and "3:45 PM").
 */
export function formatStart(input: Pick<AlertInput, "startTime" | "locale" | "timeZone">): { day: string; time: string } {
  const date = new Date(input.startTime);
  const format = (locale: string, timeZone: string) => ({
    day: new Intl.DateTimeFormat(locale, { weekday: "long", timeZone }).format(date),
    time: new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit", timeZone }).format(date),
  });
  try {
    return format(input.locale, input.timeZone);
  } catch {
    const utc = format("en", "UTC");
    return { day: utc.day, time: `${utc.time} UTC` };
  }
}
