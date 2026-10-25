import { DurableObject } from "cloudflare:workers";
import { broadcast, createChannel, deleteChannel, ENVIRONMENTS, type APNsEnvironment } from "./apns";
import { fetchIBU, parseIBUDate, type RaceSnapshot } from "./ibu";
import {
  ACTIVITY_LIFETIME_MS,
  broadcastTimestamp,
  calendarFields,
  dismissalDate,
  isFollowable,
  liveState,
  referenceMs,
  relevanceScore,
  type IBUResults,
  type LiveState,
} from "./live";
import { startFavoriteActivities } from "./liveStarts";
import { ProviderTokens, type ProviderTokenSet } from "./providerTokens";
import { PushLots } from "./pushLots";
import { SUBREQUESTS_PER_RUN, SubrequestBudget } from "./subrequests";

/**
 * The channels store no messages, as Apple advises for frequent updates like sports
 * scores, so a device offline when the end is sent never gets it: the end is sent
 * again at this interval, until the channel is deleted.
 */
const END_RESEND_INTERVAL_MS = 10 * 60_000;
const END_GRACE_MS = 60 * 60_000;
/** How long a failed request to APNs waits before it goes again: the cron's interval. */
const RETRY_MS = 60_000;
/**
 * How long the APNs and IBU API requests of an update may wait, at most: the object is reset
 * once an update has run 30 s (`blockConcurrencyWhile`), and a subrequest has no time limit of
 * its own. The rest is left for the D1 queries that record what the requests did.
 */
const REQUESTS_TIME_MS = 20_000;
/** The storage key of the channels left to delete at APNs (`RetiredChannel`). */
const RETIRED_KEY = "retiredChannels";

/**
 * The Live Activity of one race, in a Durable Object named after it (`getByName(raceId)`):
 * each cron run hands it the race as the calendar lists it (`sync`), and its alarm sends the
 * ends again, deletes the channels at APNs, and ends the activity of a race the calendar
 * stopped listing. The object runs one update at a time, so overlapping cron runs never
 * interleave on a race, and each invocation has its own subrequests: a race never waits
 * for another's (https://developers.cloudflare.com/workers/platform/limits/#subrequests).
 * Its channels stay in D1 (`live_channels`), which only this object writes, for the app's
 * `GET` of a race's channel: those reads would otherwise spend the 100,000 Durable Object
 * requests a day of the Workers Free plan.
 */
export class RaceActivity extends DurableObject<Env> {
  /** Brings the race's activity up to date with the race as the cron run scheduled at `now` read it. */
  async sync(race: RaceSnapshot, now: number, providerTokens: ProviderTokenSet): Promise<void> {
    const failure = await this.serialized((deadline) =>
      syncRace(this.env, this.ctx.storage, race.id, now, deadline, { race, providerTokens }),
    );
    if (failure) throw failure.error;
  }

  override async alarm(): Promise<void> {
    // The object's name, the race's id, is known in its alarms too (Cloudflare changelog, 2026-03-15).
    const raceId = this.ctx.id.name ?? "";
    const failure = await this.serialized((deadline) =>
      syncRace(this.env, this.ctx.storage, raceId, Date.now(), deadline),
    );
    if (failure) console.error("Live Activity alarm failed", raceId, String(failure.error));
  }

  /**
   * Runs `update` while no other request or alarm reaches the object: it waits on APNs and the
   * IBU API, when the object would otherwise take the next one. A failure is returned rather
   * than thrown, which would reset the object, and the alarm tries again a minute later. The
   * update's requests are given up at the deadline it is handed, before the object's time is up.
   */
  private async serialized(update: (deadline: number) => Promise<void>): Promise<{ error: unknown } | undefined> {
    let failure: { error: unknown } | undefined;
    await this.ctx.blockConcurrencyWhile(async () => {
      try {
        await update(Date.now() + REQUESTS_TIME_MS);
      } catch (error) {
        failure = { error };
        await this.ctx.storage.setAlarm(Date.now() + RETRY_MS);
      }
    });
    return failure;
  }
}

interface ChannelRow {
  raceId: string;
  environment: APNsEnvironment;
  channelId: string;
  state: string;
  publishedAt: number;
  endedAt: number | null;
  endSentAt: number | null;
  deletedAt: number | null;
  /** When its end or deletion last failed, 0 if never. */
  attemptedAt: number;
}

/** A channel of the race to delete at APNs, kept in the object's storage until it is. */
interface RetiredChannel {
  environment: APNsEnvironment;
  channelId: string;
  /** When its deletion last failed, 0 if never. */
  attemptedAt: number;
}

/**
 * Updates the race's activity at `now`: with the race as a cron run's calendar `listed` it, or
 * from an alarm without. A race followable opens a channel per APNs environment, and each new
 * state of the race is broadcast on them; a race over, or unlisted for longer than its activity
 * can last, has its activity ended. The activity then starts on the devices whose favorites
 * race (liveStarts.ts), the ends are sent, again for the devices that were offline, and the
 * channels are deleted at APNs an hour after; the alarm is set for the next of them. The requests
 * still unanswered at `deadline` are given up, for a later update.
 */
export async function syncRace(
  env: Env,
  storage: DurableObjectStorage,
  raceId: string,
  now: number,
  deadline: number,
  listed?: { race: RaceSnapshot; providerTokens: ProviderTokenSet },
): Promise<void> {
  const rows = await readChannels(env.DB, raceId);
  // A run started before the latest state recorded, which a newer run read from a newer calendar.
  if (listed && rows.some((row) => Math.max(row.publishedAt, row.endedAt ?? 0) > now)) return;
  const budget = new SubrequestBudget(SUBREQUESTS_PER_RUN, deadline);
  const tokens = new ProviderTokens(env, now, budget, listed?.providerTokens);
  const results = lazyResults(raceId, budget);
  const race = listed?.race;
  const followed = race && isFollowable(race) && now < parseIBUDate(race.startTime) + ACTIVITY_LIFETIME_MS;
  if (followed) {
    await follow(env, storage, tokens, race, rows, results, now);
  } else {
    const over = rows.filter((row) => row.endedAt === null && (race || !mayStillBeShown(row, now)));
    if (over.length > 0) await end(env.DB, over, await currentState(raceId, race, results), now);
  }
  const current = await readChannels(env.DB, raceId);
  if (followed) {
    const open = current.filter((row) => row.endedAt === null && !isDropped(row));
    await startFavoriteActivities(
      env,
      race,
      open.map(({ environment, channelId, state }) => ({
        environment,
        channelId,
        state: JSON.parse(state) as LiveState,
      })),
      results,
      now,
      new PushLots(env, tokens),
    );
  }
  await sendEnds(env, tokens, current, now);
  const retired = await deleteRetired(env, storage, tokens, now);
  await schedule(storage, current, retired, now);
}

async function readChannels(db: D1Database, raceId: string): Promise<ChannelRow[]> {
  const { results } = await db
    .prepare(
      `SELECT race_id AS raceId, environment, channel_id AS channelId, state, published_at AS publishedAt,
         ended_at AS endedAt, end_sent_at AS endSentAt, deleted_at AS deletedAt, attempted_at AS attemptedAt
       FROM live_channels WHERE race_id = ?1 ORDER BY environment`,
    )
    .bind(raceId)
    .all<ChannelRow>();
  return results;
}

/** The race's results, read once per update, if at all. */
function lazyResults(raceId: string, budget: SubrequestBudget): () => Promise<IBUResults> {
  let results: Promise<IBUResults> | undefined;
  return () => (results ??= fetchIBU<IBUResults>("Results", { RaceId: raceId }, budget));
}

/**
 * Broadcasts the race's new state on its open channels, and opens those it lacks, replacing
 * the ended ones of a race followable again, like a cancellation called off, and those APNs
 * no longer knows.
 */
async function follow(
  env: Env,
  storage: DurableObjectStorage,
  tokens: ProviderTokens,
  race: RaceSnapshot,
  rows: ChannelRow[],
  results: () => Promise<IBUResults>,
  now: number,
) {
  const reinstated = rows.filter((row) => row.endedAt !== null && now > row.endedAt);
  if (reinstated.length > 0) {
    retire(
      storage,
      reinstated.filter((row) => row.deletedAt === null),
    );
    await env.DB.batch(
      reinstated.map((row) =>
        env.DB.prepare("DELETE FROM live_channels WHERE race_id = ?1 AND environment = ?2").bind(
          row.raceId,
          row.environment,
        ),
      ),
    );
  }
  const known = await currentState(race.id, race, results);
  const kept = rows.filter((row) => !reinstated.includes(row));
  for (const row of kept) {
    if (row.endedAt === null)
      await publish(env, tokens, row, { ...(JSON.parse(row.state) as LiveState), ...known }, now);
  }
  for (const environment of ENVIRONMENTS) {
    const row = kept.find((channel) => channel.environment === environment);
    if (row && !isDropped(row)) continue;
    // A dropped channel's replacement starts from its state, which keeps the leaders when the results can't be read.
    const state: LiveState = row
      ? (JSON.parse(row.state) as LiveState)
      : { leaders: [], ...known, ...calendarFields(race) };
    await openChannel(env, storage, tokens, race.id, environment, state, now);
  }
}

/**
 * Broadcasts the new state and records it. A channel APNs no longer knows only records it,
 * dropped: its replacement starts from it.
 */
async function publish(env: Env, tokens: ProviderTokens, row: ChannelRow, state: LiveState, now: number) {
  const stored = JSON.stringify(state);
  if (stored === row.state) return;
  if (!isDropped(row)) {
    const outcome = await send(env, tokens, row, { event: "update" }, state, now);
    if (outcome === "unregistered") row.deletedAt = now;
    else if (outcome !== "sent") return;
  }
  await env.DB.prepare(
    "UPDATE live_channels SET state = ?1, published_at = ?2, deleted_at = ?3 WHERE race_id = ?4 AND environment = ?5",
  )
    .bind(stored, now, row.deletedAt, row.raceId, row.environment)
    .run();
  row.state = stored;
}

/** Opens the race's channel for `environment`, replacing a dropped one, with `state`. */
async function openChannel(
  env: Env,
  storage: DurableObjectStorage,
  tokens: ProviderTokens,
  raceId: string,
  environment: APNsEnvironment,
  state: LiveState,
  now: number,
) {
  const outcome = await tokens.send(environment, (token, signal) =>
    createChannel(environment, env.APNS_TOPIC, token, signal),
  );
  if (outcome.kind !== "created") {
    if (outcome.kind !== "deferred") console.error("APNs channel creation failed", raceId, environment, outcome);
    return;
  }
  try {
    await env.DB.prepare(
      `INSERT INTO live_channels (race_id, environment, channel_id, state, published_at, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?5)
       ON CONFLICT (race_id, environment) DO UPDATE
       SET channel_id = excluded.channel_id, state = excluded.state, published_at = excluded.published_at,
         created_at = excluded.created_at, deleted_at = NULL`,
    )
      .bind(raceId, environment, outcome.channelId, JSON.stringify(state), now)
      .run();
  } catch (error) {
    // Recorded nowhere, the channel would count against the limit of 10,000 forever: deleted at
    // once, or retired for a later alarm.
    if ((await deleteAtAPNs(env, tokens, environment, outcome.channelId)) !== "deleted") {
      retire(storage, [{ environment, channelId: outcome.channelId }]);
    }
    throw error;
  }
}

/** An open channel APNs no longer knows, waiting for its replacement. */
function isDropped(row: ChannelRow): boolean {
  return row.endedAt === null && row.deletedAt !== null;
}

/**
 * Whether the activity of this channel's race may still be on screen (`ACTIVITY_LIFETIME_MS`):
 * a race the calendar stops listing, which a partial response can do, keeps it until then.
 */
function mayStillBeShown(row: ChannelRow, now: number): boolean {
  return now < referenceMs((JSON.parse(row.state) as LiveState).startTime) + ACTIVITY_LIFETIME_MS;
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
  results: () => Promise<IBUResults>,
): Promise<Partial<LiveState>> {
  if (race && !needsResults(race)) return { ...calendarFields(race), leaders: [] };
  try {
    return { ...liveState(await results()), ...(race && calendarFields(race)) };
  } catch (error) {
    console.warn("Live Activity results unavailable", raceId, String(error));
    return race ? calendarFields(race) : {};
  }
}

/**
 * Ends the channels with the final state, which the app learns from their rows whether the
 * end goes through or not: `sendEnds` sends it, but on a dropped channel, already unknown to
 * APNs, which has no subscriber left to tell.
 */
async function end(db: D1Database, rows: ChannelRow[], known: Partial<LiveState>, now: number) {
  await db.batch(
    rows.map((row) =>
      db
        .prepare(
          `UPDATE live_channels SET state = ?1, published_at = ?2, ended_at = ?2, attempted_at = 0
           WHERE race_id = ?3 AND environment = ?4`,
        )
        .bind(JSON.stringify({ ...(JSON.parse(row.state) as LiveState), ...known }), now, row.raceId, row.environment),
    ),
  );
}

/**
 * When the ended channel is next due: its end, at once then every `END_RESEND_INTERVAL_MS`, or
 * its deletion after `END_GRACE_MS`, a failed attempt waiting `RETRY_MS`.
 */
function endDue(row: ChannelRow): number {
  const planned =
    row.endSentAt === null ? 0 : Math.min(row.endSentAt + END_RESEND_INTERVAL_MS, (row.endedAt ?? 0) + END_GRACE_MS);
  return Math.max(planned, row.attemptedAt + RETRY_MS);
}

/**
 * Sends the ends that are due, for the devices that were offline too, and deletes the channels
 * at APNs once the grace period is over. The rows stay, marked deleted, for the app to learn
 * the final state.
 */
async function sendEnds(env: Env, tokens: ProviderTokens, rows: ChannelRow[], now: number) {
  for (const row of rows) {
    if (row.endedAt === null || row.deletedAt !== null || endDue(row) > now) continue;
    const outcome = await (now - row.endedAt >= END_GRACE_MS
      ? deleteAtAPNs(env, tokens, row.environment, row.channelId)
      : send(
          env,
          tokens,
          row,
          { event: "end", "dismissal-date": dismissalDate(row.endedAt) },
          JSON.parse(row.state) as LiveState,
          now,
        ));
    if (outcome === "deferred") continue;
    if (outcome === "deleted" || outcome === "unregistered") row.deletedAt = now;
    else {
      if (outcome === "sent") row.endSentAt = now;
      row.attemptedAt = now;
    }
    await env.DB.prepare(
      "UPDATE live_channels SET end_sent_at = ?1, deleted_at = ?2, attempted_at = ?3 WHERE race_id = ?4 AND environment = ?5",
    )
      .bind(row.endSentAt, row.deletedAt, row.attemptedAt, row.raceId, row.environment)
      .run();
  }
}

/** Deletes a channel at APNs, "deleted" too when APNs no longer knew it. */
async function deleteAtAPNs(
  env: Env,
  tokens: ProviderTokens,
  environment: APNsEnvironment,
  channelId: string,
): Promise<"deleted" | "deferred" | "failed"> {
  const deletion = await tokens.send(environment, (token, signal) =>
    deleteChannel(environment, env.APNS_TOPIC, channelId, token, signal),
  );
  if (deletion.kind === "sent" || deletion.kind === "unregistered") return "deleted";
  if (deletion.kind === "deferred") return "deferred";
  console.error("APNs channel deletion failed", environment, channelId, deletion);
  return "failed";
}

/** Queues the channels for their deletion at APNs (`deleteRetired`). */
function retire(storage: DurableObjectStorage, channels: Pick<RetiredChannel, "environment" | "channelId">[]) {
  if (channels.length === 0) return;
  const retired = storage.kv.get<RetiredChannel[]>(RETIRED_KEY) ?? [];
  const added = channels.filter((channel) => !retired.some((known) => known.channelId === channel.channelId));
  storage.kv.put(RETIRED_KEY, [
    ...retired,
    ...added.map(({ environment, channelId }) => ({ environment, channelId, attemptedAt: 0 })),
  ]);
}

/** Deletes the retired channels at APNs that are due, and returns those left. */
async function deleteRetired(
  env: Env,
  storage: DurableObjectStorage,
  tokens: ProviderTokens,
  now: number,
): Promise<RetiredChannel[]> {
  const retired = storage.kv.get<RetiredChannel[]>(RETIRED_KEY) ?? [];
  if (retired.length === 0) return retired;
  const left: RetiredChannel[] = [];
  for (const channel of retired) {
    if (channel.attemptedAt + RETRY_MS > now) {
      left.push(channel);
      continue;
    }
    const deletion = await deleteAtAPNs(env, tokens, channel.environment, channel.channelId);
    if (deletion === "deferred") left.push(channel);
    else if (deletion === "failed") left.push({ ...channel, attemptedAt: now });
  }
  if (left.length > 0) storage.kv.put(RETIRED_KEY, left);
  else storage.kv.delete(RETIRED_KEY);
  return left;
}

/**
 * Sets the alarm for the next end, deletion or retry due, or for the end of the activity of a
 * race followed, in case the calendar stops listing it; none once the race needs nothing more.
 */
async function schedule(storage: DurableObjectStorage, rows: ChannelRow[], retired: RetiredChannel[], now: number) {
  const times = [
    ...rows.filter((row) => row.endedAt !== null && row.deletedAt === null).map(endDue),
    ...rows
      .filter((row) => row.endedAt === null)
      .map((row) => referenceMs((JSON.parse(row.state) as LiveState).startTime) + ACTIVITY_LIFETIME_MS),
    ...retired.map((channel) => channel.attemptedAt + RETRY_MS),
  ];
  const alarm = await storage.getAlarm();
  if (times.length === 0) {
    if (alarm !== null) await storage.deleteAlarm();
    return;
  }
  // What is due already, a request the update had no subrequest left for, waits for the next try.
  const next = Math.max(Math.min(...times), now + RETRY_MS);
  if (alarm !== next) await storage.setAlarm(next);
}

/**
 * Broadcasts an ActivityKit event; "unregistered" when APNs no longer knows the channel,
 * "deferred" when the update has no subrequest left.
 */
async function send(
  env: Env,
  tokens: ProviderTokens,
  row: ChannelRow,
  event: { event: "update" } | { event: "end"; "dismissal-date": number },
  state: LiveState,
  now: number,
): Promise<"sent" | "unregistered" | "deferred" | "failed"> {
  const payload = {
    aps: {
      timestamp: broadcastTimestamp(now),
      ...event,
      "relevance-score": relevanceScore(state),
      "content-state": state,
    },
  };
  const outcome = await tokens.send(row.environment, (token, signal) =>
    broadcast(
      { environment: row.environment, bundleId: env.APNS_TOPIC, channelId: row.channelId, payload },
      token,
      signal,
    ),
  );
  if (outcome.kind === "sent" || outcome.kind === "unregistered" || outcome.kind === "deferred") return outcome.kind;
  console.error("APNs broadcast failed", row.raceId, row.environment, outcome);
  return "failed";
}
