import { probe } from "./apns";
import { deleteDevice, isDeviceToken, parseRegistration, saveDevice } from "./devices";
import { IBU_BASE_URL } from "./ibu";
import { runCron } from "./watcher";

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    const device = url.pathname.match(/^\/v1\/devices\/([^/]+)$/);

    if (device) {
      const token = decodeURIComponent(device[1] ?? "").toLowerCase();
      if (request.method === "PUT") {
        const body = await request.json().catch(() => undefined);
        const registration = parseRegistration(token, body);
        if (typeof registration === "string") return json({ error: registration }, 400);
        await saveDevice(env.DB, registration, Date.now());
        return new Response(null, { status: 204 });
      }
      if (request.method === "DELETE") {
        if (!isDeviceToken(token)) return json({ error: "invalid device token" }, 400);
        await deleteDevice(env.DB, token);
        return new Response(null, { status: 204 });
      }
      return new Response(null, { status: 405 });
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
    await runCron(env, controller.scheduledTime);
  },
} satisfies ExportedHandler<Env>;

/**
 * Read-only cache in front of biathlonresults.com, with the same paths and
 * query strings (`/ibu/Results?RaceId=…`). Cloudflare documents a working
 * Cache API for Workers on custom domains.
 */
const CACHE_SECONDS: Record<string, number> = {
  Results: 15,
  AnalyticResults: 15,
  Competitions: 60,
  CupResults: 300,
  Events: 3600,
  Cups: 3600,
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

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}
