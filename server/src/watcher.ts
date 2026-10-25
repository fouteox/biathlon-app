import type { APNsEnvironment } from "./apns";
import { detectChange, hasChanged, type RaceChange } from "./changes";
import { deleteDevices } from "./devices";
import {
  activeEvents,
  fetchIBU,
  seasonId,
  seasonStart,
  snapshot,
  type IBUCompetition,
  type IBUEvent,
  type RaceSnapshot,
} from "./ibu";
import { syncLiveActivities } from "./live";
import { startFavoriteActivities } from "./liveStarts";
import type { AlertInput } from "./payload";
import { ProviderTokens } from "./providerTokens";
import { MAX_SEND_ATTEMPTS, PushLots } from "./pushLots";
import { SubrequestBudget } from "./subrequests";

/** The calendar of events rarely changes: refresh it every 6 hours. */
const EVENTS_TTL_MS = 6 * 60 * 60 * 1000;
/** An alert older than this is no longer useful. */
const OUTBOX_MAX_AGE_MS = 30 * 60 * 1000;

/**
 * Whether the run scheduled at `scheduledTime` is the first for its minute, and records it.
 * Cloudflare sometimes fires the cron twice for one minute (3 times in a day, measured on
 * 2026-10-25): the second run would send the same alerts again. A run of an earlier minute
 * than one already started is skipped too, the later run doing its work.
 */
export async function claimCronRun(db: D1Database, scheduledTime: number): Promise<boolean> {
  const minute = Math.floor(scheduledTime / 60_000);
  const claimed = await db
    .prepare(
      `INSERT INTO settings (key, value, updated_at) VALUES ('cron_minute', ?1, ?2)
       ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
         WHERE CAST(settings.value AS INTEGER) < CAST(excluded.value AS INTEGER)
       RETURNING key`,
    )
    .bind(String(minute), scheduledTime)
    .first();
  return claimed !== null;
}

/**
 * One cron run: detect race changes and queue alerts, send a batch of alerts, then
 * update the races' Live Activities with the subrequests left, and start those of the
 * favorites' races. Device pushes go out in lots (`PushLots`), outside the run's budget.
 */
export async function runCron(env: Env, now: number): Promise<void> {
  const budget = new SubrequestBudget();
  const lots = new PushLots(env, new ProviderTokens(env, now, budget));
  let races: RaceSnapshot[] | undefined;
  try {
    ({ races } = await pollRaces(env, now, budget));
  } finally {
    // Alerts queued by earlier runs and ended activities still go out while the IBU API is down.
    try {
      await drainOutbox(env, now, lots);
    } finally {
      await syncLiveActivities(env, races, now, budget);
      // After the channels it subscribes the new activities to.
      if (races) await startFavoriteActivities(env, races, now, budget, lots);
    }
  }
}

/**
 * Compares the IBU schedule with the stored baseline. The new baseline and
 * the alerts it triggers are written in one D1 batch, which is a transaction,
 * so a failed run cannot record a change without queuing its alerts.
 */
export async function pollRaces(
  env: Env,
  now: number,
  budget = new SubrequestBudget(),
): Promise<{ changes: RaceChange[]; races: RaceSnapshot[] }> {
  const events = activeEvents(await worldCupEvents(env.DB, now, budget), now);
  if (events.length === 0) return { changes: [], races: [] };

  const current: RaceSnapshot[] = [];
  for (const event of events) {
    const races = await fetchIBU<IBUCompetition[]>("Competitions", { EventId: event.EventId }, budget);
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
  return { changes, races: current };
}

/**
 * Deletes the races of past seasons, which the watcher no longer polls, but those a Live
 * Activity's channel or start still references.
 */
export async function pruneRaces(db: D1Database, now: number): Promise<void> {
  await db
    .prepare(
      `DELETE FROM races WHERE start_time < ?1
       AND id NOT IN (SELECT race_id FROM live_channels) AND id NOT IN (SELECT race_id FROM live_starts)`,
    )
    .bind(seasonStart(new Date(now)).toISOString())
    .run();
}

/**
 * A device's categories, a JSON array. The server's previous version wrote them comma-separated,
 * until the migration that converts its rows, applied once no running version writes that form.
 */
const CATEGORIES = `json_each(CASE WHEN json_valid(categories) THEN categories
  ELSE '["' || replace(categories, ',', '","') || '"]' END)`;

/** Queues one alert per device subscribed to the race's category and to this kind of change. */
function enqueue(db: D1Database, change: RaceChange, now: number): D1PreparedStatement {
  const preference = change.kind === "cancelled" ? "cancellation" : "rescheduling";
  return db
    .prepare(
      `INSERT INTO outbox (token, environment, kind, race_id, race_name, start_time, locale, time_zone, created_at)
       SELECT token, environment, ?1, ?2, ?3, ?4, locale, time_zone, ?5 FROM devices
       WHERE ${preference} = 1 AND ?6 IN (SELECT value FROM ${CATEGORIES})`,
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

export async function drainOutbox(
  env: Env,
  now: number,
  lots = new PushLots(env, new ProviderTokens(env, now, new SubrequestBudget())),
): Promise<void> {
  const { results: rows } = await env.DB.prepare("SELECT * FROM outbox WHERE created_at >= ?1 ORDER BY id LIMIT ?2")
    .bind(now - OUTBOX_MAX_AGE_MS, lots.room)
    .all<OutboxRow>();

  const done: number[] = [];
  const retry: number[] = [];
  const unregistered: string[] = [];
  const sent = rows.map(async (row) => {
    const outcome = await lots.send({
      deviceToken: row.token,
      environment: row.environment,
      topic: env.APNS_TOPIC,
      collapseId: `${row.kind}-${row.race_id}`,
      expiration: Math.floor((row.created_at + OUTBOX_MAX_AGE_MS) / 1000),
      alert: {
        kind: row.kind,
        raceId: row.race_id,
        raceName: row.race_name,
        startTime: row.start_time,
        locale: row.locale,
        timeZone: row.time_zone,
      },
    });
    switch (outcome.kind) {
      case "sent":
        done.push(row.id);
        break;
      case "unregistered":
        unregistered.push(row.token);
        break;
      case "deferred":
        // Left untouched for the next run.
        break;
      case "retry":
      case "expiredProviderToken":
        (row.attempts + 1 >= MAX_SEND_ATTEMPTS ? done : retry).push(row.id);
        console.warn("APNs retry", row.id, outcome);
        break;
      default:
        done.push(row.id);
        console.error("APNs failure", row.id, outcome);
    }
  });
  await lots.flush();
  await Promise.all(sent);

  const statements = [
    env.DB.prepare("DELETE FROM outbox WHERE created_at < ?1").bind(now - OUTBOX_MAX_AGE_MS),
    env.DB.prepare("DELETE FROM outbox WHERE id IN (SELECT value FROM json_each(?1))").bind(JSON.stringify(done)),
    env.DB.prepare("UPDATE outbox SET attempts = attempts + 1 WHERE id IN (SELECT value FROM json_each(?1))").bind(
      JSON.stringify(retry),
    ),
  ];
  await env.DB.batch(statements);
  if (unregistered.length > 0) await deleteDevices(env.DB, [...new Set(unregistered)]);
}

/** World Cup events (Level=1) of the current season, cached in D1. */
async function worldCupEvents(db: D1Database, now: number, budget: SubrequestBudget): Promise<IBUEvent[]> {
  const season = seasonId(new Date(now));
  const key = `events_${season}`;
  const cached = await db.prepare("SELECT value, updated_at FROM settings WHERE key = ?1").bind(key).first<{
    value: string;
    updated_at: number;
  }>();
  if (cached && now - cached.updated_at < EVENTS_TTL_MS) return JSON.parse(cached.value) as IBUEvent[];

  const events = await fetchIBU<IBUEvent[]>("Events", { SeasonId: season, Level: "1" }, budget);
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
