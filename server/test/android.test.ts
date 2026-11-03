import { createExecutionContext, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vite-plus/test";
import { parseAndroidRegistration, saveAndroidDevice } from "../src/devices";
import { buildMessage, classifyFCM, isInstallationId } from "../src/fcm";
import { accessToken, fetchAccessToken, SCOPES } from "../src/google";
import worker from "../src/index";
import { androidResourceName, formatStart, LOC_KEYS } from "../src/payload";
import { HEADER, refusal, requestHash, type Verdict } from "../src/playIntegrity";
import type { PushSender } from "../src/pushSender";
import { drainOutbox, pollRaces } from "../src/watcher";
import { answer } from "./network";

const NOW = Date.parse("2026-11-26T14:00:00Z");
const RACE_ID = "BT2627SWRLCP01SMIN";
const FID = "cR2mJ0yxQ9aQk3vT5b_x-Q";
const PACKAGE = "com.fouteox.biathlon";

const alert = {
  kind: "rescheduled" as const,
  raceId: RACE_ID,
  raceName: "Men's 20km Individual",
  startTime: "2026-11-26T15:45:00.000Z",
  locale: "fr",
  timeZone: "Europe/Paris",
};

/** Google's answers: an access token, then the verdict `verdict` gives for each integrity token. */
function stubGoogle(options: { verdict?: (hash: string) => Verdict | Response; fcm?: () => Response } = {}) {
  const sent: { url: string; authorization: string | null; body: unknown }[] = [];
  let tokens = 0;
  answer(async (request) => {
    // Read as bytes: the token request's form body isn't text to workerd.
    const text = new TextDecoder().decode(await request.arrayBuffer());
    sent.push({ url: request.url, authorization: request.headers.get("authorization"), body: text });
    if (request.url === "https://oauth2.googleapis.com/token") {
      tokens += 1;
      return Response.json({ access_token: `google-token-${tokens}`, expires_in: 3599, token_type: "Bearer" });
    }
    if (request.url.startsWith("https://playintegrity.googleapis.com/")) {
      const { integrityToken } = JSON.parse(text) as { integrityToken: string };
      const verdict = options.verdict?.(integrityToken) ?? genuine(integrityToken);
      return verdict instanceof Response ? verdict : Response.json({ tokenPayloadExternal: verdict });
    }
    if (request.url.startsWith("https://fcm.googleapis.com/")) {
      return options.fcm?.() ?? Response.json({ name: "projects/biathlon-test/messages/1" });
    }
    return undefined;
  });
  return sent;
}

/**
 * The verdict of a genuine app on a genuine device, for a test whose integrity token is the
 * request hash itself, as Google echoes it.
 */
function genuine(hash: string, timestamp = Date.now()): Verdict {
  return {
    requestDetails: { requestPackageName: PACKAGE, requestHash: hash, timestampMillis: String(timestamp) },
    appIntegrity: { appRecognitionVerdict: "PLAY_RECOGNIZED", packageName: PACKAGE, versionCode: "3" },
    deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
  };
}

const registration = {
  categories: ["SM", "MX"],
  cancellation: true,
  rescheduling: true,
  locale: "de-DE",
  timeZone: "Europe/Berlin",
};

/** A request the app signs as it does: its integrity token carries the request's hash, here as the token itself. */
async function request(method: "PUT" | "DELETE", fid: string, body?: unknown, token?: string) {
  const text = body === undefined ? "" : JSON.stringify(body);
  const path = `/v1/android-devices/${fid}`;
  const hash = await requestHash(method, path, new TextEncoder().encode(text));
  return new Request(`https://server.test${path}`, {
    method,
    headers: { [HEADER]: token ?? hash },
    body: text || undefined,
  });
}

const call = (request: Request) => worker.fetch(request as never, env, createExecutionContext());

const devices = () =>
  env.DB.prepare("SELECT token, platform, environment, categories, locale FROM devices ORDER BY token")
    .all()
    .then(({ results }) => results);

describe("Android device registration", () => {
  it("accepts Firebase Installation IDs and the iOS preferences", () => {
    expect(isInstallationId(FID)).toBe(true);
    expect(isInstallationId("a/b")).toBe(false);
    expect(isInstallationId("")).toBe(false);
    expect(parseAndroidRegistration(FID, registration)).toEqual({ fid: FID, ...registration });
    expect(parseAndroidRegistration(FID, { ...registration, categories: ["XX"] })).toBe("invalid categories");
  });

  it("registers and unregisters a device vouched for by Play Integrity", async () => {
    stubGoogle();
    expect((await call(await request("PUT", FID, registration))).status).toBe(204);
    expect(await devices()).toEqual([
      { token: FID, platform: "android", environment: null, categories: '["SM","MX"]', locale: "de-DE" },
    ]);

    expect((await call(await request("DELETE", FID))).status).toBe(204);
    expect(await devices()).toEqual([]);
  });

  it("refuses a request without a token, with a token for another request, or that Google refuses", async () => {
    const sent = stubGoogle({
      verdict: (token) => (token === "garbled" ? new Response("{}", { status: 400 }) : genuine(token)),
    });
    const unsigned = new Request(`https://server.test/v1/android-devices/${FID}`, {
      method: "PUT",
      body: JSON.stringify(registration),
    });
    expect((await call(unsigned)).status).toBe(401);
    // Before Google is asked, which counts each check against the app's quota.
    expect(sent).toEqual([]);

    const otherRequest = await requestHash("PUT", `/v1/android-devices/${FID}`, new TextEncoder().encode("{}"));
    const tampered = await call(await request("PUT", FID, registration, otherRequest));
    expect(tampered.status).toBe(401);
    expect(await tampered.json()).toEqual({ error: "integrity verdict rejected: request hash mismatch" });

    expect((await call(await request("PUT", FID, registration, "garbled"))).status).toBe(401);
    expect(await devices()).toEqual([]);
  });

  it("checks the request is valid before spending an integrity check", async () => {
    const sent = stubGoogle();
    expect((await call(await request("PUT", "a%2Fb", registration))).status).toBe(400);
    expect((await call(await request("PUT", FID, { ...registration, cancellation: "yes" }))).status).toBe(400);
    expect(sent).toEqual([]);
  });

  it("answers 503 while Google can't check the token, for the app to try again", async () => {
    stubGoogle({ verdict: () => new Response("unavailable", { status: 503 }) });
    expect((await call(await request("PUT", FID, registration))).status).toBe(503);
  });

  it("signs a new access token once when Google rejects the cached one", async () => {
    let decodes = 0;
    const sent = stubGoogle({
      verdict: (token) => (++decodes === 1 ? new Response("{}", { status: 401 }) : genuine(token)),
    });
    expect((await call(await request("PUT", FID, registration))).status).toBe(204);
    expect(sent.filter(({ url }) => url.includes("playintegrity")).map(({ authorization }) => authorization)).toEqual([
      "Bearer google-token-1",
      "Bearer google-token-2",
    ]);
  });

  it("never takes over an iOS device's token", async () => {
    stubGoogle();
    const token = "ab".repeat(32);
    await env.DB.prepare(
      "INSERT INTO devices (token, platform, environment, categories, cancellation, rescheduling, locale, time_zone, updated_at) VALUES (?1, 'ios', 'sandbox', '[]', 1, 1, 'fr', 'Europe/Paris', 0)",
    )
      .bind(token)
      .run();

    expect((await call(await request("PUT", token, registration))).status).toBe(204);
    expect((await call(await request("DELETE", token))).status).toBe(204);

    expect(await devices()).toEqual([
      { token, platform: "ios", environment: "sandbox", categories: "[]", locale: "fr" },
    ]);
  });
});

describe("Play Integrity verdicts", () => {
  const expected = { packageName: PACKAGE, requestHash: "hash", minVersionCode: 2, now: NOW };
  const verdict = genuine("hash", NOW - 60_000);

  it("accepts this app from Google Play, on a certified device, for this request", () => {
    expect(refusal(verdict, expected)).toBeUndefined();
  });

  it("refuses another app, another request, a stale token, a sideloaded or old build, and an uncertified device", () => {
    const { requestDetails, appIntegrity } = verdict;
    expect(
      refusal({ ...verdict, requestDetails: { ...requestDetails, requestPackageName: "other.app" } }, expected),
    ).toBe("package mismatch");
    expect(refusal(verdict, { ...expected, requestHash: "other" })).toBe("request hash mismatch");
    expect(refusal(verdict, { ...expected, now: NOW + 10 * 60_000 })).toBe("token too old");
    expect(refusal(verdict, { ...expected, now: NOW - 10 * 60_000 })).toBe("token too old");
    expect(
      refusal(
        { ...verdict, appIntegrity: { ...appIntegrity, appRecognitionVerdict: "UNRECOGNIZED_VERSION" } },
        expected,
      ),
    ).toBe("app not recognized by Google Play");
    expect(refusal(verdict, { ...expected, minVersionCode: 4 })).toBe("version 3 no longer supported");
    expect(refusal({ ...verdict, deviceIntegrity: {} }, expected)).toBe("device integrity not met");
    expect(
      refusal({ ...verdict, deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_BASIC_INTEGRITY"] } }, expected),
    ).toBe("device integrity not met");
  });

  it("hashes the method, the path and the body, as the app does", async () => {
    // printf 'PUT /v1/android-devices/x\n{}' | openssl dgst -sha256 -binary | basenc --base64url (unpadded)
    expect(await requestHash("PUT", "/v1/android-devices/x", new TextEncoder().encode("{}"))).toBe(
      "rQr28Hi93CLw0gY8VSoeZ8IV6j31uhi2UanhldbJwSY",
    );
  });
});

describe("Google access tokens", () => {
  it("trades an RS256 assertion of the service account for a token of both scopes", async () => {
    const pair = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
    const privateKey = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----\n`;
    const sent = stubGoogle();

    const token = await fetchAccessToken(
      { projectId: "p", clientEmail: "push@p.iam.gserviceaccount.com", privateKey },
      NOW,
    );

    expect(token).toEqual({ token: "google-token-1", expiresAt: NOW + 3_599_000 });
    const form = new URLSearchParams(sent[0]!.body as string);
    expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    const [header, claims, signature] = form.get("assertion")!.split(".") as [string, string, string];
    const decode = (part: string) =>
      Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    expect(JSON.parse(new TextDecoder().decode(decode(header)))).toEqual({ alg: "RS256", typ: "JWT" });
    expect(JSON.parse(new TextDecoder().decode(decode(claims)))).toEqual({
      iss: "push@p.iam.gserviceaccount.com",
      scope: SCOPES,
      aud: "https://oauth2.googleapis.com/token",
      iat: NOW / 1000,
      exp: NOW / 1000 + 3600,
    });
    const valid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      pair.publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("reuses the cached token until five minutes before it expires", async () => {
    stubGoogle();
    expect(await accessToken(env, NOW)).toBe("google-token-1");
    expect(await accessToken(env, NOW + 54 * 60_000)).toBe("google-token-1");
    expect(await accessToken(env, NOW + 56 * 60_000)).toBe("google-token-2");
    expect(await accessToken(env, NOW + 56 * 60_000, { refresh: true })).toBe("google-token-3");
  });
});

describe("Android alerts", () => {
  it("builds the alert from the Android resources the app generates from the catalog, in the device's time zone", () => {
    const { day, time } = formatStart(alert);
    expect(
      buildMessage({ fid: FID, collapseKey: `rescheduled-${RACE_ID}`, expiration: NOW / 1000 + 1800, alert }, NOW),
    ).toEqual({
      fid: FID,
      android: {
        collapseKey: `rescheduled-${RACE_ID}`,
        priority: "HIGH",
        ttl: "1800s",
        notification: {
          titleLocKey: "race_smin",
          bodyLocKey: "push_rescheduled",
          bodyLocArgs: [day, time],
          channelId: "race-alerts",
          tag: `rescheduled-${RACE_ID}`,
        },
      },
      data: { raceId: RACE_ID, startTime: alert.startTime },
    });
    expect(androidResourceName(LOC_KEYS.cancelled)).toBe("push_cancelled");
  });

  it("names a race of a kind the app doesn't know with the IBU's name", () => {
    const message = buildMessage(
      {
        fid: FID,
        collapseKey: "k",
        expiration: 0,
        alert: { ...alert, kind: "cancelled", raceId: "BT2627SWRLCP01SMXX" },
      },
      NOW,
    );
    expect(message.android.notification).toEqual({
      title: "Men's 20km Individual",
      bodyLocKey: "push_cancelled",
      channelId: "race-alerts",
      tag: "k",
    });
    expect(message.android.ttl).toBe("0s");
  });

  it("classifies FCM responses", () => {
    expect(classifyFCM(404, "UNREGISTERED").kind).toBe("unregistered");
    expect(classifyFCM(403, "SENDER_ID_MISMATCH").kind).toBe("unregistered");
    expect(classifyFCM(401, "UNAUTHENTICATED").kind).toBe("expiredProviderToken");
    expect(classifyFCM(429, "QUOTA_EXCEEDED").kind).toBe("retry");
    expect(classifyFCM(503, "UNAVAILABLE").kind).toBe("retry");
    expect(classifyFCM(400, "INVALID_ARGUMENT").kind).toBe("failed");
    expect(classifyFCM(403, "PERMISSION_DENIED").kind).toBe("failed");
  });

  async function follow(fid: string) {
    const device = parseAndroidRegistration(fid, { ...registration, categories: ["SM"] });
    if (typeof device === "string") throw new Error(device);
    await saveAndroidDevice(env.DB, device, 0);
  }

  it("queues an Android device's alert, then sends it through FCM with the service account's token", async () => {
    await follow(FID);
    const sent = stubGoogle();
    answer(({ url }) =>
      url.includes("/Events")
        ? Response.json([{ EventId: RACE_ID.slice(0, 14), StartDate: "2026-11-23", EndDate: "2026-11-29" }])
        : url.includes("/Competitions")
          ? Response.json([
              {
                RaceId: RACE_ID,
                catId: "SM",
                ShortDescription: "Men's 20km Individual",
                StartTime: "2026-11-26T15:15:00Z",
                StatusId: 1,
              },
            ])
          : undefined,
    );
    await pollRaces(env, NOW);
    answer(({ url }) =>
      url.includes("/Competitions")
        ? Response.json([
            {
              RaceId: RACE_ID,
              catId: "SM",
              ShortDescription: "Men's 20km Individual",
              StartTime: "2026-11-26T15:15:00Z",
              StatusId: 6,
            },
          ])
        : undefined,
    );
    await pollRaces(env, NOW);
    expect((await env.DB.prepare("SELECT token, platform, environment, kind FROM outbox").all()).results).toEqual([
      { token: FID, platform: "android", environment: null, kind: "cancelled" },
    ]);

    await drainOutbox(env, NOW);

    const pushes = sent.filter(({ url }) => url.startsWith("https://fcm.googleapis.com/"));
    expect(pushes.map(({ url, authorization }) => ({ url, authorization }))).toEqual([
      {
        url: "https://fcm.googleapis.com/v1/projects/biathlon-test/messages:send",
        authorization: "Bearer google-token-1",
      },
    ]);
    expect(JSON.parse(pushes[0]!.body as string).message.fid).toBe(FID);
    expect((await env.DB.prepare("SELECT * FROM outbox").all()).results).toEqual([]);
  });

  it("forgets the devices FCM no longer knows", async () => {
    await follow(FID);
    await env.DB.prepare(
      "INSERT INTO outbox (token, platform, kind, race_id, race_name, start_time, locale, time_zone, created_at) VALUES (?1, 'android', 'cancelled', ?2, 'x', '2026-11-26T15:15:00.000Z', 'de-DE', 'Europe/Berlin', ?3)",
    )
      .bind(FID, RACE_ID, NOW)
      .run();
    stubGoogle({
      fcm: () =>
        Response.json(
          { error: { code: 404, status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } },
          { status: 404 },
        ),
    });

    await drainOutbox(env, NOW);

    expect(await devices()).toEqual([]);
  });

  it("sends a lot of Android pushes from its Durable Object", async () => {
    let calls = 0;
    stubGoogle({ fcm: () => (++calls === 2 ? new Response("{}", { status: 503 }) : Response.json({})) });
    const push = { fid: FID, collapseKey: "k", expiration: NOW / 1000 + 60, alert };

    const outcomes = await runInDurableObject(
      env.PUSH_SENDER.get(env.PUSH_SENDER.newUniqueId()),
      (sender: PushSender) => sender.send([push, push], "google-token"),
    );

    expect(outcomes.map(({ kind }) => kind).toSorted()).toEqual(["retry", "sent"]);
  });
});
