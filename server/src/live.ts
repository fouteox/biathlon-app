import { broadcast, createChannel, deleteChannel, ENVIRONMENTS, type APNsEnvironment } from "./apns";
import { fetchIBU, parseIBUDate, raceStatus, type IBUCompetition, type RaceSnapshot, type RaceStatus } from "./ibu";
import { ProviderTokens } from "./providerTokens";
import { SubrequestBudget } from "./subrequests";

/**
 * One Live Activity per race, updated through an APNs broadcast channel: one request
 * per update reaches every subscriber, whatever their number (Apple, WWDC24 session
 * 10069). The watcher opens a channel per race and APNs environment while the race
 * is upcoming, publishes each change of its state, then ends the activity and
 * deletes the channel a while after the race is over (channels are limited to 10,000).
 */

/** `Results?RaceId=`: the race and its rows. */
export interface IBUResults {
  Competition?: IBUCompetition | null;
  Results?: IBUResultRow[] | null;
}

export interface IBUResultRow {
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
/** Seconds between the UNIX epoch and the reference date of Foundation's `Date`. */
const REFERENCE_DATE_S = 978_307_200;
/**
 * Each creation is one subrequest; the Free plan allows 50 per invocation, and
 * the outbox spends up to `MAX_PUSHES_PER_RUN` of them. Counted per environment,
 * so failures in one never hold up the other.
 */
const MAX_CHANNEL_CREATIONS_PER_ENVIRONMENT = 2;
/**
 * The channels store no messages, as Apple advises for frequent updates like sports
 * scores, so a device offline when the end is sent never gets it: the end is sent
 * again at this interval, until the channel is deleted.
 */
const END_RESEND_INTERVAL_MS = 10 * 60_000;
const END_GRACE_MS = 60 * 60_000;

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

/** The state of a race nobody has results for yet, from the calendar alone. */
function calendarState(race: RaceSnapshot): LiveState {
  return { phase: race.status, startTime: referenceSeconds(race.startTime), leaders: [] };
}

function referenceSeconds(time: string): number {
  return parseIBUDate(time) / 1000 - REFERENCE_DATE_S;
}

interface ChannelRow {
  raceId: string;
  environment: APNsEnvironment;
  channelId: string;
  state: string;
  endedAt: number | null;
  endSentAt: number | null;
}

/**
 * Opens the channels of upcoming races, broadcasts each new state of the races
 * that have channels, and ends the activities of races that are over or no longer
 * watched (`races` is the watcher's current list). Without `races`, when the
 * calendar can't be read, only the activities already ended are looked after.
 * What the budget can't cover waits for the next run.
 */
export async function syncLiveActivities(
  env: Env,
  races: RaceSnapshot[] | undefined,
  now: number,
  budget = new SubrequestBudget(),
): Promise<void> {
  const tokens = new ProviderTokens(env, now, budget);
  const { results: rows } = await env.DB.prepare(
    "SELECT race_id AS raceId, environment, channel_id AS channelId, state, ended_at AS endedAt, end_sent_at AS endSentAt FROM live_channels",
  ).all<ChannelRow>();
  const watched = new Map(races?.map((race) => [race.id, race]));
  const open: ChannelRow[] = [];
  const kept: ChannelRow[] = [];
  for (const channel of rows) {
    if (channel.endedAt === null) {
      open.push(channel);
      kept.push(channel);
    } else if (isFollowable(watched.get(channel.raceId))) {
      // A race followable again, like a cancellation called off, gets new channels.
      if (!(await deleteEnded(env, tokens, channel))) kept.push(channel);
    } else {
      await resendEnd(env, tokens, channel, now);
      kept.push(channel);
    }
  }
  if (!races) return;
  await openChannels(env, tokens, races, kept, now);

  for (const [raceId, channels] of Map.groupBy(open, (row) => row.raceId)) {
    const race = watched.get(raceId);
    const state = await currentState(raceId, race, budget);
    for (const channel of channels) {
      const stored = JSON.parse(channel.state) as LiveState;
      if (!race) {
        // No longer watched: the activity ends with the latest state there is.
        await end(env, tokens, channel, state ?? stored, now);
      } else if (race.status === "finished" || race.status === "cancelled") {
        // Results that can't be read don't hold the end back.
        await end(env, tokens, channel, state ?? { ...stored, phase: race.status }, now);
      } else if (state && JSON.stringify(state) !== channel.state) {
        await publish(env, tokens, channel, state, now);
      }
    }
  }
}

function isFollowable(race: RaceSnapshot | undefined): race is RaceSnapshot {
  return race?.status === "scheduled" || race?.status === "live";
}

/**
 * Upcoming races change only through the calendar; the others need their results.
 * `undefined` when the results can't be read: the next run tries again.
 */
async function currentState(
  raceId: string,
  race: RaceSnapshot | undefined,
  budget: SubrequestBudget,
): Promise<LiveState | undefined> {
  if (race?.status === "scheduled" || race?.status === "cancelled") return calendarState(race);
  try {
    const state = liveState(await fetchIBU<IBUResults>("Results", { RaceId: raceId }, budget));
    return state ?? (race && calendarState(race));
  } catch (error) {
    console.warn("Live Activity results unavailable", raceId, String(error));
    return undefined;
  }
}

async function openChannels(env: Env, tokens: ProviderTokens, races: RaceSnapshot[], rows: ChannelRow[], now: number) {
  const open = new Set(rows.map((row) => `${row.raceId} ${row.environment}`));
  const followable = races.filter(isFollowable);
  const missing = ENVIRONMENTS.flatMap((environment) =>
    followable
      .filter((race) => !open.has(`${race.id} ${environment}`))
      .slice(0, MAX_CHANNEL_CREATIONS_PER_ENVIRONMENT)
      .map((race) => ({ race, environment })),
  );

  for (const { race, environment } of missing) {
    const outcome = await tokens.send(environment, (token) => createChannel(environment, env.APNS_TOPIC, token));
    if (outcome.kind === "deferred") return;
    if (outcome.kind !== "created") {
      console.error("APNs channel creation failed", race.id, environment, outcome);
      continue;
    }
    // A live race starts from the calendar too: its first results are published at the next run.
    await env.DB.prepare(
      "INSERT INTO live_channels (race_id, environment, channel_id, state, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
    )
      .bind(race.id, environment, outcome.channelId, JSON.stringify(calendarState(race)), now)
      .run();
  }
}

async function publish(env: Env, tokens: ProviderTokens, channel: ChannelRow, state: LiveState, now: number) {
  const outcome = await send(env, tokens, channel, "update", state, now);
  if (outcome === "sent") {
    await env.DB.prepare(`UPDATE live_channels SET state = ?1 WHERE ${SAME_OPEN_CHANNEL}`)
      .bind(JSON.stringify(state), channel.raceId, channel.environment, channel.channelId)
      .run();
  } else if (outcome === "unregistered") {
    // A new channel opens at the next run while the race is still upcoming or live.
    await forget(env, channel);
  }
}

/**
 * Cron runs can overlap: a run only changes the row it read, while it is still open,
 * so an older run never overwrites a newer end. Binds ?2 to ?4.
 */
const SAME_OPEN_CHANNEL = "race_id = ?2 AND environment = ?3 AND channel_id = ?4 AND ended_at IS NULL";

/** Sends the final state, retried at the next run until it succeeds. */
async function end(env: Env, tokens: ProviderTokens, channel: ChannelRow, state: LiveState, now: number) {
  const outcome = await send(env, tokens, channel, "end", state, now);
  if (outcome === "sent") {
    await env.DB.prepare(
      `UPDATE live_channels SET state = ?1, ended_at = ?5, end_sent_at = ?5 WHERE ${SAME_OPEN_CHANNEL}`,
    )
      .bind(JSON.stringify(state), channel.raceId, channel.environment, channel.channelId, now)
      .run();
  } else if (outcome === "unregistered") {
    await forget(env, channel);
  }
}

/** Sends the end again for devices that were offline, then deletes the channel once the grace period is over. */
async function resendEnd(env: Env, tokens: ProviderTokens, channel: ChannelRow, now: number) {
  if (now - (channel.endedAt ?? now) >= END_GRACE_MS) {
    await deleteEnded(env, tokens, channel);
    return;
  }
  if (now - (channel.endSentAt ?? now) < END_RESEND_INTERVAL_MS) return;
  const outcome = await send(env, tokens, channel, "end", JSON.parse(channel.state) as LiveState, now);
  if (outcome === "sent") {
    await env.DB.prepare("UPDATE live_channels SET end_sent_at = ?1 WHERE race_id = ?2 AND environment = ?3")
      .bind(now, channel.raceId, channel.environment)
      .run();
  } else if (outcome === "unregistered") {
    await forget(env, channel);
  }
}

/** Deletes an ended channel; `false` when it is still there, for the next run to retry. */
async function deleteEnded(env: Env, tokens: ProviderTokens, channel: ChannelRow): Promise<boolean> {
  const deletion = await tokens.send(channel.environment, (token) =>
    deleteChannel(channel.environment, env.APNS_TOPIC, channel.channelId, token),
  );
  if (deletion.kind !== "sent" && deletion.kind !== "unregistered") {
    if (deletion.kind !== "deferred") console.error("APNs channel deletion failed", channel.raceId, channel.environment, deletion);
    return false;
  }
  await env.DB.prepare("DELETE FROM live_channels WHERE race_id = ?1 AND environment = ?2 AND channel_id = ?3")
    .bind(channel.raceId, channel.environment, channel.channelId)
    .run();
  return true;
}

/** Broadcasts an ActivityKit event; "unregistered" when APNs no longer knows the channel. */
async function send(
  env: Env,
  tokens: ProviderTokens,
  channel: ChannelRow,
  event: "update" | "end",
  state: LiveState,
  now: number,
): Promise<"sent" | "unregistered" | "failed"> {
  const payload = { aps: { timestamp: Math.floor(now / 1000), event, "content-state": state } };
  const outcome = await tokens.send(channel.environment, (token) =>
    broadcast({ environment: channel.environment, bundleId: env.APNS_TOPIC, channelId: channel.channelId, payload }, token),
  );
  if (outcome.kind === "sent" || outcome.kind === "unregistered") return outcome.kind;
  if (outcome.kind !== "deferred") console.error("APNs broadcast failed", channel.raceId, channel.environment, outcome);
  return "failed";
}

/** Drops a channel APNs no longer knows. */
async function forget(env: Env, channel: ChannelRow) {
  await env.DB.prepare("DELETE FROM live_channels WHERE race_id = ?1 AND environment = ?2 AND channel_id = ?3")
    .bind(channel.raceId, channel.environment, channel.channelId)
    .run();
}

/**
 * The channel the app subscribes a race's Live Activity to, for its APNs environment,
 * with the state last published on it: the channel stores no messages, so a new
 * activity starts from it. None once the end is sent, which a new subscriber would miss.
 */
export async function channelFor(
  db: D1Database,
  raceId: string,
  environment: APNsEnvironment,
): Promise<{ channelId: string; state: LiveState } | undefined> {
  const row = await db
    .prepare(
      "SELECT channel_id AS channelId, state FROM live_channels WHERE race_id = ?1 AND environment = ?2 AND ended_at IS NULL",
    )
    .bind(raceId, environment)
    .first<{ channelId: string; state: string }>();
  return row ? { channelId: row.channelId, state: JSON.parse(row.state) as LiveState } : undefined;
}
