import { isEnvironment, type APNsEnvironment, type PushOutcome } from "./apns";
import { parseIBUDate, type RaceSnapshot } from "./ibu";
import { isFollowable, relevanceScore, type IBUResults, type LiveState } from "./live";
import { LOC_KEYS, raceTitleKey } from "./payload";
import type { Deferred } from "./providerTokens";
import { MAX_SEND_ATTEMPTS, type PushLots } from "./pushLots";
import type { LotPush } from "./pushSender";

/**
 * Live Activities started by the server when a favorite races, for the devices that turned
 * it on: Apple's example of push-to-start, "if someone starts a Live Activity to track
 * their favorite sports team, the sports app might offer to automatically start a Live
 * Activity for each of the team's games" ("Starting and updating Live Activities with
 * ActivityKit push notifications"). The app sends its push-to-start token with its
 * favorites; shortly before a race, each device with a favorite on the start list gets a
 * start push subscribing the new activity to the race's broadcast channel (raceActivity.ts).
 */

export interface StartRegistration {
  token: string;
  environment: APNsEnvironment;
  /** IBU ids. */
  athletes: string[];
  /** IOC codes. */
  nations: string[];
}

/** Favorites per kind a device may send: far more than anyone follows. */
const MAX_FAVORITES = 500;
/** The activity starts this long before the race, like one the app schedules (`RaceLiveState.activityLead`). */
const START_LEAD_MS = 30 * 60_000;
/**
 * How long after the race's start APNs keeps a start for a device that is offline: later, it
 * would show an outdated state, the race being well under way.
 */
const START_EXPIRATION_S = 15 * 60;
/** The attributes type the payload names, which ActivityKit decodes `attributes` into. */
const ATTRIBUTES_TYPE = "RaceActivityAttributes";

const ATHLETE_PATTERN = /^[A-Z0-9]{1,32}$/;
const NATION_PATTERN = /^[A-Z]{3}$/;

/** Validates the JSON body of `PUT /v1/live-activity-starts/:token`, for a token `isDeviceToken` accepted. */
export function parseStartRegistration(token: string, body: unknown): StartRegistration | string {
  if (typeof body !== "object" || body === null) return "body must be a JSON object";
  const input = body as Record<string, unknown>;
  if (!isEnvironment(input.environment)) return "invalid environment";
  const athletes = codes(input.athletes, ATHLETE_PATTERN);
  const nations = codes(input.nations, NATION_PATTERN);
  if (!athletes || !nations) return "athletes and nations must be arrays of IBU ids and IOC codes";
  // Without favorites, the app deletes its token instead.
  if (athletes.length + nations.length === 0) return "no favorites";
  return { token, environment: input.environment, athletes, nations };
}

function codes(value: unknown, pattern: RegExp): string[] | undefined {
  if (!Array.isArray(value) || value.length > MAX_FAVORITES) return undefined;
  if (!value.every((code) => typeof code === "string" && pattern.test(code))) return undefined;
  return [...new Set(value as string[])].sort();
}

/**
 * Saves the favorites for the App Attest key that signed the request, with one token per key
 * like `saveDevice`. Changed favorites check again the races the previous ones started nothing for.
 */
export async function saveStartToken(
  db: D1Database,
  registration: StartRegistration,
  keyId: string,
  now: number,
): Promise<void> {
  const athletes = JSON.stringify(registration.athletes);
  const nations = JSON.stringify(registration.nations);
  await db.batch([
    // Read before the upsert: the app sends its favorites at every launch, mostly unchanged.
    db
      .prepare(
        `DELETE FROM live_starts WHERE app_attest_key_id = ?1 AND channel_id IS NULL AND NOT EXISTS (
           SELECT 1 FROM live_start_tokens
           WHERE app_attest_key_id = ?1 AND environment = ?2 AND athletes = ?3 AND nations = ?4)`,
      )
      .bind(keyId, registration.environment, athletes, nations),
    db
      .prepare("DELETE FROM live_start_tokens WHERE app_attest_key_id = ?1 AND token <> ?2")
      .bind(keyId, registration.token),
    db
      .prepare(
        `INSERT INTO live_start_tokens (token, environment, athletes, nations, updated_at, app_attest_key_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (token) DO UPDATE SET
           environment = excluded.environment, athletes = excluded.athletes, nations = excluded.nations,
           updated_at = excluded.updated_at
         WHERE live_start_tokens.app_attest_key_id = excluded.app_attest_key_id`,
      )
      .bind(registration.token, registration.environment, athletes, nations, now, keyId),
  ]);
}

/** Whether `keyId` may change the favorites saved with `token`: those it saved, or none yet (see `ownsDevice`). */
export async function ownsStartToken(db: D1Database, token: string, keyId: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT app_attest_key_id AS keyId FROM live_start_tokens WHERE token = ?1")
    .bind(token)
    .first<{ keyId: string }>();
  return row === null || row.keyId === keyId;
}

/**
 * Deletes the favorites `keyId` saved, whatever token the app sends: ActivityKit may have
 * replaced the one the server holds before the app could send the new one. `ownsStartToken`
 * first checks the token sent isn't another key's.
 */
export async function deleteOwnedStartToken(db: D1Database, _token: string, keyId: string): Promise<void> {
  await db.prepare("DELETE FROM live_start_tokens WHERE app_attest_key_id = ?1").bind(keyId).run();
}

interface PendingToken {
  token: string;
  environment: APNsEnvironment;
  keyId: string;
}

/**
 * Whether the check `s` started the activity of its install on one of the race's open channels
 * ?3 (a JSON array): one replacing a dropped or ended channel starts it again, the activity
 * getting none of the new channel's broadcasts.
 */
const STARTED = "s.channel_id IN (SELECT value FROM json_each(?3))";

/** Whether the start of the check `s` failed too many times to be sent again. */
const EXHAUSTED = `s.attempts >= ${MAX_SEND_ATTEMPTS}`;

/**
 * The tokens `t` of the environments ?2 (a JSON array) whose install race ?1 started nothing
 * for, unless it was checked against the entrants ?6 (their `digest`) or its start was given up.
 */
const UNCHECKED = `t.environment IN (SELECT value FROM json_each(?2))
  AND t.app_attest_key_id NOT IN (
    SELECT s.app_attest_key_id FROM live_starts s WHERE s.race_id = ?1 AND (${STARTED} OR s.entrants = ?6 OR ${EXHAUSTED}))`;

/** Whether one of the favorites of `t` is among the athletes ?4 or the nations ?5 (JSON arrays). */
const ENTERED = `(EXISTS (SELECT 1 FROM json_each(t.athletes) WHERE value IN (SELECT value FROM json_each(?4)))
  OR EXISTS (SELECT 1 FROM json_each(t.nations) WHERE value IN (SELECT value FROM json_each(?5))))`;

/** One of the race's open channels, with the state last published on it. */
export interface OpenChannel {
  environment: APNsEnvironment;
  channelId: string;
  state: LiveState;
}

/**
 * Starts the race's activity, once it is due within `START_LEAD_MS` and until it is over, on
 * the devices whose favorites are on its start list and that it wasn't checked for, on its
 * open `channels`. Called by the race's Durable Object, one update at a time: the starts of a
 * race never overlap. A race waits for its start list; what the run's pushes can't cover, for
 * the next run.
 */
export async function startFavoriteActivities(
  env: Env,
  race: RaceSnapshot,
  channels: OpenChannel[],
  results: () => Promise<IBUResults>,
  now: number,
  lots: PushLots,
): Promise<void> {
  if (!isFollowable(race) || now < parseIBUDate(race.startTime) - START_LEAD_MS || channels.length === 0) return;
  const environments = JSON.stringify(channels.map((channel) => channel.environment));
  const channelIds = JSON.stringify(channels.map((channel) => channel.channelId));
  // Until the race starts, its start list can change: the installs it started nothing for
  // are checked again against each new one. Its entrants are then known.
  const unchecked = await env.DB.prepare(
    `SELECT 1 FROM live_start_tokens t WHERE t.environment IN (SELECT value FROM json_each(?2))
       AND t.app_attest_key_id NOT IN (
         SELECT s.app_attest_key_id FROM live_starts s WHERE s.race_id = ?1 AND (${STARTED} OR (s.entrants IS NOT NULL AND ?4) OR ${EXHAUSTED}))
     LIMIT 1`,
  )
    .bind(race.id, environments, channelIds, race.status === "scheduled" ? 0 : 1)
    .first();
  if (!unchecked || lots.room === 0) return;
  const entrants = await startList(race, results);
  if (!entrants) return;

  // Matched in D1 against the favorites stored when each statement runs: one write for all
  // the installs none of whose favorites races, then each start claimed only if it still matches.
  const lists = [JSON.stringify(entrants.athletes), JSON.stringify(entrants.nations)];
  const checked = await digest(lists);
  await env.DB.prepare(
    `INSERT INTO live_starts (race_id, app_attest_key_id, channel_id, entrants)
     SELECT ?1, t.app_attest_key_id, NULL, ?6 FROM live_start_tokens t WHERE ${UNCHECKED} AND NOT ${ENTERED}
     ON CONFLICT DO UPDATE SET channel_id = NULL, entrants = excluded.entrants`,
  )
    .bind(race.id, environments, channelIds, ...lists, checked)
    .run();
  const { results: pending } = await env.DB.prepare(
    `SELECT token, environment, app_attest_key_id AS keyId FROM live_start_tokens t
     WHERE ${UNCHECKED} AND ${ENTERED} ORDER BY updated_at, token`,
  )
    .bind(race.id, environments, channelIds, ...lists, checked)
    .all<PendingToken>();

  // Claimed before the pushes: a device whose favorites or opt-out were saved meanwhile is skipped.
  const claims = await claim(env, race.id, channels, pending.slice(0, lots.room), lists);
  const outcomes = claims.map((claimed) => lots.send(startPush(env, race, claimed, now)));
  await lots.flush();
  await settle(env, race.id, claims, await Promise.all(outcomes));
}

function startPush(env: Env, race: RaceSnapshot, claimed: Claim, now: number): LotPush {
  return {
    deviceToken: claimed.token,
    environment: claimed.environment,
    topic: `${env.APNS_TOPIC}.push-type.liveactivity`,
    pushType: "liveactivity",
    expiration: Math.floor(Math.max(now, parseIBUDate(race.startTime)) / 1000) + START_EXPIRATION_S,
    payload: startPayload(race, claimed.channelId, claimed.state, now),
  };
}

/**
 * Gives the starts that didn't go through back to a later run, and forgets the tokens APNs no
 * longer knows, in one D1 batch of at most three statements, whatever the number of starts.
 */
async function settle(env: Env, raceId: string, claims: Claim[], outcomes: (PushOutcome | Deferred)[]): Promise<void> {
  const unsent: Claim[] = [];
  const failed: Claim[] = [];
  const unregistered: string[] = [];
  claims.forEach((claimed, index) => {
    const outcome = outcomes[index]!;
    switch (outcome.kind) {
      case "sent":
        break;
      case "unregistered":
        unsent.push(claimed);
        unregistered.push(claimed.token);
        break;
      case "deferred":
        // Not sent: the run had no provider token to send it with.
        unsent.push(claimed);
        break;
      case "retry":
      case "expiredProviderToken":
        // The APNs key or clock may be fixed by the next run.
        console.warn("APNs Live Activity start retry", raceId, outcome);
        failed.push(claimed);
        break;
      default:
        // Refused, the claim stays: sent again, it would be refused again.
        console.error("APNs Live Activity start failed", raceId, outcome);
    }
  });
  const statements = [
    ...(unsent.length > 0 ? [release(env, raceId, unsent, 0)] : []),
    ...(failed.length > 0 ? [release(env, raceId, failed, 1)] : []),
    ...(unregistered.length > 0
      ? [
          env.DB.prepare("DELETE FROM live_start_tokens WHERE token IN (SELECT value FROM json_each(?1))").bind(
            JSON.stringify(unregistered),
          ),
        ]
      : []),
  ];
  if (statements.length > 0) await env.DB.batch(statements);
}

/**
 * The athletes and nations on the race's start list, or in its results once it is live;
 * `undefined` until the API marks the list as published, or when it can't be read.
 */
async function startList(
  race: RaceSnapshot,
  results: () => Promise<IBUResults>,
): Promise<{ athletes: string[]; nations: string[] } | undefined> {
  try {
    const list = await results();
    const rows = list.Results ?? [];
    // Before the race, rows may be preliminary until they are the start list.
    if (rows.length === 0 || (race.status === "scheduled" && !list.IsStartList)) return undefined;
    return {
      // Sorted, for their `digest`.
      athletes: [...new Set(rows.flatMap((row) => (row.IBUId ? [row.IBUId] : [])))].sort(),
      nations: [...new Set(rows.flatMap((row) => (row.Nat ? [row.Nat] : [])))].sort(),
    };
  } catch (error) {
    console.warn("Start list unavailable", race.id, String(error));
    return undefined;
  }
}

/** Identifies the entrants `lists` a check was made against, in hex. */
async function digest(lists: string[]): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(lists)));
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/**
 * Apple's start payload: `event` start, an alert so the new activity doesn't surprise anyone,
 * `attributes-type` and `attributes`, and `input-push-channel` (iOS 18) to subscribe it to the
 * race's channel. The attributes decode into `RaceActivityAttributes` with the default
 * `Codable` strategies; `scheduledStart` stays absent, the activity showing at once.
 */
function startPayload(race: RaceSnapshot, channelId: string, state: LiveState, now: number) {
  const titleKey = raceTitleKey(race.id);
  return {
    aps: {
      timestamp: Math.floor(now / 1000),
      event: "start",
      "relevance-score": relevanceScore(state),
      "content-state": state,
      "attributes-type": ATTRIBUTES_TYPE,
      attributes: { raceID: race.id, name: race.name, channelID: channelId },
      "input-push-channel": channelId,
      alert: {
        title: titleKey ? { "loc-key": titleKey } : race.name,
        body: { "loc-key": LOC_KEYS.liveActivityStart },
        sound: "default",
      },
    },
  };
}

interface Claim extends PendingToken {
  raceId: string;
  channelId: string;
  /** The state last published on the channel, which the new activity starts from: it gets only the broadcasts sent after. */
  state: LiveState;
}

/**
 * Claims the start of the race on its channel for each device's install, while the stored
 * token still has a favorite among the entrants `lists`. One set-based statement, whatever
 * the number of devices: one of the 50 D1 queries per invocation the Workers Free plan
 * allows (https://developers.cloudflare.com/d1/platform/limits/).
 */
async function claim(
  env: Env,
  raceId: string,
  channels: OpenChannel[],
  devices: PendingToken[],
  lists: string[],
): Promise<Claim[]> {
  if (devices.length === 0) return [];
  const byEnvironment = Object.fromEntries(channels.map((channel) => [channel.environment, channel.channelId]));
  const { results } = await env.DB.prepare(
    `INSERT INTO live_starts (race_id, app_attest_key_id, channel_id, entrants)
     SELECT ?1, t.app_attest_key_id, ?2 ->> t.environment, NULL FROM live_start_tokens t
     WHERE t.token IN (SELECT value FROM json_each(?3)) AND ${ENTERED}
     ON CONFLICT DO UPDATE SET channel_id = excluded.channel_id, entrants = NULL
     RETURNING app_attest_key_id AS keyId`,
  )
    .bind(raceId, JSON.stringify(byEnvironment), JSON.stringify(devices.map((device) => device.token)), ...lists)
    .all<{ keyId: string }>();
  const keys = new Set(results.map((row) => row.keyId));
  return devices.flatMap((device) => {
    const channel = channels.find((open) => open.environment === device.environment);
    if (!keys.has(device.keyId) || !channel) return [];
    return [{ ...device, raceId, channelId: channel.channelId, state: channel.state }];
  });
}

/**
 * How long a race's checks are kept: past this, it can't be followed any more, its activity
 * lasting at most 12 hours (live.ts), nor reinstated.
 */
const START_RETENTION_MS = 48 * 60 * 60_000;

/**
 * How long the favorites of an app that isn't launched any more are kept, an uninstall telling
 * the server nothing: a season and its break, for those who follow it on the Lock Screen only.
 */
const START_TOKEN_LIFETIME_MS = 365 * 24 * 60 * 60_000;

/**
 * Deletes the checks of the races that started more than two days ago, and the favorites no
 * launch of the app sent again for a year (the app sends them at every launch).
 */
export async function pruneStarts(db: D1Database, now: number): Promise<void> {
  await db.batch([
    db
      .prepare("DELETE FROM live_starts WHERE race_id IN (SELECT id FROM races WHERE start_time < ?1)")
      .bind(new Date(now - START_RETENTION_MS).toISOString()),
    db.prepare("DELETE FROM live_start_tokens WHERE updated_at < ?1").bind(now - START_TOKEN_LIFETIME_MS),
  ]);
}

/**
 * Gives the starts `claims` of the race that didn't go through back to a later run, counting
 * the `failed` send. Their rows are kept, for one write rather than a delete and an insert at
 * each retry.
 */
function release(env: Env, raceId: string, claims: Claim[], failed: 0 | 1): D1PreparedStatement {
  return env.DB.prepare(
    `UPDATE live_starts SET channel_id = NULL, attempts = attempts + ?3
     WHERE race_id = ?1 AND app_attest_key_id IN (SELECT value FROM json_each(?2))`,
  ).bind(raceId, JSON.stringify(claims.map((claimed) => claimed.keyId)), failed);
}
