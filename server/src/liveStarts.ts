import { isEnvironment, sendPush, type APNsEnvironment } from "./apns";
import { isDeviceToken } from "./devices";
import { fetchIBU, parseIBUDate, type RaceSnapshot } from "./ibu";
import { isFollowable, relevanceScore, type IBUResults, type LiveState } from "./live";
import { LOC_KEYS } from "./payload";
import { ProviderTokens } from "./providerTokens";
import { SubrequestBudget } from "./subrequests";

/**
 * Live Activities started by the server when a favorite races, for the devices that turned
 * it on: Apple's example of push-to-start, "if someone starts a Live Activity to track
 * their favorite sports team, the sports app might offer to automatically start a Live
 * Activity for each of the team's games" ("Starting and updating Live Activities with
 * ActivityKit push notifications"). The app sends its push-to-start token with its
 * favorites; shortly before a race, each device with a favorite on the start list gets a
 * start push subscribing the new activity to the race's broadcast channel (live.ts).
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
/** A start delivered later than this would show an outdated state: the race may be well under way. */
const START_EXPIRATION_S = 15 * 60;
/** The attributes type the payload names, which ActivityKit decodes `attributes` into. */
const ATTRIBUTES_TYPE = "RaceActivityAttributes";

const ATHLETE_PATTERN = /^[A-Z0-9]{1,32}$/;
const NATION_PATTERN = /^[A-Z]{3}$/;

/** Validates the JSON body of `PUT /v1/live-activity-starts/:token`. */
export function parseStartRegistration(token: string, body: unknown): StartRegistration | string {
  const normalized = token.toLowerCase();
  if (!isDeviceToken(normalized)) return "invalid push-to-start token";
  if (typeof body !== "object" || body === null) return "body must be a JSON object";
  const input = body as Record<string, unknown>;
  if (!isEnvironment(input.environment)) return "invalid environment";
  const athletes = codes(input.athletes, ATHLETE_PATTERN);
  const nations = codes(input.nations, NATION_PATTERN);
  if (!athletes || !nations) return "athletes and nations must be arrays of IBU ids and IOC codes";
  // Without favorites, the app deletes its token instead.
  if (athletes.length + nations.length === 0) return "no favorites";
  return { token: normalized, environment: input.environment, athletes, nations };
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
export async function saveStartToken(db: D1Database, registration: StartRegistration, keyId: string, now: number): Promise<void> {
  const athletes = JSON.stringify(registration.athletes);
  const nations = JSON.stringify(registration.nations);
  await db.batch([
    // Read before the upsert: the app sends its favorites at every launch, mostly unchanged.
    db
      .prepare(
        `DELETE FROM live_starts WHERE app_attest_key_id = ?1 AND started = 0 AND NOT EXISTS (
           SELECT 1 FROM live_start_tokens
           WHERE app_attest_key_id = ?1 AND environment = ?2 AND athletes = ?3 AND nations = ?4)`,
      )
      .bind(keyId, registration.environment, athletes, nations),
    db.prepare("DELETE FROM live_start_tokens WHERE app_attest_key_id = ?1 AND token <> ?2").bind(keyId, registration.token),
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
  keyId: string;
  environment: APNsEnvironment;
  athletes: string;
  nations: string;
}

/**
 * Starts the activity of each race due within `START_LEAD_MS`, until it is over, on the
 * devices whose favorites are on its start list and that it wasn't checked for. A race
 * waits for its channel, and for its start list; what the budget can't cover, for the next run.
 */
export async function startFavoriteActivities(
  env: Env,
  races: RaceSnapshot[],
  now: number,
  budget = new SubrequestBudget(),
): Promise<void> {
  const tokens = new ProviderTokens(env, now, budget);
  const due = races.filter((race) => isFollowable(race) && now >= parseIBUDate(race.startTime) - START_LEAD_MS);
  for (const race of due) {
    const { results: channels } = await env.DB.prepare(
      `SELECT environment, channel_id AS channelId, state FROM live_channels
       WHERE race_id = ?1 AND ended_at IS NULL AND deleted_at IS NULL`,
    )
      .bind(race.id)
      .all<{ environment: APNsEnvironment; channelId: string; state: string }>();
    const { results: pending } = await env.DB.prepare(
      `SELECT token, app_attest_key_id AS keyId, environment, athletes, nations FROM live_start_tokens
       WHERE environment IN (SELECT value FROM json_each(?2))
         AND app_attest_key_id NOT IN (SELECT app_attest_key_id FROM live_starts WHERE race_id = ?1)
       ORDER BY updated_at, token`,
    )
      .bind(race.id, JSON.stringify(channels.map((channel) => channel.environment)))
      .all<PendingToken>();
    if (pending.length === 0) continue;
    // The start list, then at least one start.
    if (!budget.has(2)) return;
    const entrants = await startList(race.id, budget);
    if (!entrants) continue;

    for (const device of pending) {
      const isEntered =
        (JSON.parse(device.athletes) as string[]).some((id) => entrants.athletes.has(id)) ||
        (JSON.parse(device.nations) as string[]).some((nation) => entrants.nations.has(nation));
      if (!isEntered) {
        await claim(env, race.id, device.keyId, false);
        continue;
      }
      // Claimed before the push: an overlapping run that read the same pending token skips it.
      if (!(await claim(env, race.id, device.keyId, true))) continue;
      const channel = channels.find((row) => row.environment === device.environment)!;
      const state = JSON.parse(channel.state) as LiveState;
      const outcome = await tokens.send(device.environment, (token) =>
        sendPush(
          {
            deviceToken: device.token,
            environment: device.environment,
            topic: `${env.APNS_TOPIC}.push-type.liveactivity`,
            pushType: "liveactivity",
            expiration: Math.floor(now / 1000) + START_EXPIRATION_S,
            payload: startPayload(race, channel.channelId, state, now),
          },
          token,
        ),
      );
      switch (outcome.kind) {
        case "sent":
          break;
        case "deferred":
          await release(env, race.id, device.keyId);
          return;
        case "unregistered":
          await release(env, race.id, device.keyId);
          await deleteStartToken(env.DB, device.token);
          break;
        case "retry":
          console.warn("APNs Live Activity start retry", race.id, outcome.reason);
          await release(env, race.id, device.keyId);
          break;
        default:
          // Refused, the claim stays: sent again, it would be refused again.
          console.error("APNs Live Activity start failed", race.id, outcome);
      }
    }
  }
}

/** The athletes and nations on the race's start list; `undefined` until it is published or when it can't be read. */
async function startList(
  raceId: string,
  budget: SubrequestBudget,
): Promise<{ athletes: Set<string>; nations: Set<string> } | undefined> {
  try {
    const rows = (await fetchIBU<IBUResults>("Results", { RaceId: raceId }, budget)).Results ?? [];
    if (rows.length === 0) return undefined;
    return {
      athletes: new Set(rows.flatMap((row) => (row.IBUId ? [row.IBUId] : []))),
      nations: new Set(rows.flatMap((row) => (row.Nat ? [row.Nat] : []))),
    };
  } catch (error) {
    console.warn("Start list unavailable", raceId, String(error));
    return undefined;
  }
}

/**
 * Apple's start payload: `event` start, an alert so the new activity doesn't surprise anyone,
 * `attributes-type` and `attributes`, and `input-push-channel` (iOS 18) to subscribe it to the
 * race's channel. The attributes decode into `RaceActivityAttributes` with the default
 * `Codable` strategies; `scheduledStart` stays absent, the activity showing at once.
 */
function startPayload(race: RaceSnapshot, channelId: string, state: LiveState, now: number) {
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
        title: { "loc-key": LOC_KEYS.liveActivityStart.title },
        body: { "loc-key": LOC_KEYS.liveActivityStart.body, "loc-args": [race.name] },
        sound: "default",
      },
    },
  };
}

/** Records that the race was checked for the install; `false` when another run already had. */
async function claim(env: Env, raceId: string, keyId: string, started: boolean): Promise<boolean> {
  const { meta } = await env.DB.prepare(
    "INSERT INTO live_starts (race_id, app_attest_key_id, started) VALUES (?1, ?2, ?3) ON CONFLICT DO NOTHING",
  )
    .bind(raceId, keyId, started ? 1 : 0)
    .run();
  return meta.changes === 1;
}

/** Gives a start that didn't go through back to a later run. */
function release(env: Env, raceId: string, keyId: string) {
  return env.DB.prepare("DELETE FROM live_starts WHERE race_id = ?1 AND app_attest_key_id = ?2 AND started = 1")
    .bind(raceId, keyId)
    .run();
}

/** Deletes a token APNs reported as no longer valid. */
async function deleteStartToken(db: D1Database, token: string): Promise<void> {
  await db.prepare("DELETE FROM live_start_tokens WHERE token = ?1").bind(token).run();
}
