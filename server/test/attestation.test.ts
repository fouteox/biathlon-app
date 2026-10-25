import { createExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vite-plus/test";
import { AsnEcSignatureFormatter } from "@peculiar/x509";
import { decode, encode } from "cborg";
import { AttestationError, fromBase64, sha256, toBase64, verifyAssertion, verifyAttestation } from "../src/attestation";
import { deleteOwnedDevice } from "../src/devices";
import worker from "../src/index";
import { checkChallenge, issueChallenge } from "../src/challenges";
import { clientData, HEADERS, pruneKeys } from "../src/keys";
import sample from "./fixtures/apple-attestation-sample.json";

// Apple's sample was attested on 2026-04-20; its credential certificate expires on 2026-04-23.
const sampleTime = Date.parse("2026-04-21T00:00:00Z");
// Apple's sample passed the raw challenge as clientDataHash (its "expected clientDataHash"
// ends with the challenge's bytes); the app passes the SHA-256 of the challenge.
const sampleInput = {
  attestation: fromBase64(sample.attestation),
  keyId: fromBase64(sample.keyId),
  clientDataHash: new TextEncoder().encode(sample.challenge),
  appId: sample.appId,
  now: sampleTime,
  // Apple's sample is an operating system executable (category 1).
  validationCategories: [1],
};

describe("attestation", () => {
  it("verifies Apple's sample attestation object", async () => {
    const key = await verifyAttestation(sampleInput);
    expect(key.environment).toBe("production");
    expect(key.validationCategory).toBe(1);
    expect(key.bundleVersion).toBe("1");
    expect(key.publicKey.length).toBe(65);
    expect(toBase64(await sha256(key.publicKey))).toBe(sample.keyId);
  });

  it("rejects an attestation for another app, key or challenge", async () => {
    await expect(verifyAttestation({ ...sampleInput, appId: "1234567890.com.example.other" })).rejects.toThrow(
      "App ID mismatch",
    );
    await expect(verifyAttestation({ ...sampleInput, keyId: new Uint8Array(32) })).rejects.toThrow(
      "key identifier mismatch",
    );
    await expect(verifyAttestation({ ...sampleInput, clientDataHash: new Uint8Array(32) })).rejects.toThrow(
      "nonce mismatch",
    );
  });

  it("rejects validation categories other than this app's builds", async () => {
    await expect(verifyAttestation({ ...sampleInput, validationCategories: undefined })).rejects.toThrow(
      "validation category 1 not allowed",
    );
  });

  it("rejects builds older than the minimum bundle version", async () => {
    // Apple's sample is build "1".
    await expect(verifyAttestation({ ...sampleInput, minBundleVersion: "1.0" })).resolves.toBeDefined();
    await expect(verifyAttestation({ ...sampleInput, minBundleVersion: "0.9.9" })).resolves.toBeDefined();
    await expect(verifyAttestation({ ...sampleInput, minBundleVersion: "1.0.1" })).rejects.toThrow(
      "bundle version 1 no longer supported",
    );
    await expect(verifyAttestation({ ...sampleInput, minBundleVersion: "10" })).rejects.toThrow("no longer supported");
  });

  it("rejects an expired credential certificate", async () => {
    await expect(verifyAttestation({ ...sampleInput, now: Date.parse("2026-05-01T00:00:00Z") })).rejects.toThrow(
      "validity",
    );
  });

  it("rejects a chain that doesn't lead to Apple's root", async () => {
    // The intermediate certificate as root: the intermediate's issuer then doesn't match.
    await expect(verifyAttestation({ ...sampleInput, root: sampleCertificates()[1] })).rejects.toThrow("chain");
  });

  it("rejects tampered authenticator data", async () => {
    const tampered = new Uint8Array(sampleInput.attestation);
    // Last byte of authData: part of the validation category, covered by the nonce.
    tampered[tampered.length - 1] = tampered[tampered.length - 1]! ^ 1;
    await expect(verifyAttestation({ ...sampleInput, attestation: tampered })).rejects.toThrow("nonce mismatch");
  });

  it("rejects a credential certificate whose signature doesn't match", async () => {
    const attestation = decode(sampleInput.attestation, { useMaps: true }) as Map<string, unknown>;
    const [leaf, intermediate] = sampleCertificates();
    const tampered = new Uint8Array(leaf!);
    // Last byte of the signature value.
    tampered[tampered.length - 1] = tampered[tampered.length - 1]! ^ 1;
    const statement = new Map(attestation.get("attStmt") as Map<string, unknown>).set("x5c", [tampered, intermediate]);
    await expect(
      verifyAttestation({ ...sampleInput, attestation: encode(new Map(attestation).set("attStmt", statement)) }),
    ).rejects.toThrow("invalid certificate signature");
  });

  it("rejects a malformed certificate", async () => {
    const attestation = decode(sampleInput.attestation, { useMaps: true }) as Map<string, unknown>;
    const statement = new Map(attestation.get("attStmt") as Map<string, unknown>).set("x5c", [
      Uint8Array.from([0x30, 0x00]),
      sampleCertificates()[1],
    ]);
    await expect(
      verifyAttestation({ ...sampleInput, attestation: encode(new Map(attestation).set("attStmt", statement)) }),
    ).rejects.toThrow("malformed input");
  });

  it("rejects garbage", async () => {
    await expect(verifyAttestation({ ...sampleInput, attestation: new Uint8Array([0xa1, 0x01]) })).rejects.toThrow();
  });
});

const appId = env.APP_ATTEST_APP_ID;

/** A device-side App Attest key, signing like DCAppAttestService.generateAssertion. */
async function makeDevice() {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const publicKey = new Uint8Array((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const keyId = toBase64(await sha256(publicKey));
  const rpIdHash = await sha256(new TextEncoder().encode(appId));
  let counter = 0;
  const assert = async (
    data: Uint8Array,
    options: { counter?: number; rpIdHash?: Uint8Array; extensions?: Uint8Array } = {},
  ) => {
    counter = options.counter ?? counter + 1;
    const extensions = options.extensions ?? buildExtensions(3, "1");
    const authenticatorData = new Uint8Array(37 + extensions.length);
    authenticatorData.set(options.rpIdHash ?? rpIdHash);
    new DataView(authenticatorData.buffer).setUint32(33, counter);
    authenticatorData.set(extensions, 37);
    const nonce = await sha256(new Uint8Array([...authenticatorData, ...(await sha256(data))]));
    const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, nonce));
    // App Attest encodes signatures in DER.
    const signature = new Uint8Array(
      new AsnEcSignatureFormatter().toAsnSignature({ name: "ECDSA", namedCurve: "P-256" }, raw)!,
    );
    return encode({ signature, authenticatorData });
  };
  return { publicKey, keyId, assert };
}

/** Apple's extensions map: the validation category (little-endian UInt32) and the bundle version. */
function buildExtensions(category: number, version: string): Uint8Array {
  return encode({
    apple_validation_category_01: Uint8Array.from([category, 0, 0, 0]),
    apple_bundle_version_01: version,
  });
}

/** The credential and intermediate certificates of Apple's sample. */
function sampleCertificates(): Uint8Array[] {
  const attestation = decode(sampleInput.attestation, { useMaps: true }) as Map<string, Map<string, Uint8Array[]>>;
  return attestation.get("attStmt")!.get("x5c")!;
}

describe("assertion", () => {
  it("rejects assertions without the build extensions", async () => {
    const device = await makeDevice();
    const data = new TextEncoder().encode("request");
    const input = { clientData: data, publicKey: device.publicKey, appId, previousCounter: 0 };
    await expect(
      verifyAssertion({ ...input, assertion: await device.assert(data, { extensions: new Uint8Array() }) }),
    ).rejects.toThrow("missing validation category");
    await expect(
      verifyAssertion({
        ...input,
        assertion: await device.assert(data, { extensions: buildExtensions(3, "1").subarray(0, 39) }),
      }),
    ).rejects.toThrow();
  });

  it("checks the bundle version of assertions", async () => {
    const device = await makeDevice();
    const data = new TextEncoder().encode("request");
    const input = { clientData: data, publicKey: device.publicKey, appId, previousCounter: 0, minBundleVersion: "2" };
    await expect(verifyAssertion({ ...input, assertion: await device.assert(data) })).rejects.toThrow(
      "no longer supported",
    );
    await expect(
      verifyAssertion({ ...input, assertion: await device.assert(data, { extensions: buildExtensions(4, "2") }) }),
    ).resolves.toBe(2);
  });

  it("accepts a signed request and returns its counter", async () => {
    const device = await makeDevice();
    const data = new TextEncoder().encode("request");
    const input = { clientData: data, publicKey: device.publicKey, appId, previousCounter: 0 };
    expect(await verifyAssertion({ ...input, assertion: await device.assert(data) })).toBe(1);
  });

  it("rejects other data, another app, and a counter that didn't grow", async () => {
    const device = await makeDevice();
    const data = new TextEncoder().encode("request");
    const input = { clientData: data, publicKey: device.publicKey, appId, previousCounter: 5 };
    await expect(
      verifyAssertion({
        ...input,
        assertion: await device.assert(data, { counter: 6 }),
        clientData: new Uint8Array(1),
      }),
    ).rejects.toThrow("invalid signature");
    await expect(
      verifyAssertion({ ...input, assertion: await device.assert(data, { counter: 7, rpIdHash: new Uint8Array(32) }) }),
    ).rejects.toThrow("App ID mismatch");
    await expect(verifyAssertion({ ...input, assertion: await device.assert(data, { counter: 5 }) })).rejects.toThrow(
      "counter",
    );
  });

  it("rejects malformed CBOR as a verification failure", async () => {
    // { "fmt": <text with an invalid UTF-8 byte> }
    const bad = Uint8Array.from([0xa1, 0x63, 0x66, 0x6d, 0x74, 0x61, 0xff]);
    await expect(verifyAttestation({ ...sampleInput, attestation: bad })).rejects.toThrow(AttestationError);
    // The same map twice: cborg rejects duplicate keys.
    const duplicate = Uint8Array.from([0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02]);
    await expect(verifyAttestation({ ...sampleInput, attestation: duplicate })).rejects.toThrow("malformed input");
  });
});

/**
 * An attested device calling the worker, with its requests to `prefix` + token signed
 * the way the app signs them (AppAttest.swift), and the tokens stored in `table`.
 */
async function setUp({ prefix = "/v1/devices/", table = "devices" } = {}) {
  const device = await makeDevice();
  await env.DB.prepare(
    "INSERT INTO app_attest_keys (key_id, public_key, environment, counter, receipt, created_at) VALUES (?1, ?2, 'development', 0, '', 0)",
  )
    .bind(device.keyId, toBase64(device.publicKey))
    .run();
  const call = (request: Request) => worker.fetch(request as never, env, createExecutionContext());
  const challenge = async () => {
    const response = await call(
      new Request("https://server.test/v1/app-attest/challenges?purpose=assert", { method: "POST" }),
    );
    return ((await response.json()) as { challenge: string }).challenge;
  };
  const signed = async (method: string, deviceToken: string, body?: unknown, tamper?: (body: string) => string) => {
    const value = await challenge();
    const text = body === undefined ? "" : JSON.stringify(body);
    const path = `${prefix}${deviceToken}`;
    const assertion = await device.assert(clientData(value, method, path, new TextEncoder().encode(text)));
    const headers = {
      [HEADERS.keyId]: device.keyId,
      [HEADERS.assertion]: toBase64(assertion),
      [HEADERS.challenge]: value,
    };
    return new Request(`https://server.test${path}`, {
      method,
      headers,
      body: tamper ? tamper(text) : text || undefined,
    });
  };
  const tokens = async () =>
    (await env.DB.prepare(`SELECT token FROM ${table}`).all<{ token: string }>()).results.map((row) => row.token);
  return { call, signed, tokens };
}

describe("device registration endpoint", () => {
  const token = "ab".repeat(32);
  const registration = {
    environment: "sandbox",
    categories: ["SW"],
    cancellation: true,
    rescheduling: true,
    locale: "fr-FR",
    timeZone: "Europe/Paris",
  };

  it("registers and unregisters with a valid assertion", async () => {
    const { call, signed, tokens } = await setUp();
    expect((await call(await signed("PUT", token, registration))).status).toBe(204);
    expect(await tokens()).toEqual([token]);
    expect((await call(await signed("DELETE", token))).status).toBe(204);
    expect(await tokens()).toEqual([]);
  });

  it("rejects unsigned, replayed and tampered requests", async () => {
    const { call, signed, tokens } = await setUp();
    const unsigned = new Request(`https://server.test/v1/devices/${token}`, {
      method: "PUT",
      body: JSON.stringify(registration),
    });
    expect((await call(unsigned)).status).toBe(401);

    const request = await signed("PUT", token, registration);
    expect((await call(request.clone())).status).toBe(204);
    const replay = await call(request);
    expect(replay.status).toBe(401);
    expect(await replay.json()).toEqual({ error: "assertion rejected: counter did not increase" });

    const tampered = await signed("PUT", token, registration, (body) => body.replace("SW", "SM"));
    expect((await call(tampered)).status).toBe(401);
    expect(await tokens()).toEqual([token]);
  });

  it("tells the app when its key is unknown", async () => {
    const { call, signed } = await setUp();
    const request = await signed("PUT", token, registration);
    request.headers.set(HEADERS.keyId, toBase64(new Uint8Array(32)));
    const response = await call(request);
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unknown key" });
  });

  it("deletes keys no device has used for 30 days", async () => {
    const { call, signed } = await setUp();
    const keys = async () =>
      (await env.DB.prepare("SELECT COUNT(*) AS n FROM app_attest_keys").first<{ n: number }>())!.n;
    await call(await signed("PUT", token, registration));
    const later = Date.now() + 31 * 24 * 60 * 60 * 1000;
    await pruneKeys(env.DB, later);
    expect(await keys()).toBe(1);
    await call(await signed("DELETE", token));
    await pruneKeys(env.DB, later);
    expect(await keys()).toBe(0);
  });

  it("lets only the key that registered a token change it", async () => {
    const owner = await setUp();
    const other = await setUp();
    await owner.call(await owner.signed("PUT", token, registration));
    const put = await other.call(await other.signed("PUT", token, registration));
    expect(put.status).toBe(403);
    expect((await other.call(await other.signed("DELETE", token))).status).toBe(403);
    expect(await owner.tokens()).toEqual([token]);
  });

  it("lets a key claim a token registered before App Attest", async () => {
    const { call, signed } = await setUp();
    await call(await signed("PUT", token, registration));
    await env.DB.prepare("UPDATE devices SET app_attest_key_id = NULL").run();
    const other = await setUp();
    expect((await other.call(await other.signed("PUT", token, registration))).status).toBe(204);
    expect((await call(await signed("DELETE", token))).status).toBe(403);
    expect(await other.tokens()).toEqual([token]);
  });

  it("checks ownership in the delete itself", async () => {
    const { call, signed, tokens } = await setUp();
    await call(await signed("PUT", token, registration));
    const owner = (await env.DB.prepare("SELECT app_attest_key_id AS keyId FROM devices").first<{ keyId: string }>())!
      .keyId;
    await deleteOwnedDevice(env.DB, token, "another key");
    expect(await tokens()).toEqual([token]);
    await deleteOwnedDevice(env.DB, token, owner);
    expect(await tokens()).toEqual([]);
  });

  it("keeps one token per key", async () => {
    const { call, signed, tokens } = await setUp();
    await call(await signed("PUT", token, registration));
    await call(await signed("PUT", "cd".repeat(32), registration));
    expect(await tokens()).toEqual(["cd".repeat(32)]);
  });

  it("stores the token in lowercase and rejects one that isn't hex", async () => {
    const { call, signed, tokens } = await setUp();
    expect((await call(await signed("PUT", token.toUpperCase(), registration))).status).toBe(204);
    expect(await tokens()).toEqual([token]);
    for (const method of ["PUT", "DELETE"] as const) {
      const response = await call(await signed(method, "not-a-token", method === "PUT" ? registration : undefined));
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({ error: "invalid token" });
    }
  });
});

describe("Live Activity start endpoint", () => {
  const token = "ef".repeat(32);
  const favorites = { environment: "production", athletes: ["BTFRA00000000001"], nations: ["NOR"] };
  const live = () => setUp({ prefix: "/v1/live-activity-starts/", table: "live_start_tokens" });

  it("saves and forgets the favorites with a valid assertion", async () => {
    const { call, signed, tokens } = await live();
    expect((await call(await signed("PUT", token, favorites))).status).toBe(204);
    const row = await env.DB.prepare("SELECT environment, athletes, nations FROM live_start_tokens").first();
    expect(row).toEqual({ environment: "production", athletes: '["BTFRA00000000001"]', nations: '["NOR"]' });
    expect((await call(await signed("DELETE", token))).status).toBe(204);
    expect(await tokens()).toEqual([]);
  });

  it("rejects unsigned requests and invalid favorites", async () => {
    const { call, signed, tokens } = await live();
    const unsigned = new Request(`https://server.test/v1/live-activity-starts/${token}`, {
      method: "PUT",
      body: JSON.stringify(favorites),
    });
    expect((await call(unsigned)).status).toBe(401);
    for (const body of [
      { ...favorites, environment: "staging" },
      { ...favorites, athletes: [42] },
      { ...favorites, nations: ["France"] },
      { ...favorites, athletes: [], nations: [] },
      { ...favorites, athletes: Array.from({ length: 501 }, (_, index) => `BT${index}`) },
    ]) {
      expect((await call(await signed("PUT", token, body))).status).toBe(400);
    }
    expect((await call(await signed("PUT", "not-a-token", favorites))).status).toBe(400);
    expect(await tokens()).toEqual([]);
  });

  it("lets only the key that saved a token change it, and keeps one token per key", async () => {
    const owner = await live();
    const other = await live();
    await owner.call(await owner.signed("PUT", token, favorites));
    expect((await other.call(await other.signed("PUT", token, favorites))).status).toBe(403);
    expect((await other.call(await other.signed("DELETE", token))).status).toBe(403);
    expect(await owner.tokens()).toEqual([token]);
    await owner.call(await owner.signed("PUT", "cd".repeat(32), favorites));
    expect(await owner.tokens()).toEqual(["cd".repeat(32)]);
  });

  it("forgets the key's favorites whatever token the app deletes with", async () => {
    const { call, signed, tokens } = await live();
    await call(await signed("PUT", token, favorites));
    // ActivityKit replaced the token before the app could send the new one.
    expect((await call(await signed("DELETE", "cd".repeat(32)))).status).toBe(204);
    expect(await tokens()).toEqual([]);
  });

  it("keeps the keys of saved favorites", async () => {
    const { call, signed } = await live();
    const keys = async () =>
      (await env.DB.prepare("SELECT COUNT(*) AS n FROM app_attest_keys").first<{ n: number }>())!.n;
    await call(await signed("PUT", token, favorites));
    const later = Date.now() + 31 * 24 * 60 * 60 * 1000;
    await pruneKeys(env.DB, later);
    expect(await keys()).toBe(1);
    await call(await signed("DELETE", token));
    await pruneKeys(env.DB, later);
    expect(await keys()).toBe(0);
  });
});

describe("challenges", () => {
  const now = Date.parse("2026-11-26T12:00:00Z");

  it("answers 429 to an IP address past 30 challenges a minute", async () => {
    const issue = (ip: string) =>
      worker.fetch(
        new Request("https://server.test/v1/app-attest/challenges?purpose=attest", {
          method: "POST",
          headers: { "cf-connecting-ip": ip },
        }) as never,
        env,
        createExecutionContext(),
      );
    for (let index = 0; index < 30; index += 1) expect((await issue("192.0.2.1")).status).toBe(201);

    const limited = await issue("192.0.2.1");

    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBe("60");
    expect((await issue("192.0.2.2")).status).toBe(201);
  });

  it("accepts a fresh challenge for its purpose only", async () => {
    const challenge = await issueChallenge("secret", "assert", now);
    expect(await checkChallenge("secret", challenge, "assert", now + 60_000)).toBe(true);
    expect(await checkChallenge("secret", challenge, "attest", now)).toBe(false);
    expect(await checkChallenge("other", challenge, "assert", now)).toBe(false);
  });

  it("expires assert challenges after 5 minutes and attest ones after a day", async () => {
    expect(
      await checkChallenge("secret", await issueChallenge("secret", "assert", now), "assert", now + 6 * 60_000),
    ).toBe(false);
    const attest = await issueChallenge("secret", "attest", now);
    expect(await checkChallenge("secret", attest, "attest", now + 23 * 3_600_000)).toBe(true);
    expect(await checkChallenge("secret", attest, "attest", now + 25 * 3_600_000)).toBe(false);
  });

  it("rejects forged and malformed challenges", async () => {
    const challenge = await issueChallenge("secret", "assert", now);
    const forged = challenge.replace(`assert.${now}`, `assert.${now + 1}`);
    expect(await checkChallenge("secret", forged, "assert", now)).toBe(false);
    expect(await checkChallenge("secret", "nonsense", "assert", now)).toBe(false);
    expect(await checkChallenge("secret", "a.b.c.!!", "assert", now)).toBe(false);
  });
});
