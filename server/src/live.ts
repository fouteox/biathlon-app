import { ENVIRONMENTS, type APNsEnvironment } from "./apns";
import { parseIBUDate, raceStatus, type IBUCompetition, type RaceSnapshot, type RaceStatus } from "./ibu";
import type { ProviderTokens, ProviderTokenSet } from "./providerTokens";

/**
 * One Live Activity per race, updated through an APNs broadcast channel: one request
 * per update reaches every subscriber, whatever their number (Apple, WWDC24 session
 * 10069). Each race's Durable Object (`RaceActivity`, raceActivity.ts) opens a channel
 * per APNs environment while the race is upcoming, publishes each change of its state,
 * then ends the activity and deletes the channel at APNs a while after the race is over
 * (channels are limited to 10,000).
 */

/** `Results?RaceId=`: the race and its rows. */
export interface IBUResults {
  /** Whether `Results` is the published start list, before the race. */
  IsStartList?: boolean | null;
  Competition?: IBUCompetition | null;
  Results?: IBUResultRow[] | null;
}

export interface IBUResultRow {
  /** An athlete's row, not a team's. */
  IBUId?: string | null;
  IsTeam?: boolean | null;
  Name?: string | null;
  ShortName?: string | null;
  Nat?: string | null;
  Rank?: string | number | null;
  IRM?: string | null;
  TotalTime?: string | null;
  Behind?: string | null;
}

/**
 * The Live Activity's `content-state`, decoded on the device into `RaceLiveState`
 * (BiathlonKit) with the default `Codable` strategies: same keys, and dates in
 * seconds since 2001-01-01. Checked against the shared `live-activity.json` fixture.
 */
export interface LiveState {
  phase: RaceStatus;
  startTime: number;
  leaders: Leader[];
}

export interface Leader {
  rank: string;
  name: string;
  nation?: string;
  /** The leader's time, then each follower's gap to them. */
  result?: string;
}

const LEADER_COUNT = 3;

/**
 * The broadcast's `relevance-score`, which `RaceLiveState.relevanceScore` (BiathlonKit) gives
 * the app's own updates: with several races followed, the Dynamic Island shows the live
 * one rather than the first activity started. Upcoming races rank alike: their activities
 * only show from 30 minutes before the start, and races are farther apart. Between 0 and 1:
 * Apple takes any value for a Live Activity, only their order counts, but the Push
 * Notifications Console rejects one above 1, the range of other notifications. Checked
 * against the shared `live-activity.json` fixture.
 */
export function relevanceScore(state: LiveState): number {
  return RELEVANCE_SCORES[state.phase];
}

const RELEVANCE_SCORES: Record<RaceStatus, number> = { live: 1, scheduled: 0.5, finished: 0, cancelled: 0 };
/** Seconds between the UNIX epoch and the reference date of Foundation's `Date`. */
const REFERENCE_DATE_S = 978_307_200;
/**
 * How long after its race's start an activity can be on screen: a Live Activity lasts at most
 * 8 hours, then stays on the Lock Screen for up to 4 more (ActivityKit, "Displaying live data
 * with Live Activities"). A race followed no longer gets one past it.
 */
export const ACTIVITY_LIFETIME_MS = 12 * 60 * 60_000;

/**
 * Deletes the channels deleted at APNs whose activity ended longer ago than an activity can
 * stay on screen (`ACTIVITY_LIFETIME_MS`): until then, `channelFor` tells the app it ended.
 */
export async function pruneChannels(db: D1Database, now: number): Promise<void> {
  await db
    .prepare("DELETE FROM live_channels WHERE ended_at < ?1 AND deleted_at IS NOT NULL")
    .bind(now - ACTIVITY_LIFETIME_MS)
    .run();
}

/** The state the app shows, from a race's results; `undefined` without a `Competition` block. */
export function liveState(results: IBUResults): LiveState | undefined {
  const competition = results.Competition;
  if (!competition) return undefined;
  const rows = results.Results ?? [];
  const teams = rows.filter((row) => row.IsTeam);
  const ranked = (teams.length > 0 ? teams : rows).filter((row) => !row.IRM && row.Rank != null).slice(0, LEADER_COUNT);
  return {
    phase: raceStatus(competition),
    startTime: referenceSeconds(competition.StartTime),
    leaders: ranked.map((row, index) => {
      // Absent rather than null, like Swift's synthesized `Codable`.
      const leader: Leader = { rank: String(row.Rank), name: row.ShortName ?? row.Name ?? "" };
      if (row.Nat) leader.nation = row.Nat;
      const result = index === 0 ? row.TotalTime : row.Behind;
      if (result) leader.result = result;
      return leader;
    }),
  };
}

/** What the calendar tells of a race: everything but its leaders. */
type CalendarFields = Pick<LiveState, "phase" | "startTime">;

export function calendarFields(race: RaceSnapshot): CalendarFields {
  return { phase: race.status, startTime: referenceSeconds(race.startTime) };
}

function referenceSeconds(time: string): number {
  return parseIBUDate(time) / 1000 - REFERENCE_DATE_S;
}

/** UNIX milliseconds of a `startTime` in seconds since 2001-01-01. */
export function referenceMs(seconds: number): number {
  return (seconds + REFERENCE_DATE_S) * 1000;
}

export function isFollowable(race: RaceSnapshot | undefined): race is RaceSnapshot {
  return race?.status === "scheduled" || race?.status === "live";
}

/** The `timestamp` of an ActivityKit push, in seconds since 1970, from a time in milliseconds. */
export function broadcastTimestamp(ms: number): number {
  return Math.floor(ms / 1000);
}

/**
 * The `dismissal-date` of an activity ended at `endedAt` (milliseconds), in seconds since 1970
 * like `timestamp`: the Lock Screen keeps the final state 30 minutes, within the HIG's
 * "15 to 30 minutes is adequate", instead of the default four hours. Every send of the end
 * carries the same date, so a device offline until later removes the activity at once.
 */
export function dismissalDate(endedAt: number): number {
  return broadcastTimestamp(endedAt + DISMISSAL_DELAY_MS);
}

const DISMISSAL_DELAY_MS = 30 * 60_000;

/**
 * Hands each race the calendar lists to its Durable Object (`RaceActivity`), all at once, with
 * the run's APNs provider tokens: objects signing their own at once would renew them more often
 * than the 20 minutes APNs accepts. A race whose update fails is logged, and tried again by its
 * object's alarm.
 */
export async function syncLiveActivities(
  env: Env,
  races: RaceSnapshot[],
  now: number,
  tokens: ProviderTokens,
): Promise<void> {
  if (races.length === 0) return;
  const providerTokens = await givenTokens(tokens);
  const updates = await Promise.allSettled(
    races.map((race) => env.RACE_ACTIVITY.getByName(race.id).sync(race, now, providerTokens)),
  );
  updates.forEach((update, index) => {
    if (update.status === "rejected")
      console.error("Live Activity update failed", races[index]!.id, String(update.reason));
  });
}

/**
 * The run's provider tokens, for the objects. One that can't be loaded, like a broken APNs key,
 * is left out: its environment's requests then fail in each object, without holding up the other's.
 */
export async function givenTokens(tokens: ProviderTokens): Promise<ProviderTokenSet> {
  const given: ProviderTokenSet = {};
  for (const environment of ENVIRONMENTS) {
    try {
      given[environment] = await tokens.token(environment);
    } catch (error) {
      console.error("APNs provider token unavailable", environment, String(error));
    }
  }
  return given;
}

/**
 * The channel the app subscribes a race's Live Activity to, for its APNs environment,
 * with the state last published on it: the channel stores no messages, so a new
 * activity starts from it. Once the end is sent, which a new subscriber would miss,
 * only the final state and its dismissal date, for the app to end the activities that missed it. None while
 * a dropped channel waits for its replacement.
 */
export async function channelFor(
  db: D1Database,
  raceId: string,
  environment: APNsEnvironment,
): Promise<
  { channelId: string; state: LiveState; timestamp: number } | { ended: LiveState; dismissalDate: number } | undefined
> {
  const row = await db
    .prepare(
      `SELECT channel_id AS channelId, state, published_at AS publishedAt, ended_at AS endedAt, deleted_at AS deletedAt
       FROM live_channels WHERE race_id = ?1 AND environment = ?2`,
    )
    .bind(raceId, environment)
    .first<{
      channelId: string;
      state: string;
      publishedAt: number;
      endedAt: number | null;
      deletedAt: number | null;
    }>();
  if (!row) return undefined;
  const state = JSON.parse(row.state) as LiveState;
  if (row.endedAt !== null) return { ended: state, dismissalDate: dismissalDate(row.endedAt) };
  return row.deletedAt === null
    ? { channelId: row.channelId, state, timestamp: broadcastTimestamp(row.publishedAt) }
    : undefined;
}
