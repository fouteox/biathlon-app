import type { ChangeKind } from "./changes";
import { eventId } from "./ibu";

/**
 * Alert texts are resolved on the device from the app's Localizable.xcstrings
 * through `title-loc-key` / `loc-key`, so the server never translates: the title
 * names the race, the body says what happened. The keys must exist in the app's
 * String Catalog.
 */
export const LOC_KEYS = {
  cancelled: "push.cancelled",
  rescheduled: "push.rescheduled",
  /** The alert of a Live Activity started for a favorite (liveStarts.ts). */
  liveActivityStart: "push.liveActivity",
  /** The alert of a Live Activity started for a race the device follows (liveStarts.ts). */
  followedRaceStart: "push.followedRace",
} as const;

/**
 * The `catId` + `DisciplineId` pairs that follow a `RaceId`'s event and that the app names
 * (`RaceKind` in BiathlonKit), checked against the shared `race-kinds.json` fixture.
 */
export const RACE_KINDS = [
  "SMSP",
  "SWSP",
  "SMPU",
  "SWPU",
  "SMIN",
  "SWIN",
  "SMSI",
  "SWSI",
  "SMMS",
  "SWMS",
  "SMRL",
  "SWRL",
  "MXRL",
  "MXSR",
] as const;

/**
 * The race's name in the app's String Catalog, or `undefined` for a kind the app doesn't know.
 * The kind follows the 14-character event, as in `RaceKind(raceID:)`.
 */
export function raceTitleKey(raceId: string): string | undefined {
  const kind = raceId.slice(14, 18);
  return (RACE_KINDS as readonly string[]).includes(kind) ? `race.${kind}` : undefined;
}

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
  const titleKey = raceTitleKey(input.raceId);
  return {
    aps: {
      alert: {
        ...(titleKey ? { "title-loc-key": titleKey } : { title: input.raceName }),
        "loc-key": LOC_KEYS[input.kind],
        ...(input.kind === "rescheduled" && { "loc-args": rescheduledArgs(input) }),
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
  return [day, time];
}

/**
 * The new start's day and time, in the device's locale and time zone
 * (e.g. "jeudi" and "15:45", or "Thursday" and "3:45 PM").
 */
export function formatStart(input: Pick<AlertInput, "startTime" | "locale" | "timeZone">): {
  day: string;
  time: string;
} {
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
