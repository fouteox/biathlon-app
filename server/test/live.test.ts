import {
  createExecutionContext,
  createScheduledController,
  listDurableObjectIds,
  runDurableObjectAlarm,
  runInDurableObject,
} from "cloudflare:test";
import { env as testEnv } from "cloudflare:workers";
import { describe, expect, it, vi } from "vite-plus/test";
import fixture from "../../Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures/live-activity.json";
import worker from "../src/index";
import { snapshot, type IBUCompetition, type RaceSnapshot } from "../src/ibu";
import {
  givenTokens,
  liveState,
  pruneChannels,
  relevanceScore,
  syncLiveActivities,
  type IBUResults,
  type LiveState,
} from "../src/live";
import { parseStartRegistration, pruneStarts, saveStartToken } from "../src/liveStarts";
import { ProviderTokens } from "../src/providerTokens";
import { SubrequestBudget } from "../src/subrequests";
import { parseRegistration, saveDevice } from "../src/devices";
import { buildPayload } from "../src/payload";
import { PushLots } from "../src/pushLots";
import { PushSender } from "../src/pushSender";
import { syncRace } from "../src/raceActivity";
import { claimCronRun, drainOutbox, pollRaces, pruneRaces } from "../src/watcher";
import { answer } from "./network";

// Shared with the app's BiathlonKit tests, which decode each `content-state` with
// ActivityKit's default strategies and give its local updates the same relevance score.
const cases: { name: string; results: IBUResults; state: unknown; relevanceScore?: number }[] = fixture;

describe("Live Activity state shared with the app", () => {
  for (const { name, results, state, relevanceScore: score } of cases) {
    it(name, () => {
      expect(liveState(results) ?? null).toEqual(state);
      if (state) expect(relevanceScore(state as LiveState)).toBe(score);
    });
  }
});

const [live, relay] = cases as [(typeof cases)[number], (typeof cases)[number]];
/** The relay's final state on the calendar of `race()`, which decides the start time. */
const relayFinal = { ...(relay.state as object), startTime: (live.state as { startTime: number }).startTime };
const RACE_ID = "BT2627SWRLCP01SMIN";
const NOW = Date.parse("2026-11-26T15:30:00Z");

const race = (overrides: Partial<IBUCompetition> = {}): RaceSnapshot =>
  snapshot({
    RaceId: RACE_ID,
    catId: "SM",
    ShortDescription: "Men's 20km Individual",
    StartTime: "2026-11-26T15:15:00Z",
    StatusId: 1,
    ScheduleStatus: "SCHEDULED",
    ...overrides,
  });

interface Sent {
  method: string;
  url: string;
  headers: Record<string, string>;
  body: unknown;
}

/** Answers like APNs and the IBU API, and records every request. */
function stubNetwork(
  options: {
    results?: unknown;
    resultsStatus?: number;
    broadcastReason?: string;
    failingHost?: string;
    deviceStatus?: number;
    deviceReason?: string;
    /** Names the channels APNs creates, unique across stubs. */
    channelPrefix?: string;
    /** Runs while APNs answers a device push; its status, if any, replaces the answer. */
    duringDevice?: () => Promise<number | undefined>;
    /** Runs while the IBU API answers, like a request served meanwhile. */
    duringResults?: () => Promise<void>;
  } = {},
): Sent[] {
  const sent: Sent[] = [];
  let channels = 0;
  answer(async (request) => {
    const { method, url } = request;
    const body = await request.text();
    sent.push({ method, url, headers: Object.fromEntries(request.headers), body: body ? JSON.parse(body) : undefined });
    if (url.includes("biathlonresults.com")) {
      await options.duringResults?.();
      return Response.json(options.results ?? live.results, { status: options.resultsStatus ?? 200 });
    }
    if (options.failingHost && url.includes(options.failingHost)) return new Response(null, { status: 500 });
    if (url.includes("api-manage-broadcast") && method === "POST") {
      channels += 1;
      return new Response(null, {
        status: 201,
        headers: { "apns-channel-id": `${options.channelPrefix ?? "channel"}-${channels}` },
      });
    }
    if (url.includes("api-manage-broadcast") && method === "DELETE") return new Response(null, { status: 204 });
    if (url.includes("/3/device/")) {
      const status = (await options.duringDevice?.()) ?? options.deviceStatus;
      if (status)
        return options.deviceReason
          ? Response.json({ reason: options.deviceReason }, { status })
          : new Response(null, { status });
    }
    if (url.includes("/4/broadcasts/") && options.broadcastReason) {
      return Response.json({ reason: options.broadcastReason }, { status: 400 });
    }
    return new Response(null, { status: 200 });
  });
  return sent;
}

/** The test's bindings, in a copy a test can change. */
async function makeEnv(): Promise<Env> {
  const env = { ...testEnv };
  // The watcher stores each race before its channels reference it.
  await env.DB.prepare(
    "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'Men''s 20km Individual', '2026-11-26T15:15:00.000Z', 'scheduled', 0)",
  )
    .bind(RACE_ID)
    .run();
  return env;
}

/** Puts `env.DB` behind the methods `replace` returns for the real database, which answers the others. */
function replaceD1(env: Env, replace: (db: D1Database) => Partial<Pick<D1Database, "prepare" | "batch">>): void {
  const db = env.DB;
  env.DB = {
    prepare: (sql: string) => db.prepare(sql),
    batch: (statements: D1PreparedStatement[]) => db.batch(statements),
    ...replace(db),
  } as unknown as D1Database;
}

/** Counts the D1 queries made from now on: each `run`, `all`, `first` or `batch`. */
function countD1Queries(env: Env): () => number {
  let queries = 0;
  const db = env.DB;
  const counted = <T extends (...args: never[]) => unknown>(method: T) =>
    ((...args: Parameters<T>) => {
      queries += 1;
      return method(...args);
    }) as T;
  const statement = (prepared: D1PreparedStatement): D1PreparedStatement =>
    ({
      bind: (...values: unknown[]) => statement(prepared.bind(...values)),
      run: counted(() => prepared.run()),
      all: counted(() => prepared.all()),
      first: counted(() => prepared.first()),
      raw: prepared,
    }) as unknown as D1PreparedStatement;
  env.DB = {
    prepare: (sql: string) => statement(db.prepare(sql)),
    // A batch counts as one query against the limit per invocation, whatever its statements
    // (https://developers.cloudflare.com/d1/platform/limits/).
    batch: (statements: D1PreparedStatement[]) => {
      queries += 1;
      return db.batch(statements.map((item) => (item as unknown as { raw: D1PreparedStatement }).raw));
    },
  } as unknown as D1Database;
  return () => queries;
}

/** Records the size of each lot a `PushSender` Durable Object sends, in no set order: the lots go out at once. */
function recordLots(): () => number[] {
  const send = vi.spyOn(PushSender.prototype, "send");
  return () => send.mock.calls.map(([pushes]) => pushes.length);
}

/** The pushes of one run, with room for `capacity` of them. */
const pushLots = (env: Env, now: number, capacity: number) =>
  new PushLots(env, new ProviderTokens(env, now, new SubrequestBudget()), capacity);

const channels = (env: Env) =>
  env.DB.prepare("SELECT environment, channel_id AS channelId, state FROM live_channels ORDER BY environment")
    .all<{ environment: string; channelId: string; state: string }>()
    .then(({ results }) => results);

/** One cron run's update of the races' Live Activities, each in its object. */
const sync = (env: Env, races: RaceSnapshot[], now: number) =>
  syncLiveActivities(env, races, now, new ProviderTokens(env, now, new SubrequestBudget()));

const activity = (raceId = RACE_ID) => testEnv.RACE_ACTIVITY.getByName(raceId);

/**
 * Updates the race in its object with `env`, which a test can change: as a cron run listing
 * `race` does, with the provider tokens it loads with `cronEnv`, or as the object's alarm does without.
 */
async function update(env: Env, now: number, race?: RaceSnapshot, cronEnv = env, deadline = Date.now() + 60_000) {
  const raceId = race?.id ?? RACE_ID;
  const listed = race && {
    race,
    providerTokens: await givenTokens(new ProviderTokens(cronEnv, now, new SubrequestBudget())),
  };
  return runInDurableObject(activity(raceId), (_, state) =>
    syncRace(env, state.storage, raceId, now, deadline, listed),
  );
}

/** APNs takes the requests to `path` and never answers them, as a stalled connection does. */
const unanswered = (path: string) =>
  answer(({ url }) => (url.includes(path) ? new Promise<Response>(() => {}) : undefined));

/** When the race's object is set to wake up. */
const alarmOf = (raceId = RACE_ID) => runInDurableObject(activity(raceId), (_, state) => state.storage.getAlarm());

const broadcasts = (sent: Sent[]) => sent.filter((request) => request.url.includes("/4/broadcasts/"));

describe("Live Activity channels", () => {
  it("opens one channel per APNs environment for an upcoming race, without broadcasting", async () => {
    const env = await makeEnv();
    const sent = stubNetwork();

    await sync(env, [race()], NOW);

    const creations = sent.filter(
      (request) => request.method === "POST" && request.url.includes("api-manage-broadcast"),
    );
    expect(creations.map((request) => request.url)).toEqual([
      "https://api-manage-broadcast.push.apple.com:2196/1/apps/com.fouteox.biathlon/channels",
      "https://api-manage-broadcast.sandbox.push.apple.com:2195/1/apps/com.fouteox.biathlon/channels",
    ]);
    // Apple: no message storage for frequently updated sports scores.
    expect(creations[0]?.body).toEqual({ "message-storage-policy": 0, "push-type": "LiveActivity" });
    expect(creations[0]?.headers.authorization).toMatch(/^bearer /);
    expect((await channels(env)).map(({ environment, channelId }) => [environment, channelId])).toEqual([
      ["production", "channel-1"],
      ["sandbox", "channel-2"],
    ]);
    expect(broadcasts(sent)).toEqual([]);
  });

  it("broadcasts a live race's new leaders once, on every environment", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    const sent = stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);
    await sync(env, [race({ IsLive: true })], NOW + 60_000);

    const updates = broadcasts(sent);
    expect(updates.map((request) => [request.url, request.headers["apns-channel-id"]])).toEqual([
      ["https://api.push.apple.com/4/broadcasts/apps/com.fouteox.biathlon", "channel-1"],
      ["https://api.sandbox.push.apple.com/4/broadcasts/apps/com.fouteox.biathlon", "channel-2"],
    ]);
    expect(updates[0]?.headers).toMatchObject({
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "apns-expiration": "0",
    });
    expect(updates[0]?.body).toEqual({
      aps: { timestamp: NOW / 1000, event: "update", "relevance-score": 1, "content-state": live.state },
    });
  });

  it("broadcasts a new start time of an upcoming race", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    const sent = stubNetwork();
    await sync(env, [race({ StartTime: "2026-11-26T15:45:00Z" })], NOW);

    expect(
      broadcasts(sent).map((request) => (request.body as { aps: { "content-state": unknown } }).aps["content-state"]),
    ).toEqual([
      { phase: "scheduled", startTime: 817400700, leaders: [] },
      { phase: "scheduled", startTime: 817400700, leaders: [] },
    ]);
    // Upcoming races need no results.
    expect(sent.some((request) => request.url.includes("biathlonresults.com"))).toBe(false);
  });

  it("ends the activity with the final results, sends the end again for offline devices, then deletes the channels", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];

    const sent = stubNetwork({ results: relay.results });
    await sync(env, finished, NOW);
    expect(broadcasts(sent).map((request) => request.body)).toEqual([
      { aps: { timestamp: NOW / 1000, event: "end", "relevance-score": 0, "content-state": relayFinal } },
      { aps: { timestamp: NOW / 1000, event: "end", "relevance-score": 0, "content-state": relayFinal } },
    ]);

    // No message storage: devices offline at the end only get a later send.
    const later = stubNetwork({ results: relay.results });
    await sync(env, finished, NOW + 60_000);
    expect(broadcasts(later)).toEqual([]);
    await sync(env, finished, NOW + 10 * 60_000);
    expect(broadcasts(later).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual([
      "end",
      "end",
    ]);
    expect(later.some((request) => request.url.includes("biathlonresults.com"))).toBe(false);
    expect(later.some((request) => request.method === "DELETE")).toBe(false);

    const last = stubNetwork();
    await sync(env, finished, NOW + 60 * 60_000);
    expect(
      last.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"]),
    ).toEqual(["channel-1", "channel-2"]);
    expect(broadcasts(last)).toEqual([]);
    // The rows stay, for the app to learn that the activity is over.
    expect((await channels(env)).map(({ state }) => JSON.parse(state))).toEqual([relayFinal, relayFinal]);

    const after = stubNetwork();
    await sync(env, finished, NOW + 70 * 60_000);
    expect(after.filter((request) => !request.url.includes("biathlonresults.com"))).toEqual([]);
  });

  it("ends a race from the calendar when its results don't describe it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    const sent = stubNetwork({ results: { RaceId: RACE_ID, Results: [] } });
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual([
      "end",
      "end",
    ]);
  });

  it("ends a finished race with its last state when its results can't be read", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork({ resultsStatus: 503 });
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 60_000);

    expect(broadcasts(sent).map((request) => request.body)).toEqual([
      {
        aps: {
          timestamp: NOW / 1000 + 60,
          event: "end",
          "relevance-score": 0,
          "content-state": { ...(live.state as object), phase: "finished" },
        },
      },
      {
        aps: {
          timestamp: NOW / 1000 + 60,
          event: "end",
          "relevance-score": 0,
          "content-state": { ...(live.state as object), phase: "finished" },
        },
      },
    ]);
  });

  it("ends a finished race with the calendar's phase when its results still say it is live", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    const sent = stubNetwork();
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    expect(
      broadcasts(sent).map((request) => (request.body as { aps: { "content-state": unknown } }).aps["content-state"]),
    ).toEqual([
      { ...(live.state as object), phase: "finished" },
      { ...(live.state as object), phase: "finished" },
    ]);
  });

  it("keeps the last leaders when the results stop describing the race", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);
    const withoutCompetition = { RaceId: RACE_ID, Results: [] };

    const unchanged = stubNetwork({ results: withoutCompetition });
    await sync(env, [race({ IsLive: true })], NOW + 60_000);
    expect(broadcasts(unchanged)).toEqual([]);

    const sent = stubNetwork({ results: withoutCompetition });
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 120_000);
    expect(
      broadcasts(sent).map((request) => (request.body as { aps: { "content-state": unknown } }).aps["content-state"]),
    ).toEqual([
      { ...(live.state as object), phase: "finished" },
      { ...(live.state as object), phase: "finished" },
    ]);
  });

  it("follows the calendar's phase, ending the activity only once the calendar says the race is over", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const ahead = { ...relayFinal, phase: "live" };

    const sent = stubNetwork({ results: relay.results });
    await sync(env, [race({ IsLive: true })], NOW);
    await sync(env, [race({ IsLive: true })], NOW + 60_000);
    expect(broadcasts(sent).map((request) => request.body)).toEqual([
      { aps: { timestamp: NOW / 1000, event: "update", "relevance-score": 1, "content-state": ahead } },
      { aps: { timestamp: NOW / 1000, event: "update", "relevance-score": 1, "content-state": ahead } },
    ]);
    expect(sent.filter((request) => request.method !== "GET" && !request.url.includes("/4/broadcasts/"))).toEqual([]);

    const ended = stubNetwork({ results: relay.results });
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 120_000);
    expect(broadcasts(ended).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual([
      "end",
      "end",
    ]);
  });

  it("replaces the ended channels of a race that can be followed again", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW);

    const sent = stubNetwork();
    await sync(env, [race()], NOW + 60_000);

    expect(sent.filter((request) => request.method === "DELETE").length).toBe(2);
    const rows = await channels(env);
    expect(rows.map(({ channelId }) => channelId)).toEqual(["channel-1", "channel-2"]);
    expect(rows.every(({ state }) => JSON.parse(state).phase === "scheduled")).toBe(true);
  });

  it("lets only a run started after the end reinstate a race", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 60_000);

    // An older run, started before the end, still holds a snapshot of the race under way.
    const sent = stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW + 30_000);

    expect(sent.filter((request) => request.url.includes("api-manage-broadcast"))).toEqual([]);
    expect((await channels(env)).map(({ channelId }) => channelId)).toEqual(["channel-1", "channel-2"]);
  });

  it("clears the leaders of a race the calendar cancels", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork();
    await sync(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW + 60_000);

    const states = broadcasts(sent).map(
      (request) =>
        (request.body as { aps: { "content-state": { phase: string; leaders: unknown[] } } }).aps["content-state"],
    );
    expect(states.map(({ phase, leaders }) => [phase, leaders])).toEqual([
      ["cancelled", []],
      ["cancelled", []],
    ]);
  });

  it("opens new channels for a race followable again once its old ones are deleted", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW);
    stubNetwork();
    await sync(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW + 60 * 60_000);

    const sent = stubNetwork();
    await sync(env, [race()], NOW + 61 * 60_000);

    expect(sent.filter((request) => request.method === "DELETE")).toEqual([]);
    expect((await channels(env)).map(({ channelId }) => channelId)).toEqual(["channel-1", "channel-2"]);
  });

  it("updates a race one run at a time, though cron runs overlap", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    const sent = stubNetwork();
    await Promise.all([sync(env, [race({ IsLive: true })], NOW), sync(env, [race({ IsLive: true })], NOW + 60_000)]);

    expect(broadcasts(sent).length).toBe(2);
  });

  it("deletes at a later try a replaced channel APNs failed to delete", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW);
    stubNetwork({ failingHost: "api-manage-broadcast.push.apple.com" });
    answer(({ method, url }) =>
      method === "POST" && url.includes("api-manage-broadcast")
        ? new Response(null, { status: 201, headers: { "apns-channel-id": `new-${new URL(url).port}` } })
        : undefined,
    );
    await sync(env, [race()], NOW + 60_000);

    const sent = stubNetwork();
    await update(env, NOW + 2 * 60_000);

    expect(
      sent.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"]),
    ).toEqual(["channel-1"]);
    const later = stubNetwork();
    await update(env, NOW + 3 * 60_000);
    expect(later.filter((request) => request.method === "DELETE")).toEqual([]);
  });

  it("clears the leaders of a live race the calendar schedules again", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork();
    await sync(env, [race({ StartTime: "2026-11-27T15:15:00Z" })], NOW + 60_000);

    const states = broadcasts(sent).map(
      (request) => (request.body as { aps: { "content-state": { leaders: unknown[] } } }).aps["content-state"],
    );
    expect(states.map(({ leaders }) => leaders)).toEqual([[], []]);
  });

  it("moves the start time of a live race from the calendar while its results can't be read", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork({ resultsStatus: 503 });
    await sync(env, [race({ IsLive: true, StartTime: "2026-11-26T16:15:00Z" })], NOW + 60_000);

    const states = broadcasts(sent).map(
      (request) => (request.body as { aps: { "content-state": { startTime: number } } }).aps["content-state"],
    );
    expect(states).toEqual([
      { ...(live.state as { startTime: number }), startTime: (live.state as { startTime: number }).startTime + 3600 },
      { ...(live.state as { startTime: number }), startTime: (live.state as { startTime: number }).startTime + 3600 },
    ]);
  });

  it("replaces a channel APNs no longer knows at once", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    const sent = stubNetwork({ broadcastReason: "ChannelNotRegistered" });
    await sync(env, [race({ IsLive: true })], NOW);

    const creations = sent.filter(
      (request) => request.method === "POST" && request.url.includes("api-manage-broadcast"),
    );
    expect(creations.length).toBe(2);
    // Opened with the leaders the update looked up.
    expect((await channels(env)).map(({ channelId, state }) => [channelId, JSON.parse(state)])).toEqual([
      ["channel-1", live.state],
      ["channel-2", live.state],
    ]);
    const { results } = await env.DB.prepare("SELECT deleted_at AS deletedAt FROM live_channels").all();
    expect(results).toEqual([{ deletedAt: null }, { deletedAt: null }]);
  });

  it("clears the leaders of a dropped channel's replacement when the race is scheduled again", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", results: relay.results });
    await sync(env, [race({ IsLive: true })], NOW + 60_000);

    stubNetwork();
    await sync(env, [race()], NOW + 2 * 60_000);

    expect((await channels(env)).map(({ state }) => JSON.parse(state).leaders)).toEqual([[], []]);
  });

  it("ends the activity with its final state even when APNs rejects the end, sent again at the next run", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];
    stubNetwork({ results: relay.results, broadcastReason: "BadPayload" });
    await sync(env, finished, NOW);

    const { results } = await env.DB.prepare(
      "SELECT ended_at AS endedAt, end_sent_at AS endSentAt FROM live_channels",
    ).all();
    expect(results).toEqual([
      { endedAt: NOW, endSentAt: null },
      { endedAt: NOW, endSentAt: null },
    ]);
    const sent = stubNetwork({ results: relay.results });
    await sync(env, finished, NOW + 60_000);
    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual([
      "end",
      "end",
    ]);
  });

  it("deletes a channel at APNs when it can't record it", async () => {
    const env = await makeEnv();
    replaceD1(env, (db) => ({
      prepare: (sql) => {
        if (sql.startsWith("INSERT INTO live_channels")) throw new Error("D1 unavailable");
        return db.prepare(sql);
      },
    }));
    const sent = stubNetwork();

    await expect(update(env, NOW, race())).rejects.toThrow("D1 unavailable");

    expect(
      sent.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"]),
    ).toEqual(["channel-1"]);
  });

  it("deletes at a later try a channel it can't record, when deleting it at once fails too", async () => {
    const env = await makeEnv();
    const db = env.DB;
    replaceD1(env, () => ({
      prepare: (sql) => {
        if (sql.startsWith("INSERT INTO live_channels")) throw new Error("D1 unavailable");
        return db.prepare(sql);
      },
    }));
    answer(({ method }) =>
      method === "POST"
        ? new Response(null, { status: 201, headers: { "apns-channel-id": "channel-1" } })
        : new Response(null, { status: 500 }),
    );
    await expect(update(env, NOW, race())).rejects.toThrow("D1 unavailable");

    const sent = stubNetwork();
    await update(testEnv, NOW + 60_000);
    expect(
      sent.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"]),
    ).toEqual(["channel-1"]);
  });

  it("signs a new provider token when APNs rejects one, even with no subrequest left to retry", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const later = NOW + 30 * 60_000;

    const outcome = await new ProviderTokens(env, later, new SubrequestBudget(1)).send("sandbox", async () => ({
      kind: "expiredProviderToken",
    }));

    expect(outcome).toEqual({ kind: "deferred" });
    const cached = await env.DB.prepare(
      "SELECT updated_at AS updatedAt FROM settings WHERE key = 'apns_token_sandbox'",
    ).first();
    expect(cached).toEqual({ updatedAt: later });
  });

  it("keeps the activity of a race the calendar stops listing until the system has ended it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const events = (sent: Sent[]) =>
      broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event);
    // Its alarm ends it, the calendar no longer calling its object.
    expect(await alarmOf()).toBe(Date.parse("2026-11-27T03:15:00Z"));

    const meanwhile = stubNetwork();
    await update(env, NOW + 60_000);
    const later = stubNetwork();
    await update(env, Date.parse("2026-11-27T03:15:00Z"));

    expect([events(meanwhile), events(later)]).toEqual([[], ["end", "end"]]);
  });

  it("follows no race past the time its activity could be on screen", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    const sent = stubNetwork();
    await sync(env, [race()], Date.parse("2026-11-27T03:15:00Z"));
    await sync(env, [race()], Date.parse("2026-11-27T03:16:00Z"));

    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual([
      "end",
      "end",
    ]);
    expect(sent.filter((request) => request.url.includes("api-manage-broadcast"))).toEqual([]);
  });

  it("sets its alarm for the next end, then for the deletion, and none once the channels are deleted", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];
    stubNetwork({ results: relay.results });

    await sync(env, finished, NOW);
    expect(await alarmOf()).toBe(NOW + 10 * 60_000);
    await update(env, NOW + 50 * 60_000);
    expect(await alarmOf()).toBe(NOW + 60 * 60_000);
    await update(env, NOW + 60 * 60_000);
    expect(await alarmOf()).toBeNull();
  });

  it("sends the end again from its alarm", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork({ results: relay.results });
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    const sent = stubNetwork();
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(NOW + 10 * 60_000);
      expect(await runDurableObjectAlarm(activity())).toBe(true);
    } finally {
      vi.useRealTimers();
    }

    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual([
      "end",
      "end",
    ]);
    expect(await alarmOf()).toBe(NOW + 20 * 60_000);
  });

  it("keeps in a dropped channel's replacement the leaders looked up when APNs dropped it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", results: relay.results });
    await sync(env, [race({ IsLive: true })], NOW + 60_000);

    stubNetwork({ resultsStatus: 503 });
    await sync(env, [race({ IsLive: true })], NOW + 2 * 60_000);

    const ahead = { ...relayFinal, phase: "live" };
    expect((await channels(env)).map(({ state }) => JSON.parse(state))).toEqual([ahead, ahead]);
  });

  it("seeds a dropped channel's replacement with the leaders the same run looked up", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", results: live.results });
    await sync(env, [race({ IsLive: true })], NOW);

    stubNetwork({ results: relay.results });
    await sync(env, [race({ IsLive: true })], NOW + 60_000);

    const ahead = { ...relayFinal, phase: "live" };
    expect((await channels(env)).map(({ state }) => JSON.parse(state))).toEqual([ahead, ahead]);
  });

  it("opens the channels of every race listed in one run, each from its own object", async () => {
    const env = await makeEnv();
    const sent = stubNetwork();
    const races = ["A", "B", "C"].map((suffix) => race({ RaceId: RACE_ID + suffix }));
    for (const { id } of races) {
      await env.DB.prepare(
        "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'x', 'x', 'scheduled', 0)",
      )
        .bind(id)
        .run();
    }
    const before = await listDurableObjectIds(env.RACE_ACTIVITY);

    await sync(env, races, NOW);

    expect(sent.filter((request) => request.url.includes("api-manage-broadcast")).length).toBe(6);
    const created = (await listDurableObjectIds(env.RACE_ACTIVITY)).filter(
      (id) => !before.some((known) => known.equals(id)),
    );
    expect(created.length).toBe(races.length);
    for (const { id } of races) {
      expect(created.some((created) => created.equals(env.RACE_ACTIVITY.idFromName(id)))).toBe(true);
    }
  });

  it("keeps opening channels in one environment while the other fails", async () => {
    const env = await makeEnv();
    const races = ["A", "B", "C", "D", "E"].map((suffix) => race({ RaceId: RACE_ID + suffix }));
    for (const { id } of races) {
      await env.DB.prepare(
        "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'x', 'x', 'scheduled', 0)",
      )
        .bind(id)
        .run();
    }

    stubNetwork({ failingHost: "api-manage-broadcast.push.apple.com" });
    for (const run of [0, 1, 2]) await sync(env, races, NOW + run * 60_000);

    expect((await channels(env)).map(({ environment }) => environment)).toEqual(Array(5).fill("sandbox"));
  });

  it("gives up the requests APNs leaves unanswered once the update's time is up, and sends them at the next run", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const before = await channels(env);

    stubNetwork();
    unanswered("/4/broadcasts/");
    // An update past 30 s would reset the object (blockConcurrencyWhile), and a subrequest has no time limit.
    await update(env, NOW, race({ IsLive: true }), env, Date.now() + 50);
    expect(await channels(env)).toEqual(before);

    const sent = stubNetwork();
    await update(env, NOW + 60_000, race({ IsLive: true }));
    expect(broadcasts(sent)).toHaveLength(2);
  });

  it("gives up a race's results the IBU API leaves unanswered once the update's time is up", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);

    stubNetwork();
    unanswered("biathlonresults.com");
    await update(env, NOW, race({ IsLive: true }), env, Date.now() + 50);

    expect((await channels(env)).map(({ state }) => (JSON.parse(state) as LiveState).phase)).toEqual(["live", "live"]);
  });

  it("sends the end again while the calendar can't be read", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork({ results: relay.results });
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    const sent = stubNetwork();
    await update(env, NOW + 10 * 60_000);

    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual([
      "end",
      "end",
    ]);
    expect(sent.filter((request) => request.url.includes("api-manage-broadcast"))).toEqual([]);
  });
});

describe("pruning", () => {
  const HOUR = 60 * 60_000;

  it("forgets the channels deleted at APNs once no activity they ended can still be on screen", async () => {
    const env = await makeEnv();
    const ended = NOW - 12 * HOUR;
    const insert = (environment: string, channelId: string, endedAt: number | null, deletedAt: number | null) =>
      env.DB.prepare(
        "INSERT INTO live_channels (race_id, environment, channel_id, state, published_at, created_at, ended_at, deleted_at) VALUES (?1, ?2, ?3, '{}', 0, 0, ?4, ?5)",
      )
        .bind(RACE_ID, environment, channelId, endedAt, deletedAt)
        .run();
    await insert("production", "over", ended - 1, ended);
    await insert("sandbox", "not-deleted-at-APNs", ended - 1, null);

    await pruneChannels(env.DB, NOW);

    expect((await channels(env)).map(({ channelId }) => channelId)).toEqual(["not-deleted-at-APNs"]);

    await env.DB.prepare("DELETE FROM live_channels").run();
    await insert("production", "ended-lately", ended, ended);
    await insert("sandbox", "followed", null, ended - 1);

    await pruneChannels(env.DB, NOW);

    expect((await channels(env)).map(({ channelId }) => channelId)).toEqual(["ended-lately", "followed"]);
  });

  it("forgets the races of past seasons, which the watcher no longer polls", async () => {
    const env = await makeEnv();
    const insert = (id: string, startTime: string) =>
      env.DB.prepare(
        "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'x', ?2, 'finished', 0)",
      )
        .bind(id, startTime)
        .run();
    await insert("BT2526SWRLCP09SMMS", "2026-03-22T13:45:00.000Z");
    // Still referenced by a channel whose deletion at APNs keeps failing.
    await insert("BT2526SWRLCP09SWMS", "2026-03-22T11:00:00.000Z");
    await env.DB.prepare(
      "INSERT INTO live_channels (race_id, environment, channel_id, state, published_at, created_at, ended_at) VALUES ('BT2526SWRLCP09SWMS', 'production', 'c', '{}', 0, 0, 0)",
    ).run();

    await pruneRaces(env.DB, Date.parse("2026-07-01T03:00:00Z"));

    const { results } = await env.DB.prepare("SELECT id FROM races ORDER BY id").all<{ id: string }>();
    expect(results.map(({ id }) => id)).toEqual(["BT2526SWRLCP09SWMS", RACE_ID]);
  });

  it("prunes once a day, in the cron run of 03:00 UTC", async () => {
    const env = await makeEnv();
    await env.DB.prepare(
      "INSERT INTO live_channels (race_id, environment, channel_id, state, published_at, created_at, ended_at, deleted_at) VALUES (?1, 'production', 'c', '{}', 0, 0, 0, 0)",
    )
      .bind(RACE_ID)
      .run();
    answer(() => Response.json([]));
    const run = (time: string) =>
      worker.scheduled(createScheduledController({ scheduledTime: Date.parse(time), cron: "* * * * *" }), env);

    await run("2027-07-01T02:59:00Z");
    expect((await env.DB.prepare("SELECT id FROM races").all()).results).toEqual([{ id: RACE_ID }]);

    await run("2027-07-01T03:00:00Z");
    expect(await channels(env)).toEqual([]);
    expect((await env.DB.prepare("SELECT id FROM races").all()).results).toEqual([]);
  });
});

describe("GET /v1/races/:id/channels/:environment", () => {
  const get = (env: Env, path: string) =>
    worker.fetch(new Request(`https://server.test${path}`), env, createExecutionContext());

  it("gives the app the race's channel for its APNs environment, with its current state and the broadcast's timestamp", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const sent = stubNetwork();
    await sync(env, [race({ IsLive: true })], NOW + 90_000);

    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(response.status).toBe(200);
    const { aps } = broadcasts(sent)[0]!.body as { aps: { timestamp: number } };
    expect(await response.json()).toEqual({ channelId: "channel-2", state: live.state, timestamp: aps.timestamp });
  });

  it("dates the state a channel opens with from its opening, older than any broadcast on it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW + 1_500);

    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(await response.json()).toMatchObject({ timestamp: Math.floor((NOW + 1_500) / 1000) });
  });

  it("keeps its answers out of HTTP caches, since the channel can change at every run", async () => {
    const env = await makeEnv();
    for (const status of [404, 200]) {
      const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
      expect([response.status, response.headers.get("cache-control")]).toEqual([status, "no-store"]);
      stubNetwork();
      await sync(env, [race()], NOW);
    }
  });

  it("answers 410 with the final state once the race's activity has ended, even after its channel is deleted", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];
    stubNetwork({ results: relay.results });
    await sync(env, finished, NOW);

    for (const now of [NOW, NOW + 60 * 60_000]) {
      stubNetwork();
      await sync(env, finished, now);
      const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
      expect(response.status).toBe(410);
      expect(await response.json()).toEqual({ state: relayFinal });
    }
  });

  it("answers 410 with the final state when APNs no longer knew the channel at the end", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];
    stubNetwork({ results: relay.results, broadcastReason: "ChannelNotRegistered" });
    await sync(env, finished, NOW);

    const later = stubNetwork({ results: relay.results });
    await sync(env, finished, NOW + 60 * 60_000);
    expect(later.filter((request) => !request.url.includes("biathlonresults.com"))).toEqual([]);
    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(response.status).toBe(410);
    expect(await response.json()).toEqual({ state: relayFinal });
  });

  it("answers 404 for a channel APNs no longer knows, until it is replaced", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", failingHost: "api-manage-broadcast" });
    await sync(env, [race({ IsLive: true })], NOW);

    expect((await get(env, `/v1/races/${RACE_ID}/channels/sandbox`)).status).toBe(404);
  });

  it("answers 410 with the final state when a race ends before its dropped channel is replaced", async () => {
    const env = await makeEnv();
    stubNetwork();
    await sync(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", failingHost: "api-manage-broadcast" });
    await sync(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork({ results: relay.results });
    await sync(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 60_000);

    expect(sent.filter((request) => !request.url.includes("biathlonresults.com"))).toEqual([]);
    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(response.status).toBe(410);
    expect(await response.json()).toEqual({ state: relayFinal });
  });

  it("answers 404 for a race without a channel and 400 for an unknown environment", async () => {
    const env = await makeEnv();
    expect((await get(env, `/v1/races/${RACE_ID}/channels/production`)).status).toBe(404);
    expect((await get(env, `/v1/races/${RACE_ID}/channels/staging`)).status).toBe(400);
  });
});

describe("alerts", () => {
  const PERSISTED = "SELECT token, attempts FROM outbox ORDER BY id";

  async function queue(env: Env, tokens: string[], kind = "cancelled") {
    for (const token of tokens) {
      await env.DB.prepare(
        "INSERT INTO outbox (token, environment, kind, race_id, race_name, start_time, locale, time_zone, created_at) VALUES (?1, 'sandbox', ?2, ?3, 'x', '2026-11-26T15:15:00.000Z', 'fr', 'Europe/Paris', ?4)",
      )
        .bind(token, kind, RACE_ID, NOW)
        .run();
    }
  }

  const devicePushes = (sent: Sent[]) => sent.filter((request) => request.url.includes("/3/device/"));

  it("sends a run's alerts in lots of 50 Durable Object calls, more than the run's own subrequests", async () => {
    const env = await makeEnv();
    const lots = recordLots();
    await queue(
      env,
      Array.from({ length: 120 }, (_, index) => `t${index}`),
    );
    const sent = stubNetwork();

    await drainOutbox(env, NOW);

    expect(lots().toSorted((a, b) => b - a)).toEqual([50, 50, 20]);
    expect(devicePushes(sent).length).toBe(120);
    expect((await env.DB.prepare(PERSISTED).all()).results).toEqual([]);
  });

  it("queues an alert for the devices that follow the race's category and this kind of change", async () => {
    const env = await makeEnv();
    const register = async (token: string, categories: string[], cancellation = true) => {
      const key = `key-${token}`;
      await env.DB.prepare(
        "INSERT INTO app_attest_keys (key_id, public_key, environment, counter, receipt, created_at) VALUES (?1, '', 'development', 0, '', 0)",
      )
        .bind(key)
        .run();
      const device = parseRegistration(token, {
        environment: "sandbox",
        categories,
        cancellation,
        rescheduling: true,
        locale: "fr",
        timeZone: "Europe/Paris",
      });
      if (typeof device === "string") throw new Error(device);
      await saveDevice(env.DB, device, key, 0);
    };
    await register("aa".repeat(32), ["SW", "SM"]);
    await register("bb".repeat(32), ["SW", "MX"]);
    await register("cc".repeat(32), ["SM"], false);
    const stored = await env.DB.prepare("SELECT categories FROM devices WHERE token = ?1")
      .bind("aa".repeat(32))
      .first();
    expect(stored).toEqual({ categories: '["SW","SM"]' });
    answer(({ url }) =>
      url.includes("/Events")
        ? Response.json([{ EventId: RACE_ID.slice(0, 14), StartDate: "2026-11-23", EndDate: "2026-11-29" }])
        : Response.json([
            {
              RaceId: RACE_ID,
              catId: "SM",
              ShortDescription: "Men's 20km Individual",
              StartTime: "2026-11-26T15:15:00Z",
              StatusId: 6,
            },
          ]),
    );

    await pollRaces(env, NOW);

    const queued = await env.DB.prepare("SELECT token, kind FROM outbox ORDER BY token").all();
    expect(queued.results).toEqual([{ token: "aa".repeat(32), kind: "cancelled" }]);
  });

  it("converts the categories written comma-separated before they were JSON", async () => {
    const env = await makeEnv();
    const insert = env.DB.prepare(
      "INSERT INTO devices (token, environment, categories, cancellation, rescheduling, locale, time_zone, updated_at) VALUES (?1, 'sandbox', ?2, 1, 1, 'fr', 'Europe/Paris', 0)",
    );
    await env.DB.batch([
      insert.bind("aa".repeat(32), "MX,SM"),
      insert.bind("bb".repeat(32), "SW"),
      insert.bind("cc".repeat(32), ""),
      insert.bind("dd".repeat(32), '["SM"]'),
    ]);
    const migration = testEnv.TEST_MIGRATIONS.find(({ name }) => name === "0006_device_categories_json.sql")!;

    for (const query of migration.queries) await env.DB.prepare(query).run();

    const { results } = await env.DB.prepare("SELECT categories FROM devices ORDER BY token").all();
    expect(results).toEqual([
      { categories: '["MX","SM"]' },
      { categories: '["SW"]' },
      { categories: "[]" },
      { categories: '["SM"]' },
    ]);
  });

  it("runs the cron once per scheduled minute, though Cloudflare sometimes fires it twice", async () => {
    const env = await makeEnv();
    const minute = Date.parse("2026-11-26T14:45:00Z");

    expect(await claimCronRun(env.DB, minute)).toBe(true);
    // Fired again for the same minute, at once or a little later.
    expect(await claimCronRun(env.DB, minute)).toBe(false);
    expect(await claimCronRun(env.DB, minute + 900)).toBe(false);
    expect(await claimCronRun(env.DB, minute + 60_000)).toBe(true);
    // A late run of an earlier minute.
    expect(await claimCronRun(env.DB, minute)).toBe(false);
  });

  it("sends a run's alerts once when Cloudflare fires the cron twice for one minute", async () => {
    const env = await makeEnv();
    await queue(env, ["a"]);
    // APNs unavailable: the alert stays queued for the next run.
    const sent = stubNetwork({ deviceStatus: 503 });
    answer(({ url }) => (url.includes("/Events?") ? Response.json([]) : undefined));

    for (const scheduledTime of [NOW, NOW + 900]) {
      await worker.scheduled(createScheduledController({ scheduledTime, cron: "* * * * *" }), env);
    }

    expect(devicePushes(sent).length).toBe(1);
    expect((await env.DB.prepare(PERSISTED).all()).results).toEqual([{ token: "a", attempts: 1 }]);
  });

  it("sends a lot from its Durable Object, with the outcome of each push at its index", async () => {
    const env = await makeEnv();
    answer(({ url }) => new Response(null, { status: url.endsWith("/gone") ? 410 : 200 }));
    const push = (deviceToken: string) => ({
      deviceToken,
      environment: "sandbox" as const,
      topic: env.APNS_TOPIC,
      payload: {},
      expiration: 0,
    });

    const outcomes = await runInDurableObject(
      env.PUSH_SENDER.get(env.PUSH_SENDER.newUniqueId()),
      (sender: PushSender) => sender.send([push("kept"), push("gone"), push("also-kept")], "provider token"),
    );

    expect(outcomes).toEqual([{ kind: "sent" }, { kind: "unregistered" }, { kind: "sent" }]);
  });

  it("gives up the pushes of a lot APNs leaves unanswered at the deadline it is given, for a later run", async () => {
    const env = await makeEnv();
    answer(({ url }) =>
      url.endsWith("/stalled") ? new Promise<Response>(() => {}) : new Response(null, { status: 200 }),
    );
    const push = (deviceToken: string) => ({
      deviceToken,
      environment: "sandbox" as const,
      topic: env.APNS_TOPIC,
      payload: {},
      expiration: 0,
    });

    const outcomes = await runInDurableObject(
      env.PUSH_SENDER.get(env.PUSH_SENDER.newUniqueId()),
      (sender: PushSender) => sender.send([push("sent"), push("stalled")], "provider token", Date.now() + 50),
    );

    expect(outcomes.map(({ kind }) => kind)).toEqual(["sent", "retry"]);
  });

  it("sends a lot's pushes six at a time, the connections a Durable Object request may open at once", async () => {
    const env = await makeEnv();
    let inFlight = 0;
    let most = 0;
    answer(async () => {
      inFlight += 1;
      most = Math.max(most, inFlight);
      await scheduler.wait(5);
      inFlight -= 1;
      return new Response(null, { status: 200 });
    });
    const pushes = Array.from({ length: 20 }, (_, index) => ({
      deviceToken: `t${index}`,
      environment: "sandbox" as const,
      topic: env.APNS_TOPIC,
      payload: {},
      expiration: 0,
    }));

    const outcomes = await runInDurableObject(
      env.PUSH_SENDER.get(env.PUSH_SENDER.newUniqueId()),
      (sender: PushSender) => sender.send(pushes, "provider token"),
    );

    expect(outcomes).toEqual(pushes.map(() => ({ kind: "sent" })));
    expect(most).toBe(6);
  });

  it("sends each lot from a Durable Object of its own, which no overlapping run shares", async () => {
    // Concurrent requests to one object share its 50 subrequests: measured on 2026-10-25, when
    // Cloudflare fired the cron twice within a second.
    const env = await makeEnv();
    const lots = recordLots();
    // Durable Objects outlive a test: count the objects this one creates.
    const before = (await listDurableObjectIds(env.PUSH_SENDER)).length;
    await queue(
      env,
      Array.from({ length: 60 }, (_, index) => `a${index}`),
    );
    stubNetwork();
    await drainOutbox(env, NOW);
    await queue(
      env,
      Array.from({ length: 60 }, (_, index) => `b${index}`),
    );
    await drainOutbox(env, NOW);

    expect(lots().length).toBe(4);
    expect((await listDurableObjectIds(env.PUSH_SENDER)).length - before).toBe(4);
  });

  it("builds each alert in the device's language and time zone", async () => {
    const env = await makeEnv();
    await queue(env, ["a"], "rescheduled");
    const sent = stubNetwork();

    await drainOutbox(env, NOW);

    expect(devicePushes(sent)[0]?.body).toEqual(
      buildPayload({
        kind: "rescheduled",
        raceId: RACE_ID,
        raceName: "x",
        startTime: "2026-11-26T15:15:00.000Z",
        locale: "fr",
        timeZone: "Europe/Paris",
      }),
    );
  });

  it("leaves the alerts past the run's push capacity to the next run", async () => {
    const env = await makeEnv();
    await queue(env, ["a", "b"]);
    const sent = stubNetwork();

    await drainOutbox(env, NOW, pushLots(env, NOW, 1));

    expect(devicePushes(sent).length).toBe(1);
    expect((await env.DB.prepare(PERSISTED).all()).results).toEqual([{ token: "b", attempts: 0 }]);
  });

  it("forgets the devices APNs no longer knows in a few D1 queries", async () => {
    const env = await makeEnv();
    await queue(
      env,
      Array.from({ length: 60 }, (_, index) => `t${index}`),
    );
    const calls = countD1Queries(env);
    stubNetwork({ deviceStatus: 410 });

    await drainOutbox(env, NOW);

    expect(calls()).toBeLessThanOrEqual(5);
    expect((await env.DB.prepare(PERSISTED).all()).results).toEqual([]);
  });

  it("tries the alerts of a lot that failed again", async () => {
    const env = await makeEnv();
    vi.spyOn(PushSender.prototype, "send").mockRejectedValue(new Error("Durable Object unavailable"));
    await queue(env, ["a", "b"]);
    stubNetwork();

    await drainOutbox(env, NOW);

    expect((await env.DB.prepare(PERSISTED).all()).results).toEqual([
      { token: "a", attempts: 1 },
      { token: "b", attempts: 1 },
    ]);
  });
});

describe("Live Activities started for favorites", () => {
  const START = Date.parse("2026-11-26T15:15:00Z");
  const DUE = START - 30 * 60_000;
  const PERROT = "BTFRA00000000001";
  const KEY = "key";
  /** The published start list of the scheduled race. */
  const START_LIST: IBUResults = { ...live.results, IsStartList: true };
  const stub = (options: Parameters<typeof stubNetwork>[0] = {}) => stubNetwork({ results: START_LIST, ...options });

  /** Saves the favorites of the install `key`, by default one per token. */
  async function save(env: Env, token: string, body: object, key = `${KEY}-${token}`) {
    await env.DB.prepare(
      "INSERT INTO app_attest_keys (key_id, public_key, environment, counter, receipt, created_at) VALUES (?1, '', 'development', 0, '', 0) ON CONFLICT DO NOTHING",
    )
      .bind(key)
      .run();
    const registration = parseStartRegistration(token, {
      environment: "production",
      athletes: [],
      nations: [],
      ...body,
    });
    if (typeof registration === "string") throw new Error(registration);
    await saveStartToken(env.DB, registration, key, 0);
  }

  /** A race with its channels, and tokens: Perrot's fan, an Italy fan who has nobody racing, and a sandbox France fan. */
  async function setUp() {
    const env = await makeEnv();
    stub();
    await sync(env, [race()], DUE - 60 * 60_000);
    await save(env, "aa".repeat(32), { athletes: [PERROT] });
    await save(env, "bb".repeat(32), { nations: ["ITA"] });
    await save(env, "cc".repeat(32), { environment: "sandbox", nations: ["FRA"] });
    return env;
  }

  const starts = (sent: Sent[]) => sent.filter((request) => request.url.includes("/3/device/"));
  /** The devices started, sorted: the APNs environments' lots go out at once. */
  const startUrls = (sent: Sent[]) =>
    starts(sent)
      .map((request) => request.url)
      .sort();
  const startOn = (sent: Sent[], host: string) => starts(sent).find((request) => request.url.startsWith(host));
  const ibu = (sent: Sent[]) => sent.filter((request) => request.url.includes("biathlonresults.com"));

  it("starts the race's activity on its channel for the devices whose favorites are on the start list, 30 minutes before", async () => {
    const env = await setUp();
    const sent = stub();
    await sync(env, [race()], DUE - 60_000);
    expect(sent).toEqual([]);

    await sync(env, [race()], DUE);
    expect(ibu(sent).map((request) => request.url)).toEqual([
      `https://biathlonresults.com/modules/sportapi/api/Results?RaceId=${RACE_ID}`,
    ]);
    const [production, sandbox] = await channels(env);
    expect(startUrls(sent)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
    // Apple: push type liveactivity, its own topic, an alert, and iOS 18's input-push-channel.
    expect(startOn(sent, "https://api.push.apple.com")?.headers).toMatchObject({
      "apns-push-type": "liveactivity",
      "apns-topic": "com.fouteox.biathlon.push-type.liveactivity",
      "apns-priority": "10",
      // Kept by APNs until a while after the race starts, for a device offline meanwhile.
      "apns-expiration": String(START / 1000 + 15 * 60),
    });
    expect(startOn(sent, "https://api.push.apple.com")!.body).toEqual({
      aps: {
        timestamp: DUE / 1000,
        event: "start",
        "relevance-score": 0.5,
        "content-state": JSON.parse(production!.state),
        "attributes-type": "RaceActivityAttributes",
        attributes: { raceID: RACE_ID, name: "Men's 20km Individual", channelID: production!.channelId },
        "input-push-channel": production!.channelId,
        alert: {
          title: { "loc-key": "race.SMIN" },
          body: { "loc-key": "push.liveActivity" },
          sound: "default",
        },
      },
    });
    expect(
      (startOn(sent, "https://api.sandbox.push.apple.com")!.body as { aps: { "input-push-channel": string } }).aps[
        "input-push-channel"
      ],
    ).toBe(sandbox!.channelId);

    // Each device is checked once per race.
    const later = stub();
    await sync(env, [race({ IsLive: true })], DUE + 20 * 60_000);
    expect(starts(later)).toEqual([]);
  });

  it("gives up the starts APNs leaves unanswered once the update's time is up, and sends them at the next run", async () => {
    const env = await setUp();
    stub();
    unanswered("/3/device/");
    await update(env, DUE, race(), env, Date.now() + 50);

    const sent = stub();
    await update(env, DUE + 60_000, race());
    expect(startUrls(sent)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("starts more activities in one update than its own subrequests, in lots of 50", async () => {
    const env = await setUp();
    const lots = recordLots();
    const fans = Array.from({ length: 120 }, (_, index) => index.toString(16).padStart(64, "0"));
    for (const token of fans) await save(env, token, { athletes: [PERROT] });
    const sent = stub();

    await sync(env, [race()], DUE);

    expect(starts(sent).length).toBe(122);
    expect(Math.max(...lots())).toBe(50);
    expect(lots().reduce((sum, size) => sum + size, 0)).toBe(122);
  });

  it("claims and settles a race's starts in a few D1 queries, whatever their number", async () => {
    const env = await setUp();
    for (const index of Array.from({ length: 120 }, (_, value) => value)) {
      await save(env, index.toString(16).padStart(64, "0"), { athletes: [PERROT] });
    }
    // The Workers Free plan allows 50 D1 queries per invocation.
    const calls = countD1Queries(env);
    stub({ deviceStatus: 503 });

    await update(env, DUE, race(), testEnv);

    // The race's channels, read twice, the checks, a claim and a settle.
    expect(calls()).toBeLessThanOrEqual(8);
    const sent = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(starts(sent).length).toBe(122);
  });

  it("claims nothing when D1 fails while claiming, for the next run to start them all", async () => {
    const env = await setUp();
    replaceD1(env, (db) => ({
      prepare: (sql) => {
        if (sql.includes("RETURNING")) throw new Error("D1 unavailable");
        return db.prepare(sql);
      },
    }));
    const failed = stub();
    await expect(update(env, DUE, race())).rejects.toThrow("D1 unavailable");
    expect(starts(failed)).toEqual([]);

    const sent = stub();
    await sync(testEnv, [race()], DUE + 60_000);
    expect(startUrls(sent)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("checks the race again for a device whose favorites changed, but never starts it twice", async () => {
    const env = await setUp();
    stub();
    await sync(env, [race()], DUE);

    await save(env, "aa".repeat(32), { athletes: [PERROT], nations: ["SWE"] });
    await save(env, "bb".repeat(32), { nations: ["FRA"] });
    const sent = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(startUrls(sent)).toEqual([`https://api.push.apple.com/3/device/${"bb".repeat(32)}`]);
  });

  it("checks again only for changed favorites, and keeps an install's starts when its token changes", async () => {
    const env = await setUp();
    stub();
    await sync(env, [race()], DUE);

    // The app sends its favorites at every launch, and ActivityKit can replace the token.
    await save(env, "bb".repeat(32), { nations: ["ITA"] });
    await save(env, "dd".repeat(32), { athletes: [PERROT] }, `${KEY}-${"aa".repeat(32)}`);
    const sent = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(starts(sent)).toEqual([]);
  });

  it("matches the favorites a device saved while the start list was read", async () => {
    const env = await setUp();
    const sent = stub({ duringResults: () => save(env, "bb".repeat(32), { nations: ["FRA"] }) });
    await sync(env, [race()], DUE);
    expect(starts(sent).map((request) => request.url)).toContain(
      `https://api.push.apple.com/3/device/${"bb".repeat(32)}`,
    );
  });

  it("starts nothing for a device whose favorites changed or that opted out while the start list was read", async () => {
    const env = await setUp();
    const sent = stub({
      duringResults: async () => {
        await save(env, "aa".repeat(32), { athletes: ["BTSUI00000000009"] });
        await env.DB.prepare("DELETE FROM live_start_tokens WHERE environment = 'sandbox'").run();
      },
    });
    await sync(env, [race()], DUE);
    expect(starts(sent)).toEqual([]);
  });

  it("checks again the devices none of whose favorites raced when the start list changes before the race", async () => {
    const env = await setUp();
    stub();
    await sync(env, [race()], DUE);

    // An Italian added to the start list.
    const entrant = { IBUId: "BTITA00000000006", Name: "GIACOMEL Tommaso", Nat: "ITA" };
    const amended = { ...START_LIST, Results: [...(START_LIST.Results ?? []), entrant] };
    const sent = stub({ results: amended });
    await sync(env, [race()], DUE + 60_000);
    expect(startUrls(sent)).toEqual([`https://api.push.apple.com/3/device/${"bb".repeat(32)}`]);
  });

  it("starts the activity again on the channel that replaces a dropped one", async () => {
    const env = await setUp();
    stub();
    await sync(env, [race()], DUE);

    // The activities on the dropped channel get none of its replacement's broadcasts.
    await env.DB.prepare("UPDATE live_channels SET channel_id = 'replacement' WHERE environment = 'production'").run();
    const sent = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(startUrls(sent)).toEqual([`https://api.push.apple.com/3/device/${"aa".repeat(32)}`]);
    expect((starts(sent)[0]!.body as { aps: { "input-push-channel": string } }).aps["input-push-channel"]).toBe(
      "replacement",
    );
  });

  it("forgets the favorites no launch of the app sent again for a year", async () => {
    const env = await setUp();
    await env.DB.prepare("UPDATE live_start_tokens SET updated_at = ?1 WHERE token <> ?2")
      .bind(START, "aa".repeat(32))
      .run();
    await pruneStarts(env.DB, START + 365 * 24 * 60 * 60_000);
    const { results } = await env.DB.prepare("SELECT token FROM live_start_tokens ORDER BY token").all<{
      token: string;
    }>();
    expect(results.map(({ token }) => token)).toEqual(["bb".repeat(32), "cc".repeat(32)]);
  });

  it("starts the activity with the state just published on its channel", async () => {
    const env = await setUp();
    const sent = stubNetwork();
    await sync(env, [race({ IsLive: true })], START + 60_000);
    expect(
      (startOn(sent, "https://api.push.apple.com")!.body as { aps: { "content-state": unknown } }).aps["content-state"],
    ).toEqual(live.state);
  });

  it("forgets the checks of races two days after their start", async () => {
    const env = await setUp();
    stub();
    await sync(env, [race()], DUE);
    const checks = async () =>
      (await env.DB.prepare("SELECT COUNT(*) AS n FROM live_starts").first<{ n: number }>())!.n;
    await pruneStarts(env.DB, START + 47 * 60 * 60_000);
    expect(await checks()).toBe(3);
    await pruneStarts(env.DB, START + 49 * 60 * 60_000);
    expect(await checks()).toBe(0);
  });

  it("sends each start once when cron runs overlap", async () => {
    const env = await setUp();
    const sent = stub();
    await Promise.all([sync(env, [race()], DUE), sync(env, [race()], DUE)]);
    expect(startUrls(sent)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("starts the activity again when a race is reinstated after its end", async () => {
    const env = await setUp();
    stub();
    await sync(env, [race()], DUE);
    await sync(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], DUE + 60_000);

    const sent = stub({ channelPrefix: "reinstated" });
    await sync(env, [race()], DUE + 2 * 60_000);
    const [production] = await channels(env);
    const channelOf = (host: string) =>
      (startOn(sent, host)!.body as { aps: { "input-push-channel": string } }).aps["input-push-channel"];
    expect(starts(sent).length).toBe(2);
    expect(channelOf("https://api.push.apple.com")).toBe(production!.channelId);
  });

  it("waits for the start list, and for an open channel", async () => {
    const env = await setUp();
    await env.DB.prepare("UPDATE live_channels SET deleted_at = 1 WHERE environment = 'sandbox'").run();
    const empty = stub({ results: { ...START_LIST, Results: [] }, failingHost: "api-manage-broadcast" });
    await sync(env, [race()], DUE);
    expect(starts(empty)).toEqual([]);

    // The dropped channel can't be replaced yet.
    const sent = stub({ failingHost: "api-manage-broadcast" });
    await sync(env, [race()], DUE + 60_000);
    expect(startUrls(sent)).toEqual([`https://api.push.apple.com/3/device/${"aa".repeat(32)}`]);
  });

  it("starts nothing for a race that is over", async () => {
    const env = await setUp();
    const sent = stub();
    await sync(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], DUE);
    expect(starts(sent)).toEqual([]);
  });

  it("leaves the starts past an update's push capacity to the next run", async () => {
    const env = await setUp();
    for (const index of Array.from({ length: 499 }, (_, value) => value)) {
      await save(env, index.toString(16).padStart(64, "0"), { athletes: [PERROT] });
    }
    const sent = stub();
    await sync(env, [race()], DUE);
    expect(starts(sent).length).toBe(500);

    const next = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(starts(next).length).toBe(1);
  });

  it("waits for the published start list before a scheduled race, and takes the results of a live one", async () => {
    const env = await setUp();
    // Rows the API returns before it marks them as the start list.
    const preliminary = stub({ results: { ...START_LIST, IsStartList: false } });
    await sync(env, [race()], DUE);
    expect(starts(preliminary)).toEqual([]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM live_starts").first<{ n: number }>()).toEqual({ n: 0 });

    const sent = stubNetwork();
    await sync(env, [race({ IsLive: true })], START + 60_000);
    expect(startUrls(sent)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("retries a start when APNs rejects the provider token", async () => {
    const env = await setUp();
    stub({ deviceStatus: 403, deviceReason: "ExpiredProviderToken" });
    await sync(env, [race()], DUE);

    const sent = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(startUrls(sent)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("retries a start when the provider token can't be loaded", async () => {
    const env = await setUp();
    const key = env.APNS_PRODUCTION_KEY;
    env.APNS_PRODUCTION_KEY = "not a key";
    const failed = stub();
    await update(env, DUE, race());
    expect(startUrls(failed)).toEqual([`https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`]);

    env.APNS_PRODUCTION_KEY = key;
    const sent = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(startUrls(sent)).toEqual([`https://api.push.apple.com/3/device/${"aa".repeat(32)}`]);
  });

  it("stops retrying a start after five failed sends", async () => {
    const env = await setUp();
    for (const minute of [0, 1, 2, 3, 4]) {
      const failed = stub({ deviceStatus: 503 });
      await sync(env, [race()], DUE + minute * 60_000);
      expect(starts(failed).length).toBe(2);
    }

    // Each failed send writes its row of live_starts twice, claimed then given back: past five,
    // a lasting APNs outage would spend the day's D1 row writes of the Free plan.
    const sent = stub();
    await sync(env, [race()], DUE + 5 * 60_000);
    expect(starts(sent)).toEqual([]);
  });

  it("forgets a token APNs no longer knows", async () => {
    const env = await setUp();
    stub({ deviceStatus: 410 });
    await sync(env, [race()], DUE);
    const { results } = await env.DB.prepare("SELECT token FROM live_start_tokens ORDER BY token").all<{
      token: string;
    }>();
    expect(results.map(({ token }) => token)).toEqual(["bb".repeat(32)]);
  });

  it("doesn't retry a start APNs refused", async () => {
    const env = await setUp();
    stub({ deviceStatus: 400 });
    await sync(env, [race()], DUE);
    const sent = stub();
    await sync(env, [race()], DUE + 60_000);
    expect(starts(sent)).toEqual([]);
  });
});
