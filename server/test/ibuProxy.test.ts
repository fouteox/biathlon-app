import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vite-plus/test";
import worker from "../src/index";
import { answer } from "./network";

/** Answers like the IBU API, with `status`, and records the URL of every request. */
function stubIBU(status = 200): string[] {
  const requested: string[] = [];
  answer(({ url }) => {
    requested.push(url);
    return Response.json([{ RaceId: "BT2627SWRLCP01SMIN" }], { status });
  });
  return requested;
}

async function get(path: string, ip = "192.0.2.1"): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(
    new Request(`https://server.test${path}`, { headers: { "cf-connecting-ip": ip } }),
    env,
    ctx,
  );
  // The cache is filled once the response is sent.
  await waitOnExecutionContext(ctx);
  return response;
}

describe("GET /ibu/*", () => {
  it("serves the IBU API's answers from the Cache API for the endpoint's lifetime", async () => {
    const requested = stubIBU();

    for (const _ of [1, 2]) {
      const response = await get("/ibu/Results?RaceId=BT2627SWRLCP01SMIN");
      expect(response.headers.get("cache-control")).toBe("public, max-age=15");
      expect(await response.json()).toEqual([{ RaceId: "BT2627SWRLCP01SMIN" }]);
    }

    expect(requested).toEqual(["https://biathlonresults.com/modules/sportapi/api/Results?RaceId=BT2627SWRLCP01SMIN"]);
  });

  it.each([
    ["the athlete search", "Athletes?FamilyName=simon", 3600],
    ["a race's analysis", "AnalyticResults?RaceId=BT2526SWRLCP01SMSP&TypeId=CRST", 60],
  ])("serves %s from its cache", async (_, path, seconds) => {
    const requested = stubIBU();

    for (const _ of [1, 2]) {
      const response = await get(`/ibu/${path}`);
      expect(response.headers.get("cache-control")).toBe(`public, max-age=${seconds}`);
      await response.json();
    }

    expect(requested).toEqual([`https://biathlonresults.com/modules/sportapi/api/${path}`]);
  });

  it("passes the IBU API's errors on without caching them", async () => {
    const requested = stubIBU(503);

    for (const _ of [1, 2]) {
      const response = await get("/ibu/Competitions?EventId=BT2627SWRLCP01");
      expect(response.status).toBe(503);
      await response.arrayBuffer();
    }

    expect(requested.length).toBe(2);
  });

  it("answers 404 for an endpoint the app doesn't call, without asking the IBU API", async () => {
    const requested = stubIBU();

    const response = await get("/ibu/MedalResults?SeasonId=2627");

    expect(response.status).toBe(404);
    await response.text();
    expect(requested).toEqual([]);
  });

  it("answers 429 to an IP address past 60 requests a minute the cache can't answer", { timeout: 20_000 }, async () => {
    // The local limiter counts in one-minute windows aligned to the clock (Miniflare's
    // ratelimit-object.worker.js): requests that straddle two windows would never reach 61.
    const left = 60_000 - (Date.now() % 60_000);
    if (left < 10_000) await new Promise((resolve) => setTimeout(resolve, left));
    const requested = stubIBU();
    for (let race = 1; race <= 60; race += 1) {
      expect((await get(`/ibu/Results?RaceId=${race}`)).status).toBe(200);
    }

    const limited = await get("/ibu/Results?RaceId=61");

    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBe("60");
    await limited.text();
    expect(requested.length).toBe(60);
    // The cache still answers that address, and other addresses still reach the IBU API.
    expect((await get("/ibu/Results?RaceId=1")).status).toBe(200);
    expect((await get("/ibu/Results?RaceId=61", "192.0.2.2")).status).toBe(200);
  });
});
