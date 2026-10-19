import { readFileSync } from "node:fs";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { snapshot, type IBUCompetition, type RaceSnapshot } from "../src/ibu";
import { liveState, syncLiveActivities, type IBUResults } from "../src/live";
import { makeD1 } from "./d1";

// Shared with the app's BiathlonKit tests: the app decodes this `content-state` with
// ActivityKit's default strategies, so both sides must build the same state.
const cases: { name: string; results: IBUResults; state: unknown }[] = JSON.parse(
  readFileSync(
    new URL("../../Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures/live-activity.json", import.meta.url),
    "utf8",
  ),
);

describe("Live Activity state shared with the app", () => {
  for (const { name, results, state } of cases) {
    it(name, () => {
      expect(liveState(results) ?? null).toEqual(state);
    });
  }
});

const [live, relay] = cases as [(typeof cases)[number], (typeof cases)[number]];
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
function stubNetwork(options: { results?: unknown; broadcastReason?: string } = {}): Sent[] {
  const sent: Sent[] = [];
  let channels = 0;
  vi.stubGlobal("fetch", async (input: string, init: RequestInit = {}) => {
    const url = String(input);
    const headers = Object.fromEntries(new Headers(init.headers).entries());
    sent.push({ method: init.method ?? "GET", url, headers, body: init.body ? JSON.parse(String(init.body)) : undefined });
    if (url.includes("biathlonresults.com")) return Response.json(options.results ?? live.results);
    if (url.includes("api-manage-broadcast") && init.method === "POST") {
      channels += 1;
      return new Response(null, { status: 201, headers: { "apns-channel-id": `channel-${channels}` } });
    }
    if (url.includes("api-manage-broadcast") && init.method === "DELETE") return new Response(null, { status: 204 });
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
      aps: { timestamp: NOW / 1000, event: "update", "content-state": live.state },
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

  it("ends the activity with the final results, then deletes the channels", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    const sent = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, [race({ StatusId: 11, ScheduleStatus: "FINISHED" })], NOW);

    expect(broadcasts(sent).map((request) => request.body)).toEqual([
      { aps: { timestamp: NOW / 1000, event: "end", "content-state": relay.state } },
      { aps: { timestamp: NOW / 1000, event: "end", "content-state": relay.state } },
    ]);
    const deletions = sent.filter((request) => request.method === "DELETE");
    expect(deletions.map((request) => request.headers["apns-channel-id"])).toEqual(["channel-1", "channel-2"]);
    expect(await channels(env)).toEqual([]);
  });

  it("ends the channels of races no longer watched", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    const sent = stubNetwork({ results: relay.results });
    await syncLiveActivities(env, [], NOW);

    expect(broadcasts(sent).map((request) => (request.body as { aps: { event: string } }).aps.event)).toEqual(["end", "end"]);
    expect(await channels(env)).toEqual([]);
  });

  it("forgets a channel APNs no longer knows, to open a new one", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    stubNetwork({ broadcastReason: "ChannelNotRegistered" });
    await syncLiveActivities(env, [race({ IsLive: true })], NOW);

    expect(await channels(env)).toEqual([]);
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
});

describe("GET /v1/races/:id/channels/:environment", () => {
  const get = (env: Env, path: string) =>
    worker.fetch(new Request(`https://server.test${path}`), env, {} as ExecutionContext);

  it("gives the app the race's channel for its APNs environment", async () => {
    const env = await makeEnv();
    stubNetwork();
    await syncLiveActivities(env, [race()], NOW);

    const response = await get(env, `/v1/races/${RACE_ID}/channels/sandbox`);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ channelId: "channel-2" });
  });

  it("answers 404 for a race without a channel and 400 for an unknown environment", async () => {
    const env = await makeEnv();
    expect((await get(env, `/v1/races/${RACE_ID}/channels/production`)).status).toBe(404);
    expect((await get(env, `/v1/races/${RACE_ID}/channels/staging`)).status).toBe(400);
  });
});
