import { readFileSync } from "node:fs";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { snapshot, type IBUCompetition, type RaceSnapshot } from "../src/ibu";
import { liveState, relevanceScore, syncLiveActivities, type IBUResults, type LiveState } from "../src/live";
import { parseStartRegistration, pruneStarts, saveStartToken, startFavoriteActivities } from "../src/liveStarts";
import { ProviderTokens } from "../src/providerTokens";
import { SubrequestBudget } from "../src/subrequests";
import { drainOutbox } from "../src/watcher";
import { makeD1 } from "./d1";

// Shared with the app's BiathlonKit tests, which decode each `content-state` with
// ActivityKit's default strategies and give its local updates the same relevance score.
const cases: { name: string; results: IBUResults; state: unknown; relevanceScore?: number }[] = JSON.parse(
  readFileSync(
    new URL("../../Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures/live-activity.json", import.meta.url),
    "utf8",
  ),
);

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
  vi.stubGlobal("fetch", async (input: string, init: RequestInit = {}) => {
    const url = String(input);
    const headers = Object.fromEntries(new Headers(init.headers).entries());
    sent.push({ method: init.method ?? "GET", url, headers, body: init.body ? JSON.parse(String(init.body)) : undefined });
    if (url.includes("biathlonresults.com")) {
      await options.duringResults?.();
      return Response.json(options.results ?? live.results, { status: options.resultsStatus ?? 200 });
    }
    if (options.failingHost && url.includes(options.failingHost)) return new Response(null, { status: 500 });
    if (url.includes("api-manage-broadcast") && init.method === "POST") {
      channels += 1;
      return new Response(null, { status: 201, headers: { "apns-channel-id": `${options.channelPrefix ?? "channel"}-${channels}` } });
    }
    if (url.includes("api-manage-broadcast") && init.method === "DELETE") return new Response(null, { status: 204 });
    if (url.includes("/3/device/")) {
      const status = (await options.duringDevice?.()) ?? options.deviceStatus;
      if (status) return options.deviceReason ? Response.json({ reason: options.deviceReason }, { status }) : new Response(null, { status });
    }
    if (url.includes("/4/broadcasts/") && options.broadcastReason) {
      return Response.json({ reason: options.broadcastReason }, { status: 400 });
    }
    return new Response(null, { status: 200 });
  });
  return sent;
}

let pem = "";
beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
});

afterEach(() => {
  vi.unstubAllGlobals();
});

async function makeEnv(): Promise<Env> {
  const env = {
    DB: makeD1(),
    APNS_TOPIC: "com.fouteox.biathlon",
    APNS_TEAM_ID: "DEF123GHIJ",
    APNS_SANDBOX_KEY: pem,
    APNS_SANDBOX_KEY_ID: "ABC123DEFG",
    APNS_PRODUCTION_KEY: pem,
    APNS_PRODUCTION_KEY_ID: "HIJ456KLMN",
  } as unknown as Env;
  // The watcher stores each race before its channels reference it.
  await env.DB.prepare(
    "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'Men''s 20km Individual', '2026-11-26T15:15:00.000Z', 'scheduled', 0)",
  )
    .bind(RACE_ID)
    .run();
  return env;
}

const channels = (env: Env) =>
  env.DB.prepare("SELECT environment, channel_id AS channelId, state FROM live_channels ORDER BY environment")
    .all<{ environment: string; channelId: string; state: string }>()
    .then(({ results }) => results);

const retired = (env: Env) =>
  env.DB.prepare("SELECT channel_id AS channelId FROM retired_channels ORDER BY channel_id")
    .all<{ channelId: string }>()
    .then(({ results }) => results.map(({ channelId }) => channelId));

const broadcasts = (sent: Sent[]) => sent.filter((request) => request.url.includes("/4/broadcasts/"));

describe("Live Activity channels", () => {
  it("opens one channel per APNs environment for an upcoming race, without broadcasting", async () => {
    const env = await makeEnv();
    const sent = stubNetwork();

    await syncLiveActivities(env, [race()], NOW);

    const creations = sent.filter((request) => request.method === "POST" && request.url.includes("api-manage-broadcast"));
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
    await syncLiveActivities(env, [race()], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);

    const updates = broadcasts(sent);
    expect(updates.map((request) => [request.url, request.headers["apns-channel-id"]])).toEqual([
      ["https://api.push.apple.com/4/broadcasts/apps/com.fouteox.biathlon", "channel-1"],
      ["https://api.sandbox.push.apple.com/4/broadcasts/apps/com.fouteox.biathlon", "channel-2"],
    ]);
    expect(updates[0]?.headers).toMatchObject({ "apns-push-type": "liveactivity", "apns-priority": "10", "apns-expiration": "0" });
    expect(updates[0]?.body).toEqual({
      aps: { timestamp: NOW / 1000, event: "update", "relevance-score": 1, "content-state": live.state },
    });
  });

  it("broadcasts a new start time of an upcoming race", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ StartTime: "2026-11-26T15:45:00Z" })], NOW);

    expect(broadcasts(sent).map((request) => (request.body as { aps: { "content-state": unknown } }).aps["content-state"])).toEqual([
      { phase: "scheduled", startTime: 817400700, leaders: [] },
      { phase: "scheduled", startTime: 817400700, leaders: [] },
    ]);
    // Upcoming races need no results.
    expect(sent.some((request) => request.url.includes("biathlonresults.com"))).toBe(false);
  });

  it("ends the activity with the final results, sends the end again for offline devices, then deletes the channels", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];

    const sent = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, finished, NOW);
    expect(broadcasts(sent).map((request) => request.body)).toEqual([
      { aps: { timestamp: NOW / 1000, event: "end", "relevance-score": 0, "content-state": relayFinal } },
      { aps: { timestamp: NOW / 1000, event: "end", "relevance-score": 0, "content-state": relayFinal } },
    ]);

    // No message storage: devices offline at the end only get a later send.
    const later = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, finished, NOW + 60_000);
    expect(broadcasts(later)).toEqual([]);
    await syncLiveActivities(env, finished, NOW + 10 * 60_000);
    expect(broadcasts(later).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual(["end", "end"]);
    expect(later.some((request) => request.url.includes("biathlonresults.com"))).toBe(false);
    expect(later.some((request) => request.method === "DELETE")).toBe(false);

    const last = stubNetwork();
    await syncLiveActivities(env, finished, NOW + 60 * 60_000);
    expect(last.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"])).toEqual([
      "channel-1",
      "channel-2",
    ]);
    expect(broadcasts(last)).toEqual([]);
    // The rows stay, for the app to learn that the activity is over.
    expect((await channels(env)).map(({ state }) => JSON.parse(state))).toEqual([relayFinal, relayFinal]);

    const after = stubNetwork();
    await syncLiveActivities(env, finished, NOW + 70 * 60_000);
    expect(after.filter((request) => !request.url.includes("biathlonresults.com"))).toEqual([]);
  });

  it("ends a race from the calendar when its results don't describe it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    const sent = stubNetwork({ results: { RaceId: RACE_ID, Results: [] } });
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual(["end", "end"]);
  });

  it("ends a finished race with its last state when its results can't be read", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork({ resultsStatus: 503 });
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 60_000);

    expect(broadcasts(sent).map((request) => request.body)).toEqual([
      { aps: { timestamp: NOW / 1000 + 60, event: "end", "relevance-score": 0, "content-state": { ...(live.state as object), phase: "finished" } } },
      { aps: { timestamp: NOW / 1000 + 60, event: "end", "relevance-score": 0, "content-state": { ...(live.state as object), phase: "finished" } } },
    ]);
  });

  it("ends a finished race with the calendar's phase when its results still say it is live", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    expect(broadcasts(sent).map((request) => (request.body as { aps: { "content-state": unknown } }).aps["content-state"])).toEqual([
      { ...(live.state as object), phase: "finished" },
      { ...(live.state as object), phase: "finished" },
    ]);
  });

  it("keeps the last leaders when the results stop describing the race", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);
    const withoutCompetition = { RaceId: RACE_ID, Results: [] };

    const unchanged = stubNetwork({ results: withoutCompetition });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);
    expect(broadcasts(unchanged)).toEqual([]);

    const sent = stubNetwork({ results: withoutCompetition });
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 120_000);
    expect(broadcasts(sent).map((request) => (request.body as { aps: { "content-state": unknown } }).aps["content-state"])).toEqual([
      { ...(live.state as object), phase: "finished" },
      { ...(live.state as object), phase: "finished" },
    ]);
  });

  it("follows the calendar's phase, ending the activity only once the calendar says the race is over", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const ahead = { ...relayFinal, phase: "live" };

    const sent = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);
    expect(broadcasts(sent).map((request) => request.body)).toEqual([
      { aps: { timestamp: NOW / 1000, event: "update", "relevance-score": 1, "content-state": ahead } },
      { aps: { timestamp: NOW / 1000, event: "update", "relevance-score": 1, "content-state": ahead } },
    ]);
    expect(sent.filter((request) => request.method !== "GET" && !request.url.includes("/4/broadcasts/"))).toEqual([]);

    const ended = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 120_000);
    expect(broadcasts(ended).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual(["end", "end"]);
  });

  it("leaves alone the new channel an overlapping run opened while the old one was being retired", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const cancelled = [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })];
    stubNetwork();
    await syncLiveActivities(env, cancelled, NOW);
    stubNetwork();
    // The other run replaces the row with an open channel just before this one retires the old channel.
    const batch = env.DB.batch.bind(env.DB);
    env.DB.batch = async (statements) => {
      await env.DB.prepare("UPDATE live_channels SET channel_id = 'new-' || environment, ended_at = NULL, end_sent_at = NULL").run();
      return batch(statements);
    };

    await syncLiveActivities(env, cancelled, NOW + 60 * 60_000);

    const { results } = await env.DB.prepare("SELECT channel_id AS channelId, deleted_at AS deletedAt FROM live_channels ORDER BY environment").all();
    expect(results).toEqual([
      { channelId: "new-production", deletedAt: null },
      { channelId: "new-sandbox", deletedAt: null },
    ]);
  });

  it("replaces the ended channels of a race that can be followed again", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race()], NOW + 60_000);

    expect(sent.filter((request) => request.method === "DELETE").length).toBe(2);
    const rows = await channels(env);
    expect(rows.map(({ channelId }) => channelId)).toEqual(["channel-1", "channel-2"]);
    expect(rows.every(({ state }) => JSON.parse(state).phase === "scheduled")).toBe(true);
  });

  it("lets only a run started after the end reinstate a race", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 60_000);

    // An older run, started before the end, still holds a snapshot of the race under way.
    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 30_000);

    expect(sent.filter((request) => request.url.includes("api-manage-broadcast"))).toEqual([]);
    expect((await channels(env)).map(({ channelId }) => channelId)).toEqual(["channel-1", "channel-2"]);
  });

  it("clears the leaders of a race the calendar cancels", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW + 60_000);

    const states = broadcasts(sent).map((request) => (request.body as { aps: { "content-state": { phase: string; leaders: unknown[] } } }).aps["content-state"]);
    expect(states.map(({ phase, leaders }) => [phase, leaders])).toEqual([
      ["cancelled", []],
      ["cancelled", []],
    ]);
  });

  it("opens new channels for a race followable again once its old ones are deleted", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], NOW + 60 * 60_000);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race()], NOW + 61 * 60_000);

    expect(sent.filter((request) => request.method === "DELETE")).toEqual([]);
    expect((await channels(env)).map(({ channelId }) => channelId)).toEqual(["channel-1", "channel-2"]);
  });

  it("keeps the newer state an overlapping run stored meanwhile", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    const fetchStub = globalThis.fetch;
    // The other run publishes and stores a newer state while this one is broadcasting.
    vi.stubGlobal("fetch", async (input: string, init: RequestInit = {}) => {
      if (String(input).includes("/4/broadcasts/")) {
        await env.DB.prepare("UPDATE live_channels SET state = '{\"newer\":true}'").run();
      }
      return fetchStub(input, init);
    });

    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    expect((await channels(env)).map(({ state }) => state)).toEqual(['{"newer":true}', '{"newer":true}']);
  });

  it("deletes the channels it opened when an overlapping run opened them first", async () => {
    const env = await makeEnv();
    const sent = stubNetwork();
    const fetchStub = globalThis.fetch;
    // The other run records its channels while this one is creating its own.
    vi.stubGlobal("fetch", async (input: string, init: RequestInit = {}) => {
      if (init.method === "POST" && String(input).includes("api-manage-broadcast")) {
        const environment = String(input).includes("sandbox") ? "sandbox" : "production";
        await env.DB.prepare(
          "INSERT INTO live_channels (race_id, environment, channel_id, state, published_at, created_at) VALUES (?1, ?2, 'other', '{}', 0, 0)",
        )
          .bind(RACE_ID, environment)
          .run();
      }
      return fetchStub(input, init);
    });

    await syncLiveActivities(env, [race()], NOW);

    expect(sent.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"])).toEqual([
      "channel-1",
      "channel-2",
    ]);
    expect(await retired(env)).toEqual([]);
    expect((await channels(env)).map(({ channelId }) => channelId)).toEqual(["other", "other"]);
  });

  it("deletes a few retired channels per run, leaving the rest of the budget to the races", async () => {
    const env = await makeEnv();
    for (const id of ["a", "b", "c", "d", "e", "f"]) {
      await env.DB.prepare("INSERT INTO retired_channels (environment, channel_id) VALUES ('sandbox', ?1)").bind(id).run();
    }
    const sent = stubNetwork({ failingHost: "api-manage-broadcast" });

    await syncLiveActivities(env, [], NOW);

    expect(sent.filter((request) => request.method === "DELETE").length).toBe(4);
  });

  it("tries the retired channels in turn, so failing ones can't hold the others back", async () => {
    const env = await makeEnv();
    for (const id of ["a", "b", "c", "d", "e", "f"]) {
      await env.DB.prepare("INSERT INTO retired_channels (environment, channel_id) VALUES ('sandbox', ?1)").bind(id).run();
    }
    const deleted = (sent: Sent[]) => sent.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"]);

    const first = stubNetwork({ failingHost: "api-manage-broadcast" });
    await syncLiveActivities(env, [], NOW);
    const second = stubNetwork({ failingHost: "api-manage-broadcast" });
    await syncLiveActivities(env, [], NOW + 60_000);

    expect(new Set([...deleted(first), ...deleted(second)])).toEqual(new Set(["a", "b", "c", "d", "e", "f"]));
  });

  it("clears the leaders of a live race the calendar schedules again", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ StartTime: "2026-11-27T15:15:00Z" })], NOW + 60_000);

    const states = broadcasts(sent).map((request) => (request.body as { aps: { "content-state": { leaders: unknown[] } } }).aps["content-state"]);
    expect(states.map(({ leaders }) => leaders)).toEqual([[], []]);
  });

  it("moves the start time of a live race from the calendar while its results can't be read", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork({ resultsStatus: 503 });
    await syncLiveActivities(env, [race({ IsLive: true, StartTime: "2026-11-26T16:15:00Z" })], NOW + 60_000);

    const states = broadcasts(sent).map((request) => (request.body as { aps: { "content-state": { startTime: number } } }).aps["content-state"]);
    expect(states).toEqual([
      { ...(live.state as { startTime: number }), startTime: (live.state as { startTime: number }).startTime + 3600 },
      { ...(live.state as { startTime: number }), startTime: (live.state as { startTime: number }).startTime + 3600 },
    ]);
  });

  it("spends no more subrequests than the run has left, keeping one to delete a channel it can't record", async () => {
    const env = await makeEnv();
    const counts: number[] = [];
    for (const budget of [1, 2]) {
      const sent = stubNetwork();
      await syncLiveActivities(env, [race()], NOW, new SubrequestBudget(budget));
      counts.push(sent.length, (await channels(env)).length);
    }

    expect(counts).toEqual([0, 0, 1, 1]);
  });

  it("replaces a channel APNs no longer knows at the next run", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered" });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);

    const creations = sent.filter((request) => request.method === "POST" && request.url.includes("api-manage-broadcast"));
    expect(creations.length).toBe(2);
    const { results } = await env.DB.prepare("SELECT deleted_at AS deletedAt FROM live_channels").all();
    expect(results).toEqual([{ deletedAt: null }, { deletedAt: null }]);
  });

  it("spends the budget on the open channels before sending ends again", async () => {
    const env = await makeEnv();
    const ended = JSON.stringify(relayFinal);
    for (const environment of ["production", "sandbox"]) {
      await env.DB.prepare(
        "INSERT INTO live_channels (race_id, environment, channel_id, state, published_at, created_at, ended_at, end_sent_at) VALUES (?1, ?2, ?3, ?4, 0, 0, ?5, ?5)",
      )
        .bind(RACE_ID, environment, `ended-${environment}`, ended, NOW - 20 * 60_000)
        .run();
    }
    const followed = race({ RaceId: `${RACE_ID}B`, IsLive: true });
    await env.DB.prepare(
      "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'x', 'x', 'live', 0)",
    )
      .bind(followed.id)
      .run();
    stubNetwork();
    await syncLiveActivities(env, [followed], NOW, new SubrequestBudget(3));

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" }), followed], NOW, new SubrequestBudget(3));

    expect(broadcasts(sent).map((request) => request.url)).toEqual([
      "https://api.push.apple.com/4/broadcasts/apps/com.fouteox.biathlon",
      "https://api.sandbox.push.apple.com/4/broadcasts/apps/com.fouteox.biathlon",
    ]);
    expect(broadcasts(sent).map((request) => request.headers["apns-channel-id"])).toEqual(["channel-1", "channel-2"]);
  });

  it("sends the ends again in turns, a failing one after those not tried yet", async () => {
    const env = await makeEnv();
    for (const environment of ["production", "sandbox"]) {
      await env.DB.prepare(
        "INSERT INTO live_channels (race_id, environment, channel_id, state, published_at, created_at, ended_at, end_sent_at) VALUES (?1, ?2, ?3, ?4, 0, 0, ?5, ?5)",
      )
        .bind(RACE_ID, environment, `ended-${environment}`, JSON.stringify(relayFinal), NOW - 20 * 60_000)
        .run();
    }
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];

    const hosts: string[] = [];
    for (const run of [0, 1]) {
      const sent = stubNetwork({ failingHost: "api.push.apple.com" });
      await syncLiveActivities(env, finished, NOW + run * 60_000, new SubrequestBudget(1));
      hosts.push(...broadcasts(sent).map((request) => new URL(request.url).host));
    }

    expect(hosts).toEqual(["api.push.apple.com", "api.sandbox.push.apple.com"]);
  });

  it("drops a channel APNs no longer knows even after an overlapping run updated it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    vi.stubGlobal("fetch", async (input: string) => {
      const url = String(input);
      if (url.includes("biathlonresults.com")) return Response.json(live.results);
      // An overlapping run published a newer state first.
      await env.DB.prepare("UPDATE live_channels SET state = ?1").bind(JSON.stringify(live.state)).run();
      return Response.json({ reason: "ChannelNotRegistered" }, { status: 400 });
    });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const { results } = await env.DB.prepare("SELECT deleted_at AS deletedAt FROM live_channels").all();
    expect(results).toEqual([{ deletedAt: NOW }, { deletedAt: NOW }]);
  });

  it("clears the leaders of a dropped channel's replacement when the race is scheduled again", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", results: relay.results });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);

    stubNetwork();
    await syncLiveActivities(env, [race()], NOW + 2 * 60_000);

    expect((await channels(env)).map(({ state }) => JSON.parse(state).leaders)).toEqual([[], []]);
  });

  it("ends the activity with its final state even when APNs rejects the end, sent again at the next run", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];
    stubNetwork({ results: relay.results, broadcastReason: "BadPayload" });
    await syncLiveActivities(env, finished, NOW);

    const { results } = await env.DB.prepare("SELECT ended_at AS endedAt, end_sent_at AS endSentAt FROM live_channels").all();
    expect(results).toEqual([
      { endedAt: NOW, endSentAt: null },
      { endedAt: NOW, endSentAt: null },
    ]);
    const sent = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, finished, NOW + 60_000);
    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual(["end", "end"]);
  });

  it("deletes a channel at APNs when it can't record it", async () => {
    const env = await makeEnv();
    const prepare = env.DB.prepare.bind(env.DB);
    env.DB.prepare = (sql: string) => {
      if (sql.startsWith("INSERT INTO live_channels")) throw new Error("D1 unavailable");
      return prepare(sql);
    };
    const sent = stubNetwork();

    await expect(syncLiveActivities(env, [race()], NOW)).rejects.toThrow("D1 unavailable");

    expect(sent.filter((request) => request.method === "DELETE").map((request) => request.headers["apns-channel-id"])).toEqual([
      "channel-1",
    ]);
  });

  it("sends no end once an overlapping run stored a newer state, like a race reinstated", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const sent: string[] = [];
    vi.stubGlobal("fetch", async (input: string) => {
      const url = String(input);
      sent.push(url);
      if (!url.includes("biathlonresults.com")) return new Response(null, { status: 200 });
      await env.DB.prepare("UPDATE live_channels SET state = ?1").bind(JSON.stringify(live.state)).run();
      return Response.json(relay.results);
    });

    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    expect(sent.filter((url) => url.includes("/4/broadcasts/"))).toEqual([]);
    const { results } = await env.DB.prepare("SELECT ended_at AS endedAt FROM live_channels").all();
    expect(results).toEqual([{ endedAt: null }, { endedAt: null }]);
  });

  it("queues a channel it can't record for deletion when deleting it at once fails too", async () => {
    const env = await makeEnv();
    const prepare = env.DB.prepare.bind(env.DB);
    env.DB.prepare = (sql: string) => {
      if (sql.startsWith("INSERT INTO live_channels")) throw new Error("D1 unavailable");
      return prepare(sql);
    };
    vi.stubGlobal("fetch", async (_input: string, init: RequestInit = {}) =>
      init.method === "POST"
        ? new Response(null, { status: 201, headers: { "apns-channel-id": "channel-1" } })
        : new Response(null, { status: 500 }),
    );

    await expect(syncLiveActivities(env, [race()], NOW)).rejects.toThrow("D1 unavailable");

    expect(await retired(env)).toEqual(["channel-1"]);
  });

  it("updates the races followed before opening channels for new ones", async () => {
    const env = await makeEnv();
    const upcoming = race({ RaceId: `${RACE_ID}B` });
    await env.DB.prepare(
      "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'x', 'x', 'scheduled', 0)",
    )
      .bind(upcoming.id)
      .run();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true }), upcoming], NOW, new SubrequestBudget(3));

    expect(broadcasts(sent).length).toBe(2);
    expect(sent.filter((request) => request.url.includes("api-manage-broadcast"))).toEqual([]);
  });

  it("signs a new provider token when APNs rejects one, even with no subrequest left to retry", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const later = NOW + 30 * 60_000;

    const outcome = await new ProviderTokens(env, later, new SubrequestBudget(1)).send("sandbox", async () => ({
      kind: "expiredProviderToken",
    }));

    expect(outcome).toEqual({ kind: "deferred" });
    const cached = await env.DB.prepare("SELECT updated_at AS updatedAt FROM settings WHERE key = 'apns_token_sandbox'").first();
    expect(cached).toEqual({ updatedAt: later });
  });

  it("keeps the activity of a race the calendar stops listing until the system has ended it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const events = (sent: Sent[]) => broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event);

    const meanwhile = stubNetwork();
    await syncLiveActivities(env, [], NOW);
    const later = stubNetwork();
    await syncLiveActivities(env, [], Date.parse("2026-11-27T03:16:00Z"));

    expect([events(meanwhile), events(later)]).toEqual([[], ["end", "end"]]);
  });

  it("keeps a race's lookup for a run that can broadcast its result", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    for (const run of [1, 2]) {
      const sent = stubNetwork();
      await syncLiveActivities(env, [race({ IsLive: true })], NOW + run * 60_000, new SubrequestBudget(2));
      expect(sent).toEqual([]);
    }
    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 3 * 60_000, new SubrequestBudget(3));
    expect(broadcasts(sent).length).toBe(2);
  });

  it("keeps in a dropped channel's replacement the leaders looked up when APNs dropped it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", results: relay.results });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);

    stubNetwork({ resultsStatus: 503 });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 2 * 60_000);

    const ahead = { ...relayFinal, phase: "live" };
    expect((await channels(env)).map(({ state }) => JSON.parse(state))).toEqual([ahead, ahead]);
  });

  it("seeds a dropped channel's replacement with the leaders the same run looked up", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", results: live.results });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    stubNetwork({ results: relay.results });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);

    const ahead = { ...relayFinal, phase: "live" };
    expect((await channels(env)).map(({ state }) => JSON.parse(state))).toEqual([ahead, ahead]);
  });

  it("keeps the newer state an overlapping run recorded on a dropped channel, retiring its own replacement", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered", results: live.results });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const newer = JSON.stringify({ ...relayFinal, phase: "live" });
    const sent = stubNetwork({ resultsStatus: 503 });
    const fetch = globalThis.fetch;
    vi.stubGlobal("fetch", async (input: string, init: RequestInit = {}) => {
      // An overlapping run records newer leaders while this one creates the replacements.
      if (String(input).includes("api-manage-broadcast") && init.method === "POST") {
        await env.DB.prepare("UPDATE live_channels SET state = ?1").bind(newer).run();
      }
      return fetch(input, init);
    });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 60_000);

    expect((await channels(env)).map(({ state }) => state)).toEqual([newer, newer]);
    // Both replacements were created, then deleted at APNs in the same run.
    const managed = sent.filter((request) => request.url.includes("api-manage-broadcast"));
    expect(managed.map((request) => request.method)).toEqual(["POST", "POST", "DELETE", "DELETE"]);
  });

  it("takes turns among the races under way when the budget can't cover them all", async () => {
    const env = await makeEnv();
    const races = ["A", "B"].map((suffix) => race({ RaceId: RACE_ID + suffix, IsLive: true }));
    for (const { id } of races) {
      await env.DB.prepare(
        "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'x', 'x', 'live', 0)",
      )
        .bind(id)
        .run();
    }
    stubNetwork();
    await syncLiveActivities(env, races, NOW);

    const lookups: string[] = [];
    for (const run of [1, 2]) {
      const sent = stubNetwork();
      await syncLiveActivities(env, races, NOW + run * 60_000, new SubrequestBudget(3));
      lookups.push(...sent.filter((request) => request.url.includes("biathlonresults.com")).map((request) => request.url));
    }

    expect(lookups.map((url) => new URL(url).searchParams.get("RaceId"))).toEqual(races.map(({ id }) => id));
  });

  it("opens a few channels per run, to stay within the subrequest limit", async () => {
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

    await syncLiveActivities(env, races, NOW);

    expect(sent.filter((request) => request.url.includes("api-manage-broadcast")).length).toBe(4);
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
    for (const run of [0, 1, 2]) await syncLiveActivities(env, races, NOW + run * 60_000);

    expect((await channels(env)).map(({ environment }) => environment)).toEqual(Array(5).fill("sandbox"));
  });

  it("sends the end again while the calendar can't be read, without ending followed races", async () => {
    const env = await makeEnv();
    stubNetwork();
    const followed = race({ RaceId: `${RACE_ID}B` });
    await env.DB.prepare(
      "INSERT INTO races (id, category, name, start_time, status, updated_at) VALUES (?1, 'SM', 'x', 'x', 'scheduled', 0)",
    )
      .bind(followed.id)
      .run();
    await syncLiveActivities(env, [race(), followed], NOW);
    stubNetwork({ results: relay.results });
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" }), followed], NOW);

    const sent = stubNetwork();
    await syncLiveActivities(env, undefined, NOW + 10 * 60_000);

    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual(["end", "end"]);
    expect(sent.filter((request) => request.url.includes("api-manage-broadcast"))).toEqual([]);
    expect((await channels(env)).length).toBe(4);
  });
});

describe("GET /v1/races/:id/channels/:environment", () => {
  const get = (env: Env, path: string) =>
    worker.fetch(new Request(`https://server.test${path}`), env, {} as ExecutionContext);

  it("gives the app the race's channel for its APNs environment, with its current state and the broadcast's timestamp", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const sent = stubNetwork();
    await syncLiveActivities(env, [race({ IsLive: true })], NOW + 90_000);

    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(response.status).toBe(200);
    const { aps } = broadcasts(sent)[0]?.body as { aps: { timestamp: number } };
    expect(await response.json()).toEqual({ channelId: "channel-2", state: live.state, timestamp: aps.timestamp });
  });

  it("dates the state a channel opens with from its opening, older than any broadcast on it", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW + 1_500);

    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(await response.json()).toMatchObject({ timestamp: Math.floor((NOW + 1_500) / 1000) });
  });

  it("keeps its answers out of HTTP caches, since the channel can change at every run", async () => {
    const env = await makeEnv();
    for (const status of [404, 200]) {
      const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
      expect([response.status, response.headers.get("cache-control")]).toEqual([status, "no-store"]);
      stubNetwork();
      await syncLiveActivities(env, [race()], NOW);
    }
  });

  it("answers 410 with the final state once the race's activity has ended, even after its channel is deleted", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];
    stubNetwork({ results: relay.results });
    await syncLiveActivities(env, finished, NOW);

    for (const now of [NOW, NOW + 60 * 60_000]) {
      stubNetwork();
      await syncLiveActivities(env, finished, now);
      const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
      expect(response.status).toBe(410);
      expect(await response.json()).toEqual({ state: relayFinal });
    }
  });

  it("answers 410 with the final state when APNs no longer knew the channel at the end", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    const finished = [race({ StatusId: 11, ScheduleStatus: "FINISHED" })];
    stubNetwork({ results: relay.results, broadcastReason: "ChannelNotRegistered" });
    await syncLiveActivities(env, finished, NOW);

    const later = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, finished, NOW + 60 * 60_000);
    expect(later.filter((request) => !request.url.includes("biathlonresults.com"))).toEqual([]);
    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(response.status).toBe(410);
    expect(await response.json()).toEqual({ state: relayFinal });
  });

  it("answers 404 for a channel APNs no longer knows, until it is replaced", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered" });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    expect((await get(env, `/v1/races/${RACE_ID}/channels/sandbox`)).status).toBe(404);
  });

  it("answers 410 with the final state when a race ends before its dropped channel is replaced", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);
    stubNetwork({ broadcastReason: "ChannelNotRegistered" });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    const sent = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW + 60_000);

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
  it("leave the alerts the run has no subrequests left for to the next run", async () => {
    const env = await makeEnv();
    for (const token of ["a", "b"]) {
      await env.DB.prepare(
        "INSERT INTO outbox (token, environment, kind, race_id, race_name, start_time, locale, time_zone, created_at) VALUES (?1, 'sandbox', 'cancelled', ?2, 'x', '2026-11-26T15:15:00.000Z', 'en', 'UTC', ?3)",
      )
        .bind(token, RACE_ID, NOW)
        .run();
    }
    const sent = stubNetwork();

    await drainOutbox(env, NOW, new SubrequestBudget(1));

    expect(sent.length).toBe(1);
    const { results } = await env.DB.prepare("SELECT token, attempts FROM outbox").all();
    expect(results).toEqual([{ token: "b", attempts: 0 }]);
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
    const registration = parseStartRegistration(token, { environment: "production", athletes: [], nations: [], ...body });
    if (typeof registration === "string") throw new Error(registration);
    await saveStartToken(env.DB, registration, key, 0);
  }

  /** A race with its channels, and tokens: Perrot's fan, an Italy fan who has nobody racing, and a sandbox France fan. */
  async function setUp() {
    const env = await makeEnv();
    stub();
    await syncLiveActivities(env, [race()], DUE - 60 * 60_000);
    await save(env, "aa".repeat(32), { athletes: [PERROT] });
    await save(env, "bb".repeat(32), { nations: ["ITA"] });
    await save(env, "cc".repeat(32), { environment: "sandbox", nations: ["FRA"] });
    return env;
  }

  const starts = (sent: Sent[]) => sent.filter((request) => request.url.includes("/3/device/"));
  const ibu = (sent: Sent[]) => sent.filter((request) => request.url.includes("biathlonresults.com"));

  it("starts the race's activity on its channel for the devices whose favorites are on the start list, 30 minutes before", async () => {
    const env = await setUp();
    const sent = stub();
    await startFavoriteActivities(env, [race()], DUE - 60_000);
    expect(sent).toEqual([]);

    await startFavoriteActivities(env, [race()], DUE);
    expect(ibu(sent).map((request) => request.url)).toEqual([
      `https://biathlonresults.com/modules/sportapi/api/Results?RaceId=${RACE_ID}`,
    ]);
    const [production, sandbox] = await channels(env);
    expect(starts(sent).map((request) => request.url)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
    // Apple: push type liveactivity, its own topic, an alert, and iOS 18's input-push-channel.
    expect(starts(sent)[0]?.headers).toMatchObject({
      "apns-push-type": "liveactivity",
      "apns-topic": "com.fouteox.biathlon.push-type.liveactivity",
      "apns-priority": "10",
      // Kept by APNs until a while after the race starts, for a device offline meanwhile.
      "apns-expiration": String(START / 1000 + 15 * 60),
    });
    expect(starts(sent)[0]?.body).toEqual({
      aps: {
        timestamp: DUE / 1000,
        event: "start",
        "relevance-score": 0.5,
        "content-state": JSON.parse(production!.state),
        "attributes-type": "RaceActivityAttributes",
        attributes: { raceID: RACE_ID, name: "Men's 20km Individual", channelID: production!.channelId },
        "input-push-channel": production!.channelId,
        alert: {
          title: { "loc-key": "push.liveActivity.title" },
          body: { "loc-key": "push.liveActivity.body", "loc-args": ["Men's 20km Individual"] },
          sound: "default",
        },
      },
    });
    expect((starts(sent)[1]?.body as { aps: { "input-push-channel": string } }).aps["input-push-channel"]).toBe(sandbox!.channelId);

    // Each device is checked once per race.
    const later = stub();
    await startFavoriteActivities(env, [race({ IsLive: true })], DUE + 20 * 60_000);
    expect(later).toEqual([]);
  });

  it("checks the race again for a device whose favorites changed, but never starts it twice", async () => {
    const env = await setUp();
    stub();
    await startFavoriteActivities(env, [race()], DUE);

    await save(env, "aa".repeat(32), { athletes: [PERROT], nations: ["SWE"] });
    await save(env, "bb".repeat(32), { nations: ["FRA"] });
    const sent = stub();
    await startFavoriteActivities(env, [race()], DUE + 60_000);
    expect(starts(sent).map((request) => request.url)).toEqual([`https://api.push.apple.com/3/device/${"bb".repeat(32)}`]);
  });

  it("checks again only for changed favorites, and keeps an install's starts when its token changes", async () => {
    const env = await setUp();
    stub();
    await startFavoriteActivities(env, [race()], DUE);

    // The app sends its favorites at every launch, and ActivityKit can replace the token.
    await save(env, "bb".repeat(32), { nations: ["ITA"] });
    await save(env, "dd".repeat(32), { athletes: [PERROT] }, `${KEY}-${"aa".repeat(32)}`);
    const sent = stub();
    await startFavoriteActivities(env, [race()], DUE + 60_000);
    expect(starts(sent)).toEqual([]);
  });

  it("matches the favorites a device saved while the start list was read", async () => {
    const env = await setUp();
    const sent = stub({ duringResults: () => save(env, "bb".repeat(32), { nations: ["FRA"] }) });
    await startFavoriteActivities(env, [race()], DUE);
    expect(starts(sent).map((request) => request.url)).toContain(`https://api.push.apple.com/3/device/${"bb".repeat(32)}`);
  });

  it("starts nothing for a device whose favorites changed or that opted out while the start list was read", async () => {
    const env = await setUp();
    const sent = stub({
      duringResults: async () => {
        await save(env, "aa".repeat(32), { athletes: ["BTSUI00000000009"] });
        await env.DB.prepare("DELETE FROM live_start_tokens WHERE environment = 'sandbox'").run();
      },
    });
    await startFavoriteActivities(env, [race()], DUE);
    expect(starts(sent)).toEqual([]);
  });

  it("checks again the devices none of whose favorites raced when the start list changes before the race", async () => {
    const env = await setUp();
    stub();
    await startFavoriteActivities(env, [race()], DUE);

    // An Italian added to the start list.
    const entrant = { IBUId: "BTITA00000000006", Name: "GIACOMEL Tommaso", Nat: "ITA" };
    const amended = { ...START_LIST, Results: [...(START_LIST.Results ?? []), entrant] };
    const sent = stub({ results: amended });
    await startFavoriteActivities(env, [race()], DUE + 60_000);
    expect(starts(sent).map((request) => request.url)).toEqual([`https://api.push.apple.com/3/device/${"bb".repeat(32)}`]);
  });

  it("starts nothing on a channel that ended while the start list was read", async () => {
    const env = await setUp();
    const sent = stub({
      duringResults: async () => {
        await env.DB.prepare("UPDATE live_channels SET ended_at = 1").run();
      },
    });
    await startFavoriteActivities(env, [race()], DUE);
    expect(starts(sent)).toEqual([]);
  });

  it("starts the activity again on the channel that replaces a dropped one", async () => {
    const env = await setUp();
    stub();
    await startFavoriteActivities(env, [race()], DUE);

    // The activities on the dropped channel get none of its replacement's broadcasts.
    await env.DB.prepare("UPDATE live_channels SET channel_id = 'replacement' WHERE environment = 'production'").run();
    const sent = stub();
    await startFavoriteActivities(env, [race()], DUE + 60_000);
    expect(starts(sent).map((request) => request.url)).toEqual([`https://api.push.apple.com/3/device/${"aa".repeat(32)}`]);
    expect((starts(sent)[0]?.body as { aps: { "input-push-channel": string } }).aps["input-push-channel"]).toBe("replacement");
  });

  it("forgets the favorites no launch of the app sent again for a year", async () => {
    const env = await setUp();
    await env.DB.prepare("UPDATE live_start_tokens SET updated_at = ?1 WHERE token <> ?2").bind(START, "aa".repeat(32)).run();
    await pruneStarts(env.DB, START + 365 * 24 * 60 * 60_000);
    const { results } = await env.DB.prepare("SELECT token FROM live_start_tokens ORDER BY token").all<{ token: string }>();
    expect(results.map(({ token }) => token)).toEqual(["bb".repeat(32), "cc".repeat(32)]);
  });

  it("forgets the checks of races two days after their start", async () => {
    const env = await setUp();
    stub();
    await startFavoriteActivities(env, [race()], DUE);
    const checks = async () => (await env.DB.prepare("SELECT COUNT(*) AS n FROM live_starts").first<{ n: number }>())!.n;
    await pruneStarts(env.DB, START + 47 * 60 * 60_000);
    expect(await checks()).toBe(3);
    await pruneStarts(env.DB, START + 49 * 60 * 60_000);
    expect(await checks()).toBe(0);
  });

  it("sends each start once when cron runs overlap", async () => {
    const env = await setUp();
    const sent = stub();
    await Promise.all([startFavoriteActivities(env, [race()], DUE), startFavoriteActivities(env, [race()], DUE)]);
    expect(starts(sent).map((request) => request.url).sort()).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("starts the activity again when a race is reinstated after its end", async () => {
    const env = await setUp();
    stub();
    await startFavoriteActivities(env, [race()], DUE);
    await syncLiveActivities(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], DUE + 60_000);

    const sent = stub({ channelPrefix: "reinstated" });
    await syncLiveActivities(env, [race()], DUE + 2 * 60_000);
    await startFavoriteActivities(env, [race()], DUE + 2 * 60_000);
    const [production] = await channels(env);
    expect(starts(sent).map((request) => (request.body as { aps: { "input-push-channel": string } }).aps["input-push-channel"])).toEqual([
      production!.channelId,
      expect.any(String),
    ]);
  });

  it("waits for the start list, and for an open channel", async () => {
    const env = await setUp();
    await env.DB.prepare("UPDATE live_channels SET deleted_at = 1 WHERE environment = 'sandbox'").run();
    const empty = stub({ results: { ...START_LIST, Results: [] } });
    await startFavoriteActivities(env, [race()], DUE);
    expect(starts(empty)).toEqual([]);

    const sent = stub();
    await startFavoriteActivities(env, [race()], DUE + 60_000);
    expect(starts(sent).map((request) => request.url)).toEqual([`https://api.push.apple.com/3/device/${"aa".repeat(32)}`]);
  });

  it("starts nothing for a race that is over, and leaves the rest to the next run when the budget runs out", async () => {
    const env = await setUp();
    const sent = stub();
    await startFavoriteActivities(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], DUE);
    expect(sent).toEqual([]);

    await startFavoriteActivities(env, [race()], DUE, new SubrequestBudget(2));
    expect(starts(sent).length).toBe(1);
    await startFavoriteActivities(env, [race()], DUE + 60_000);
    expect(starts(sent).map((request) => request.url)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("waits for the published start list before a scheduled race, and takes the results of a live one", async () => {
    const env = await setUp();
    // Rows the API returns before it marks them as the start list.
    const preliminary = stub({ results: { ...START_LIST, IsStartList: false } });
    await startFavoriteActivities(env, [race()], DUE);
    expect(starts(preliminary)).toEqual([]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM live_starts").first<{ n: number }>()).toEqual({ n: 0 });

    const sent = stubNetwork();
    await startFavoriteActivities(env, [race({ IsLive: true })], START + 60_000);
    expect(starts(sent).map((request) => request.url)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("keeps the start of a reinstated race when an older run's push to the ended channel fails", async () => {
    const env = await setUp();
    let reinstating = false;
    stub({
      channelPrefix: "reinstated",
      duringDevice: async () => {
        if (reinstating) return undefined;
        reinstating = true;
        // Meanwhile, the race ends and is reinstated, and a newer run starts it on the new channels.
        await syncLiveActivities(env, [race({ StatusId: 6, ScheduleStatus: "CANCELLED" })], DUE + 60_000);
        await syncLiveActivities(env, [race()], DUE + 2 * 60_000);
        await startFavoriteActivities(env, [race()], DUE + 2 * 60_000);
        return 503;
      },
    });
    await startFavoriteActivities(env, [race()], DUE);

    const sent = stub();
    await startFavoriteActivities(env, [race()], DUE + 3 * 60_000);
    expect(starts(sent)).toEqual([]);
  });

  it("retries a start when APNs rejects the provider token", async () => {
    const env = await setUp();
    stub({ deviceStatus: 403, deviceReason: "ExpiredProviderToken" });
    await startFavoriteActivities(env, [race()], DUE);

    const sent = stub();
    await startFavoriteActivities(env, [race()], DUE + 60_000);
    expect(starts(sent).map((request) => request.url)).toEqual([
      `https://api.push.apple.com/3/device/${"aa".repeat(32)}`,
      `https://api.sandbox.push.apple.com/3/device/${"cc".repeat(32)}`,
    ]);
  });

  it("forgets a token APNs no longer knows, and doesn't retry a start APNs refused", async () => {
    const env = await setUp();
    stub({ deviceStatus: 410 });
    await startFavoriteActivities(env, [race()], DUE);
    const { results } = await env.DB.prepare("SELECT token FROM live_start_tokens ORDER BY token").all<{ token: string }>();
    expect(results.map(({ token }) => token)).toEqual(["bb".repeat(32)]);

    const other = await setUp();
    stub({ deviceStatus: 400 });
    await startFavoriteActivities(other, [race()], DUE);
    const sent = stub();
    await startFavoriteActivities(other, [race()], DUE + 60_000);
    expect(starts(sent)).toEqual([]);
  });
});
