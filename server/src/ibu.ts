// Minimal client for the undocumented biathlonresults.com API.

import type { SubrequestBudget } from "./subrequests";

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
  IsLive?: boolean | null;
}

/** The fields of a race the watcher compares from one poll to the next. */
export interface RaceSnapshot {
  id: string;
  category: string;
  name: string;
  startTime: string;
  status: RaceStatus;
}

export type RaceStatus = "scheduled" | "live" | "cancelled" | "finished";

const FIRST_RESULT_STATUS_ID = 10;

/** Spends one subrequest of the run's budget; throws once none is left. */
export async function fetchIBU<T>(path: string, query: Record<string, string>, budget: SubrequestBudget): Promise<T> {
  if (!budget.take()) throw new Error(`IBU ${path}: no subrequest left in this run`);
  const url = new URL(path, IBU_BASE_URL);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`IBU ${path} answered ${response.status}`);
  return response.json<T>();
}

/** A race's event: a `RaceId` starts with its 14-character `EventId`, as biathlonresults.com reads it. */
export function eventId(raceId: string): string {
  return raceId.slice(0, 14);
}

/** IBU season id for a date, e.g. "2627" for winter 2026-27. */
export function seasonId(date: Date): string {
  const start = seasonStart(date).getUTCFullYear();
  const two = (n: number) => String(n % 100).padStart(2, "0");
  return two(start) + two(start + 1);
}

/** The start of the IBU season of a date: seasons start on July 1st. */
export function seasonStart(date: Date): Date {
  const year = date.getUTCFullYear();
  return new Date(Date.UTC(date.getUTCMonth() >= 6 ? year : year - 1, 6, 1));
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
    status: raceStatus(race),
  };
}

/**
 * Observed values: StatusId 1 / "Scheduled" / SCHEDULED, 6 / "Cancelled" /
 * CANCELLED and 11 / "Final" / FINISHED. biathlonresults.com shows results from
 * StatusId 10, which covers results not yet official. Same rules as the app
 * (`Competition.state`), checked against the shared `race-status.json` fixture.
 */
export function raceStatus(race: Omit<IBUCompetition, "RaceId" | "ShortDescription">): RaceStatus {
  if (race.IsLive) return "live";
  const text = `${race.ScheduleStatus ?? ""} ${race.StatusText ?? ""}`.toUpperCase();
  if (text.includes("CANCEL") || Number(race.StatusId) === 6) return "cancelled";
  if (text.includes("FINISHED") || Number(race.StatusId) >= FIRST_RESULT_STATUS_ID) return "finished";
  return "scheduled";
}
