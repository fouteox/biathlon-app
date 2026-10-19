import { makeProviderToken, PROVIDER_TOKEN_LIFETIME_S, sendPush, type APNsEnvironment } from "./apns";
import { detectChange, hasChanged, type RaceChange } from "./changes";
import { deleteDevice } from "./devices";
import { activeEvents, fetchIBU, seasonId, snapshot, type IBUCompetition, type IBUEvent, type RaceSnapshot } from "./ibu";
import { buildPayload, type AlertInput } from "./payload";

/** The calendar of events rarely changes: refresh it every 6 hours. */
const EVENTS_TTL_MS = 6 * 60 * 60 * 1000;
/** An alert older than this is no longer useful. */
const OUTBOX_MAX_AGE_MS = 30 * 60 * 1000;
const MAX_ATTEMPTS = 5;

/** One cron run: detect race changes and queue alerts, then send a batch of them. */
export async function runCron(env: Env, now: number): Promise<void> {
  try {
    await pollRaces(env, now);
  } finally {
    // Alerts queued by earlier runs still go out while the IBU API is down.
    await drainOutbox(env, now);
  }
}

/**
 * Compares the IBU schedule with the stored baseline. The new baseline and
 * the alerts it triggers are written in one D1 batch, which is a transaction,
 * so a failed run cannot record a change without queuing its alerts.
 */
export async function pollRaces(env: Env, now: number): Promise<RaceChange[]> {
  const events = activeEvents(await worldCupEvents(env.DB, now), now);
  if (events.length === 0) return [];

  const current: RaceSnapshot[] = [];
  for (const event of events) {
    const races = await fetchIBU<IBUCompetition[]>("Competitions", { EventId: event.EventId });
    current.push(...races.map(snapshot));
  }

  const ids = current.map((race) => race.id);
  const { results } = await env.DB.prepare(
    "SELECT id, category, name, start_time AS startTime, status FROM races WHERE id IN (SELECT value FROM json_each(?1))",
  )
    .bind(JSON.stringify(ids))
    .all<RaceSnapshot>();
  const previous = new Map(results.map((race) => [race.id, race]));

  const changes: RaceChange[] = [];
  const writes: D1PreparedStatement[] = [];
  for (const race of current) {
    const before = previous.get(race.id);
    const change = detectChange(before, race);
    if (change) {
      changes.push(change);
      writes.push(enqueue(env.DB, change, now));
    }
    if (hasChanged(before, race)) {
      writes.push(
        env.DB.prepare(
          `INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
           ON CONFLICT (id) DO UPDATE SET category = excluded.category, name = excluded.name,
             start_time = excluded.start_time, status = excluded.status, updated_at = excluded.updated_at`,
        ).bind(race.id, race.category, race.name, race.startTime, race.status, now),
      );
    }
  }
  if (writes.length > 0) await env.DB.batch(writes);
  return changes;
}

/** Queues one alert per device subscribed to the race's category and to this kind of change. */
function enqueue(db: D1Database, change: RaceChange, now: number): D1PreparedStatement {
  const preference = change.kind === "cancelled" ? "cancellation" : "rescheduling";
  return db
    .prepare(
      `INSERT INTO outbox (token, environment, kind, race_id, race_name, start_time, locale, time_zone, created_at)
       SELECT token, environment, ?1, ?2, ?3, ?4, locale, time_zone, ?5 FROM devices
       WHERE ${preference} = 1 AND (',' || categories || ',') LIKE ('%,' || ?6 || ',%')`,
    )
    .bind(change.kind, change.race.id, change.race.name, change.race.startTime, now, change.race.category);
}

interface OutboxRow {
  id: number;
  token: string;
  environment: APNsEnvironment;
  kind: AlertInput["kind"];
  race_id: string;
  race_name: string;
  start_time: string;
  locale: string;
  time_zone: string;
  attempts: number;
  created_at: number;
}

export async function drainOutbox(env: Env, now: number): Promise<void> {
  const limit = Number(env.MAX_PUSHES_PER_RUN) || 30;
  const { results: rows } = await env.DB.prepare(
    "SELECT * FROM outbox WHERE created_at >= ?1 ORDER BY id LIMIT ?2",
  )
    .bind(now - OUTBOX_MAX_AGE_MS, limit)
    .all<OutboxRow>();

  const done: number[] = [];
  const retry: number[] = [];
  const unregistered: string[] = [];
  if (rows.length > 0) {
    // One signing key per APNs environment, as Apple recommends for team-scoped keys.
    const tokens = new Map<APNsEnvironment, string>();
    const refreshed = new Set<APNsEnvironment>();
    for (const row of rows) {
      let token = tokens.get(row.environment) ?? (await providerToken(env, row.environment, now));
      tokens.set(row.environment, token);
      const request = {
        deviceToken: row.token,
        environment: row.environment,
        topic: env.APNS_TOPIC,
        collapseId: `${row.kind}-${row.race_id}`,
        expiration: Math.floor((row.created_at + OUTBOX_MAX_AGE_MS) / 1000),
        payload: buildPayload({
          kind: row.kind,
          raceId: row.race_id,
          raceName: row.race_name,
          startTime: row.start_time,
          locale: row.locale,
          timeZone: row.time_zone,
        }),
      };
      let outcome = await sendPush(request, token);
      // Sign a new token at most once per run: APNs rejects updates more frequent than every 20 minutes.
      if (outcome.kind === "expiredProviderToken" && !refreshed.has(row.environment)) {
        refreshed.add(row.environment);
        token = await providerToken(env, row.environment, now, true);
        tokens.set(row.environment, token);
        outcome = await sendPush(request, token);
      }
      switch (outcome.kind) {
        case "sent":
          done.push(row.id);
          break;
        case "unregistered":
          unregistered.push(row.token);
          break;
        case "retry":
          (row.attempts + 1 >= MAX_ATTEMPTS ? done : retry).push(row.id);
          console.warn("APNs retry", row.id, outcome.reason);
          break;
        default:
          done.push(row.id);
          console.error("APNs failure", row.id, outcome);
      }
    }
  }

  const statements = [
    env.DB.prepare("DELETE FROM outbox WHERE created_at < ?1").bind(now - OUTBOX_MAX_AGE_MS),
    env.DB.prepare("DELETE FROM outbox WHERE id IN (SELECT value FROM json_each(?1))").bind(JSON.stringify(done)),
    env.DB.prepare("UPDATE outbox SET attempts = attempts + 1 WHERE id IN (SELECT value FROM json_each(?1))").bind(
      JSON.stringify(retry),
    ),
  ];
  await env.DB.batch(statements);
  for (const deviceToken of new Set(unregistered)) await deleteDevice(env.DB, deviceToken);
}

/** Reuses the signed provider token stored in D1 while it is younger than its lifetime. */
async function providerToken(env: Env, environment: APNsEnvironment, now: number, forceRefresh = false): Promise<string> {
  const cacheKey = `apns_token_${environment}`;
  if (!forceRefresh) {
    const cached = await env.DB.prepare("SELECT value, updated_at FROM settings WHERE key = ?1")
      .bind(cacheKey)
      .first<{ value: string; updated_at: number }>();
    if (cached && now - cached.updated_at < PROVIDER_TOKEN_LIFETIME_S * 1000) return cached.value;
  }
  const key =
    environment === "sandbox"
      ? { pem: env.APNS_SANDBOX_KEY, keyId: env.APNS_SANDBOX_KEY_ID, teamId: env.APNS_TEAM_ID }
      : { pem: env.APNS_PRODUCTION_KEY, keyId: env.APNS_PRODUCTION_KEY_ID, teamId: env.APNS_TEAM_ID };
  const token = await makeProviderToken(key, Math.floor(now / 1000));
  await env.DB.prepare(
    `INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
     ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  )
    .bind(cacheKey, token, now)
    .run();
  return token;
}

/** World Cup events (Level=1) of the current season, cached in D1. */
async function worldCupEvents(db: D1Database, now: number): Promise<IBUEvent[]> {
  const season = seasonId(new Date(now));
  const key = `events_${season}`;
  const cached = await db.prepare("SELECT value, updated_at FROM settings WHERE key = ?1").bind(key).first<{
    value: string;
    updated_at: number;
  }>();
  if (cached && now - cached.updated_at < EVENTS_TTL_MS) return JSON.parse(cached.value) as IBUEvent[];

  const events = await fetchIBU<IBUEvent[]>("Events", { SeasonId: season, Level: "1" });
  const slim = events.map(({ EventId, StartDate, EndDate }) => ({ EventId, StartDate, EndDate }));
  await db
    .prepare(
      `INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
       ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
    )
    .bind(key, JSON.stringify(slim), now)
    .run();
  return slim;
}
