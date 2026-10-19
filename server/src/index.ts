import { probe } from "./apns";
import { deleteDevice, isDeviceToken, parseRegistration, saveDevice } from "./devices";
import { IBU_BASE_URL } from "./ibu";
import { authorize, issueChallenge, pruneChallenges, registerKey } from "./keys";
import { runCron } from "./watcher";

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    const device = url.pathname.match(/^\/v1\/devices\/([^/]+)$/);

    if (device) {
      if (request.method !== "PUT" && request.method !== "DELETE") return new Response(null, { status: 405 });
      const token = decodeURIComponent(device[1] ?? "").toLowerCase();
      // Read once: the assertion signs these exact bytes.
      const body = new Uint8Array(await request.arrayBuffer());
      const registration = request.method === "PUT" ? parseRegistration(token, parseJSON(body)) : undefined;
      if (typeof registration === "string") return json({ error: registration }, 400);
      if (!isDeviceToken(token)) return json({ error: "invalid device token" }, 400);
      const auth = await authorize(env, request, body, Date.now());
      if ("error" in auth) return json({ error: auth.error }, auth.status);
      if (registration) await saveDevice(env.DB, registration, auth.keyId, Date.now());
      else await deleteDevice(env.DB, token);
      return new Response(null, { status: 204 });
    }

    if (url.pathname === "/v1/app-attest/challenges" && request.method === "POST") {
      return json({ challenge: await issueChallenge(env.DB, Date.now()) }, 201);
    }

    if (url.pathname === "/v1/app-attest/keys" && request.method === "POST") {
      const failure = await registerKey(env, await request.json().catch(() => undefined), Date.now());
      return failure ? json({ error: failure.error }, failure.status) : new Response(null, { status: 204 });
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
      await pruneChallenges(env.DB, controller.scheduledTime);
    }
  },
} satisfies ExportedHandler<Env>;

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

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}
