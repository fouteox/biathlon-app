import type { RaceSnapshot } from "./ibu";

export type ChangeKind = "cancelled" | "rescheduled";

export interface RaceChange {
  kind: ChangeKind;
  race: RaceSnapshot;
}

/** Start time shifts smaller than this are ignored. */
const MIN_SHIFT_MS = 60 * 1000;

/**
 * Compares the previous and current state of a race. A race seen for the
 * first time never triggers an alert: it only becomes the baseline.
 */
export function detectChange(previous: RaceSnapshot | undefined, current: RaceSnapshot): RaceChange | undefined {
  if (!previous) return undefined;
  if (current.status === "cancelled") {
    return previous.status === "cancelled" ? undefined : { kind: "cancelled", race: current };
  }
  if (current.status === "finished") return undefined;
  const shift = Math.abs(Date.parse(current.startTime) - Date.parse(previous.startTime));
  if (shift >= MIN_SHIFT_MS) return { kind: "rescheduled", race: current };
  return undefined;
}

export function hasChanged(previous: RaceSnapshot | undefined, current: RaceSnapshot): boolean {
  return (
    !previous ||
    previous.startTime !== current.startTime ||
    previous.status !== current.status ||
    previous.name !== current.name ||
    previous.category !== current.category
  );
}
