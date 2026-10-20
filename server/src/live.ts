import { broadcast, createChannel, deleteChannel, ENVIRONMENTS, type APNsEnvironment } from "./apns";
import { fetchIBU, parseIBUDate, raceStatus, type IBUCompetition, type RaceSnapshot, type RaceStatus } from "./ibu";
import { ProviderTokens } from "./providerTokens";
import { SubrequestBudget } from "./subrequests";

/**
 * One Live Activity per race, updated through an APNs broadcast channel: one request
 * per update reaches every subscriber, whatever their number (Apple, WWDC24 session
 * 10069). The watcher opens a channel per race and APNs environment while the race
 * is upcoming, publishes each change of its state, then ends the activity and
 * deletes the channel at APNs a while after the race is over (channels are limited
 * to 10,000).
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
 * Channels are deleted a few per run: a couple of races end at a time, and failures
 * can't use up the budget of the races still followed.
 */
const MAX_CHANNEL_DELETIONS_PER_RUN = 4;
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

/** What the calendar tells of a race: everything but its leaders. */
type CalendarFields = Pick<LiveState, "phase" | "startTime">;

function calendarFields(race: RaceSnapshot): CalendarFields {
  return { phase: race.status, startTime: referenceSeconds(race.startTime) };
}

function isTerminal(phase: RaceStatus): boolean {
  return phase === "finished" || phase === "cancelled";
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
  deletedAt: number | null;
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
    `SELECT race_id AS raceId, environment, channel_id AS channelId, state, ended_at AS endedAt, end_sent_at AS endSentAt, deleted_at AS deletedAt
     FROM live_channels ORDER BY attempted_at, race_id, environment`,
  ).all<ChannelRow>();
  const watched = new Map(races?.map((race) => [race.id, race]));
  const open: ChannelRow[] = [];
  const kept: ChannelRow[] = [];
  const ended: ChannelRow[] = [];
  for (const channel of rows) {
    if (channel.endedAt === null) {
      open.push(channel);
      kept.push(channel);
    } else if (isFollowable(watched.get(channel.raceId)) && now > channel.endedAt) {
      // A race followable again, like a cancellation called off, gets new channels, in
      // a run started after the end: an older run's snapshot may predate it.
      await replace(env, channel);
    } else {
      if (channel.deletedAt === null) ended.push(channel);
      kept.push(channel);
    }
  }
  if (races) {
    // The races already followed first, then the new channels.
    await updateOpenChannels(env, tokens, open, watched, now, budget);
    await openChannels(env, tokens, races, kept, now, budget);
  }
  // After the races followed in the budget, the ends least recently tried first, then the deletions.
  for (const channel of ended) await sendEnd(env, tokens, channel, now);
  await deleteRetiredChannels(env, tokens, now);
}

async function updateOpenChannels(
  env: Env,
  tokens: ProviderTokens,
  open: ChannelRow[],
  watched: Map<string, RaceSnapshot>,
  now: number,
  budget: SubrequestBudget,
) {
  // The races least recently looked up first: a budget too short for all of them takes turns among them.
  for (const [raceId, channels] of Map.groupBy(open, (row) => row.raceId)) {
    const race = watched.get(raceId);
    // A lookup waits for a run that can also broadcast its result to every channel.
    if (needsResults(race) && !budget.has(1 + channels.length)) continue;
    const known = await currentState(raceId, race, budget);
    for (const channel of channels) {
      const state: LiveState = { ...(JSON.parse(channel.state) as LiveState), ...known };
      if (!race || isTerminal(race.status)) {
        // Over, or no longer watched: the activity ends with the latest state there is.
        await end(env, tokens, channel, state, now);
      } else if (channel.deletedAt === null && JSON.stringify(state) !== channel.state) {
        await publish(env, tokens, channel, state, now);
      }
    }
    if (needsResults(race)) {
      await env.DB.prepare("UPDATE live_channels SET attempted_at = ?1 WHERE race_id = ?2 AND ended_at IS NULL")
        .bind(now, raceId)
        .run();
    }
  }
}

function isFollowable(race: RaceSnapshot | undefined): race is RaceSnapshot {
  return race?.status === "scheduled" || race?.status === "live";
}

/** Whether the race has leaders to look up: not before it starts, nor once cancelled. */
function needsResults(race: RaceSnapshot | undefined): boolean {
  return race?.status !== "scheduled" && race?.status !== "cancelled";
}

/**
 * What is known of a race now, over its last published state. The calendar decides
 * its phase and start time, which the results can lag behind or be ahead of: an ended
 * channel then always means the calendar ended the race, or stopped listing it, so a
 * race it lists as followable again gets new channels. The results give the leaders
 * of the races under way, which keep their last ones when the results can't be read
 * or don't describe the race; upcoming and cancelled races have none.
 */
async function currentState(
  raceId: string,
  race: RaceSnapshot | undefined,
  budget: SubrequestBudget,
): Promise<Partial<LiveState> | undefined> {
  if (race && !needsResults(race)) return { ...calendarFields(race), leaders: [] };
  try {
    const state = liveState(await fetchIBU<IBUResults>("Results", { RaceId: raceId }, budget));
    return { ...state, ...(race && calendarFields(race)) };
  } catch (error) {
    console.warn("Live Activity results unavailable", raceId, String(error));
    return race && calendarFields(race);
  }
}

async function openChannels(
  env: Env,
  tokens: ProviderTokens,
  races: RaceSnapshot[],
  rows: ChannelRow[],
  now: number,
  budget: SubrequestBudget,
) {
  const key = (raceId: string, environment: APNsEnvironment) => `${raceId} ${environment}`;
  const open = new Set(rows.filter((row) => !isDropped(row)).map((row) => key(row.raceId, row.environment)));
  const dropped = new Map(rows.filter(isDropped).map((row) => [key(row.raceId, row.environment), row]));
  const followable = races.filter(isFollowable);
  const missing = ENVIRONMENTS.flatMap((environment) =>
    followable
      .filter((race) => !open.has(key(race.id, environment)))
      .slice(0, MAX_CHANNEL_CREATIONS_PER_ENVIRONMENT)
      .map((race) => ({ race, environment })),
  );

  for (const { race, environment } of missing) {
    // A creation keeps a subrequest back, to delete its channel if it can't be recorded.
    if (!budget.has(2)) return;
    const outcome = await tokens.send(environment, (token) => createChannel(environment, env.APNS_TOPIC, token));
    if (outcome.kind === "deferred") return;
    if (outcome.kind !== "created") {
      console.error("APNs channel creation failed", race.id, environment, outcome);
      continue;
    }
    // A live race starts from the calendar too: its first results are published at the next run.
    // The new channel replaces a dropped one, with the leaders last published on it while the race runs.
    const stored = race.status === "live" ? dropped.get(key(race.id, environment))?.state : undefined;
    const state: LiveState = { leaders: [], ...(stored && (JSON.parse(stored) as LiveState)), ...calendarFields(race) };
    try {
      const { meta } = await env.DB.prepare(
        `INSERT INTO live_channels (race_id, environment, channel_id, state, created_at) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT (race_id, environment) DO UPDATE
         SET channel_id = excluded.channel_id, state = excluded.state, created_at = excluded.created_at, deleted_at = NULL
         WHERE ended_at IS NULL AND deleted_at IS NOT NULL`,
      )
        .bind(race.id, environment, outcome.channelId, JSON.stringify(state), now)
        .run();
      // An overlapping run recorded its channel first: this one has no row to be deleted with.
      if (meta.changes === 0) await retire(env, environment, outcome.channelId).run();
    } catch (error) {
      // Recorded nowhere, the channel would count against the limit forever: deleted before the run
      // stops, or queued for a later run, and logged in case D1 can't take it either.
      const deletion = await tokens.send(environment, (token) =>
        deleteChannel(environment, env.APNS_TOPIC, outcome.channelId, token),
      );
      if (deletion.kind !== "sent" && deletion.kind !== "unregistered") {
        console.error("APNs channel left to delete", environment, outcome.channelId, deletion);
        await retire(env, environment, outcome.channelId).run();
      }
      throw error;
    }
  }
}

async function publish(env: Env, tokens: ProviderTokens, channel: ChannelRow, state: LiveState, now: number) {
  const outcome = await send(env, tokens, channel, "update", state, now);
  if (outcome === "sent") {
    await env.DB.prepare(`UPDATE live_channels SET state = ?1 WHERE ${UNCHANGED_OPEN_CHANNEL}`)
      .bind(JSON.stringify(state), channel.raceId, channel.environment, channel.channelId, channel.state)
      .run();
  } else if (outcome === "unregistered") {
    // Dropped, whatever state an overlapping run stored since: a new channel replaces it at a
    // next run while the race is still upcoming or live, and the row keeps the state for the
    // end if the race is over first.
    await env.DB.prepare(`UPDATE live_channels SET deleted_at = ?1 WHERE ${OPEN_CHANNEL}`)
      .bind(now, channel.raceId, channel.environment, channel.channelId)
      .run();
  }
}

/** An open channel APNs no longer knows, waiting for its replacement. */
function isDropped(channel: ChannelRow): boolean {
  return channel.endedAt === null && channel.deletedAt !== null;
}

/** The open row of the channel a run read. Binds ?2 to ?4. */
const OPEN_CHANNEL = "race_id = ?2 AND environment = ?3 AND channel_id = ?4 AND ended_at IS NULL";

/**
 * Cron runs can overlap: a run only changes the row it read, while it is still open
 * and holds the state it read, so an older run never overwrites a newer state or end.
 * Binds ?2 to ?5.
 */
const UNCHANGED_OPEN_CHANNEL = `${OPEN_CHANNEL} AND state = ?5`;

/**
 * Ends the channel with the final state, recorded before the end event is sent: an
 * overlapping run that stored a newer state since, like a race reinstated, keeps the
 * channel open. The app learns the final state from the row whether the broadcast goes
 * through or not.
 */
async function end(env: Env, tokens: ProviderTokens, channel: ChannelRow, state: LiveState, now: number) {
  const { meta } = await env.DB.prepare(`UPDATE live_channels SET state = ?1, ended_at = ?6 WHERE ${UNCHANGED_OPEN_CHANNEL}`)
    .bind(JSON.stringify(state), channel.raceId, channel.environment, channel.channelId, channel.state, now)
    .run();
  // A dropped channel, already unknown to APNs, has no subscriber left to tell.
  if (meta.changes === 0 || isDropped(channel)) return;
  await sendEnd(env, tokens, { ...channel, state: JSON.stringify(state), endedAt: now, endSentAt: null }, now);
}

/** The ended row a run read, not the open one an overlapping run may have replaced it with. Binds ?2 to ?4. */
const SAME_ENDED_CHANNEL = "race_id = ?2 AND environment = ?3 AND channel_id = ?4 AND ended_at IS NOT NULL";

/**
 * Sends the end, then again for devices that were offline, and retires the channel once
 * the grace period is over. The row stays, marked deleted, for the app to learn the final state.
 */
async function sendEnd(env: Env, tokens: ProviderTokens, channel: ChannelRow, now: number) {
  const markDeleted = () =>
    env.DB.prepare(`UPDATE live_channels SET deleted_at = ?1 WHERE ${SAME_ENDED_CHANNEL}`).bind(
      now,
      channel.raceId,
      channel.environment,
      channel.channelId,
    );
  if (now - (channel.endedAt ?? now) >= END_GRACE_MS) {
    await env.DB.batch([retire(env, channel.environment, channel.channelId), markDeleted()]);
    return;
  }
  // An end never sent goes at once.
  if (channel.endSentAt !== null && now - channel.endSentAt < END_RESEND_INTERVAL_MS) return;
  const outcome = await send(env, tokens, channel, "end", JSON.parse(channel.state) as LiveState, now);
  if (outcome === "deferred") return;
  if (outcome === "unregistered") {
    await markDeleted().run();
    return;
  }
  // Tried: a failing end goes behind the others, which it can't hold back.
  await env.DB.prepare(
    `UPDATE live_channels SET attempted_at = ?1, end_sent_at = COALESCE(?5, end_sent_at) WHERE ${SAME_ENDED_CHANNEL}`,
  )
    .bind(now, channel.raceId, channel.environment, channel.channelId, outcome === "sent" ? now : null)
    .run();
}

/** Drops an ended channel's row, for a new channel to open, and retires the channel if APNs still has it. */
async function replace(env: Env, channel: ChannelRow) {
  const deleteRow = env.DB.prepare(
    "DELETE FROM live_channels WHERE race_id = ?1 AND environment = ?2 AND channel_id = ?3",
  ).bind(channel.raceId, channel.environment, channel.channelId);
  await env.DB.batch(
    channel.deletedAt === null ? [retire(env, channel.environment, channel.channelId), deleteRow] : [deleteRow],
  );
}

/** Queues a channel for its deletion at APNs (`deleteRetiredChannels`). */
function retire(env: Env, environment: APNsEnvironment, channelId: string) {
  return env.DB.prepare(
    "INSERT INTO retired_channels (environment, channel_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING",
  ).bind(environment, channelId);
}

/**
 * Deletes a few retired channels at APNs, the least recently attempted first: failed
 * deletions are retried at later runs without starving the races or the other channels.
 */
async function deleteRetiredChannels(env: Env, tokens: ProviderTokens, now: number) {
  const { results } = await env.DB.prepare(
    "SELECT environment, channel_id AS channelId FROM retired_channels ORDER BY attempted_at LIMIT ?1",
  )
    .bind(MAX_CHANNEL_DELETIONS_PER_RUN)
    .all<{ environment: APNsEnvironment; channelId: string }>();
  for (const { environment, channelId } of results) {
    const deletion = await tokens.send(environment, (token) => deleteChannel(environment, env.APNS_TOPIC, channelId, token));
    if (deletion.kind === "sent" || deletion.kind === "unregistered") {
      await env.DB.prepare("DELETE FROM retired_channels WHERE environment = ?1 AND channel_id = ?2")
        .bind(environment, channelId)
        .run();
      continue;
    }
    if (deletion.kind !== "deferred") console.error("APNs channel deletion failed", environment, channelId, deletion);
    await env.DB.prepare("UPDATE retired_channels SET attempted_at = ?3 WHERE environment = ?1 AND channel_id = ?2")
      .bind(environment, channelId, now)
      .run();
  }
}

/**
 * Broadcasts an ActivityKit event; "unregistered" when APNs no longer knows the channel,
 * "deferred" when the run has no subrequest left.
 */
async function send(
  env: Env,
  tokens: ProviderTokens,
  channel: ChannelRow,
  event: "update" | "end",
  state: LiveState,
  now: number,
): Promise<"sent" | "unregistered" | "deferred" | "failed"> {
  const payload = { aps: { timestamp: Math.floor(now / 1000), event, "content-state": state } };
  const outcome = await tokens.send(channel.environment, (token) =>
    broadcast({ environment: channel.environment, bundleId: env.APNS_TOPIC, channelId: channel.channelId, payload }, token),
  );
  if (outcome.kind === "sent" || outcome.kind === "unregistered" || outcome.kind === "deferred") return outcome.kind;
  console.error("APNs broadcast failed", channel.raceId, channel.environment, outcome);
  return "failed";
}

/**
 * The channel the app subscribes a race's Live Activity to, for its APNs environment,
 * with the state last published on it: the channel stores no messages, so a new
 * activity starts from it. Once the end is sent, which a new subscriber would miss,
 * only the final state, for the app to end the activities that missed it. None while
 * a dropped channel waits for its replacement.
 */
export async function channelFor(
  db: D1Database,
  raceId: string,
  environment: APNsEnvironment,
): Promise<{ channelId: string; state: LiveState } | { ended: LiveState } | undefined> {
  const row = await db
    .prepare(
      "SELECT channel_id AS channelId, state, ended_at AS endedAt, deleted_at AS deletedAt FROM live_channels WHERE race_id = ?1 AND environment = ?2",
    )
    .bind(raceId, environment)
    .first<{ channelId: string; state: string; endedAt: number | null; deletedAt: number | null }>();
  if (!row) return undefined;
  const state = JSON.parse(row.state) as LiveState;
  if (row.endedAt !== null) return { ended: state };
  return row.deletedAt === null ? { channelId: row.channelId, state } : undefined;
}
