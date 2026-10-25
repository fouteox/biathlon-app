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

async function get(path: string): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(new Request(`https://server.test${path}`), env, ctx);
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

    const response = await get("/ibu/Athletes?Name=x");

    expect(response.status).toBe(404);
    await response.text();
    expect(requested).toEqual([]);
  });
});
