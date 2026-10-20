import { isEnvironment, probe } from "./apns";
import { deleteOwnedDevice, isDeviceToken, ownsDevice, parseRegistration, saveDevice, type DeviceRegistration } from "./devices";
import {
  deleteOwnedStartToken,
  ownsStartToken,
  parseStartRegistration,
  pruneStarts,
  saveStartToken,
  type StartRegistration,
} from "./liveStarts";
import { IBU_BASE_URL } from "./ibu";
import { isPurpose, issueChallenge } from "./challenges";
import { authorize, pruneKeys, registerKey } from "./keys";
import { channelFor } from "./live";
import { runCron } from "./watcher";

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    for (const [pattern, register] of TOKEN_ROUTES) {
      const match = url.pathname.match(pattern);
      if (match) return register(request, env, decodeURIComponent(match[1] ?? "").toLowerCase());
    }

    if (url.pathname === "/v1/app-attest/challenges" && request.method === "POST") {
      const purpose = url.searchParams.get("purpose");
      if (!isPurpose(purpose)) return json({ error: "purpose must be attest or assert" }, 400);
      return json({ challenge: await issueChallenge(env.APP_ATTEST_SECRET, purpose, Date.now()) }, 201);
    }

    if (url.pathname === "/v1/app-attest/keys" && request.method === "POST") {
      const failure = await registerKey(env, await request.json().catch(() => undefined), Date.now());
      return failure ? json({ error: failure.error }, failure.status) : new Response(null, { status: 204 });
    }

    const channel = url.pathname.match(/^\/v1\/races\/([^/]+)\/channels\/([^/]+)$/);
    if (channel && request.method === "GET") {
      const [, raceId = "", environment = ""] = channel.map(decodeURIComponent);
      if (!isEnvironment(environment)) return json({ error: "invalid environment" }, 400);
      // The channel can change at every cron run: no cache may answer for it, 404 and 410 included.
      const live = await channelFor(env.DB, raceId, environment);
      if (!live) return json({ error: "no channel for this race" }, 404, NO_STORE);
      return "ended" in live ? json({ state: live.ended }, 410, NO_STORE) : json(live, 200, NO_STORE);
    }

    if (url.pathname === "/v1/health" && request.method === "GET") {
      return json({ apns: await probe("sandbox", env.APNS_TOPIC) });
    }

    if (url.pathname.startsWith("/ibu/") && request.method === "GET") {
      return proxyIBU(url, ctx);
    }

    return new Response("Not found", { status: 404 });
  },

  async scheduled(controller, env, ctx): Promise<void> {
    try {
      await runCron(env, controller.scheduledTime);
    } finally {
      // Once a day is enough, and keeps these table scans off every run.
      const time = new Date(controller.scheduledTime);
      if (time.getUTCHours() === 3 && time.getUTCMinutes() === 0) {
        await pruneStarts(env.DB, controller.scheduledTime);
        await pruneKeys(env.DB, controller.scheduledTime);
      }
    }
  },
} satisfies ExportedHandler<Env>;

/** A token the app registers with a signed `PUT` and unregisters with a signed `DELETE`, owned by the key that registered it. */
interface TokenStore<Registration> {
  parse(token: string, body: unknown): Registration | string;
  owns(db: D1Database, token: string, keyId: string): Promise<boolean>;
  save(db: D1Database, registration: Registration, keyId: string, now: number): Promise<void>;
  delete(db: D1Database, token: string, keyId: string): Promise<void>;
}

const DEVICES: TokenStore<DeviceRegistration> = {
  parse: parseRegistration,
  owns: ownsDevice,
  save: saveDevice,
  delete: deleteOwnedDevice,
};

const LIVE_ACTIVITY_STARTS: TokenStore<StartRegistration> = {
  parse: parseStartRegistration,
  owns: ownsStartToken,
  save: saveStartToken,
  delete: deleteOwnedStartToken,
};

const TOKEN_ROUTES: [RegExp, (request: Request, env: Env, token: string) => Promise<Response>][] = [
  [/^\/v1\/devices\/([^/]+)$/, (request, env, token) => registerToken(request, env, token, DEVICES)],
  [/^\/v1\/live-activity-starts\/([^/]+)$/, (request, env, token) => registerToken(request, env, token, LIVE_ACTIVITY_STARTS)],
];

async function registerToken<Registration>(request: Request, env: Env, token: string, store: TokenStore<Registration>) {
  if (request.method !== "PUT" && request.method !== "DELETE") return new Response(null, { status: 405 });
  // Read once: the assertion signs these exact bytes.
  const body = new Uint8Array(await request.arrayBuffer());
  const registration = request.method === "PUT" ? store.parse(token, parseJSON(body)) : undefined;
  if (typeof registration === "string") return json({ error: registration }, 400);
  if (!isDeviceToken(token)) return json({ error: "invalid token" }, 400);
  const auth = await authorize(env, request, body, Date.now());
  if ("error" in auth) return json({ error: auth.error }, auth.status);
  if (!(await store.owns(env.DB, token, auth.keyId))) return json({ error: "token registered by another key" }, 403);
  if (registration !== undefined) await store.save(env.DB, registration, auth.keyId, Date.now());
  else await store.delete(env.DB, token, auth.keyId);
  return new Response(null, { status: 204 });
}

/**
 * Read-only cache in front of biathlonresults.com, with the same paths and
 * query strings (`/ibu/Results?RaceId=…`), for the endpoints the app calls.
 * Measured on 2026-10-19: the Cache API works on `*.workers.dev` too
 * (`cf-cache-status: HIT` on the second request).
 */
const CACHE_SECONDS: Record<string, number> = {
  Results: 15,
  Competitions: 60,
  CupResults: 300,
  Events: 3600,
  CISBios: 3600,
  AllResults: 3600,
};

async function proxyIBU(url: URL, ctx: ExecutionContext): Promise<Response> {
  const path = url.pathname.slice("/ibu/".length);
  const ttl = CACHE_SECONDS[path];
  if (ttl === undefined) return new Response("Not found", { status: 404 });

  const cache = caches.default;
  const cacheKey = new Request(url.toString());
  const hit = await cache.match(cacheKey);
  if (hit) return hit;

  const upstream = await fetch(new URL(path + url.search, IBU_BASE_URL));
  if (!upstream.ok) return new Response(upstream.body, { status: upstream.status });
  const response = new Response(upstream.body, {
    headers: {
      "content-type": upstream.headers.get("content-type") ?? "application/json",
      "cache-control": `public, max-age=${ttl}`,
    },
  });
  ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}

function parseJSON(bytes: Uint8Array): unknown {
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return undefined;
  }
}

const NO_STORE = { "cache-control": "no-store" };

function json(body: unknown, status = 200, headers?: HeadersInit): Response {
  return Response.json(body, { status, headers });
}
