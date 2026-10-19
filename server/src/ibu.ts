// Minimal client for the undocumented biathlonresults.com API.

export const IBU_BASE_URL = "https://biathlonresults.com/modules/sportapi/api/";

export interface IBUEvent {
  EventId: string;
  StartDate: string;
  EndDate: string;
}

export interface IBUCompetition {
  RaceId: string;
  catId?: string | null;
  ShortDescription: string;
  StartTime: string;
  StatusId?: number | string | null;
  StatusText?: string | null;
  ScheduleStatus?: string | null;
}

/** The fields of a race the watcher compares from one poll to the next. */
export interface RaceSnapshot {
  id: string;
  category: string;
  name: string;
  startTime: string;
  status: RaceStatus;
}

export type RaceStatus = "scheduled" | "cancelled" | "finished" | "other";

export async function fetchIBU<T>(path: string, query: Record<string, string>): Promise<T> {
  const url = new URL(path, IBU_BASE_URL);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`IBU ${path} answered ${response.status}`);
  return response.json<T>();
}

/** IBU season id for a date, e.g. "2627" for winter 2026-27. Seasons start on July 1st. */
export function seasonId(date: Date): string {
  const year = date.getUTCFullYear();
  const start = date.getUTCMonth() >= 6 ? year : year - 1;
  const two = (n: number) => String(n % 100).padStart(2, "0");
  return two(start) + two(start + 1);
}

/** IBU dates come with or without a trailing "Z"; both are UTC. */
export function parseIBUDate(raw: string): number {
  const withZone = /Z$|[+-]\d\d:?\d\d$/.test(raw) ? raw : `${raw}Z`;
  return Date.parse(withZone);
}

/**
 * Events worth watching at `now`: from two days before an event starts
 * until one day after it ends, so early schedule changes are caught too.
 */
export function activeEvents(events: IBUEvent[], now: number): IBUEvent[] {
  const day = 24 * 60 * 60 * 1000;
  return events.filter(
    (event) => parseIBUDate(event.StartDate) - 2 * day <= now && now <= parseIBUDate(event.EndDate) + day,
  );
}

export function snapshot(race: IBUCompetition): RaceSnapshot {
  return {
    id: race.RaceId,
    category: race.catId ?? "",
    name: race.ShortDescription,
    startTime: new Date(parseIBUDate(race.StartTime)).toISOString(),
    status: status(race),
  };
}

/**
 * Observed values: StatusId 1 / "Scheduled" / SCHEDULED, 6 / "Cancelled" /
 * CANCELLED and 11 / "Final" / FINISHED. Same rules as the app
 * (`Competition.state`), checked against the shared `race-status.json` fixture.
 */
function status(race: IBUCompetition): RaceStatus {
  const text = `${race.ScheduleStatus ?? ""} ${race.StatusText ?? ""}`.toUpperCase();
  if (text.includes("CANCEL") || Number(race.StatusId) === 6) return "cancelled";
  if (text.includes("FINISHED") || Number(race.StatusId) === 11) return "finished";
  if (text.includes("SCHEDULED") || Number(race.StatusId) === 1) return "scheduled";
  return "other";
}
