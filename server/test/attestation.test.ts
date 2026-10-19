import { describe, expect, it } from "vitest";
import { fromBase64, rawSignature, sha256, toBase64, verifyAssertion, verifyAttestation } from "../src/attestation";
import { decode } from "../src/cbor";
import worker from "../src/index";
import { clientData, HEADERS } from "../src/keys";
import { makeD1 } from "./d1";
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
    await expect(verifyAttestation({ ...sampleInput, appId: "1234567890.com.example.other" })).rejects.toThrow("App ID mismatch");
    await expect(verifyAttestation({ ...sampleInput, keyId: new Uint8Array(32) })).rejects.toThrow("key identifier mismatch");
    await expect(verifyAttestation({ ...sampleInput, clientDataHash: new Uint8Array(32) })).rejects.toThrow("nonce mismatch");
  });

  it("rejects an expired credential certificate", async () => {
    await expect(verifyAttestation({ ...sampleInput, now: Date.parse("2026-05-01T00:00:00Z") })).rejects.toThrow("validity");
  });

  it("rejects a chain that doesn't lead to Apple's root", async () => {
    // The intermediate certificate as root: the intermediate's issuer then doesn't match.
    const x5c = (decode(sampleInput.attestation) as Map<string, Map<string, Uint8Array[]>>).get("attStmt")!.get("x5c")!;
    await expect(verifyAttestation({ ...sampleInput, root: x5c[1] })).rejects.toThrow("chain");
  });

  it("rejects tampered authenticator data", async () => {
    const tampered = new Uint8Array(sampleInput.attestation);
    // Last byte of authData: part of the validation category, covered by the nonce.
    tampered[tampered.length - 1] = tampered[tampered.length - 1]! ^ 1;
    await expect(verifyAttestation({ ...sampleInput, attestation: tampered })).rejects.toThrow("nonce mismatch");
  });

  it("rejects garbage", async () => {
    await expect(verifyAttestation({ ...sampleInput, attestation: new Uint8Array([0xa1, 0x01]) })).rejects.toThrow();
  });
});

const appId = "TEAM123456.com.fouteox.biathlon";

/** A device-side App Attest key, signing like DCAppAttestService.generateAssertion. */
async function makeDevice() {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const publicKey = new Uint8Array((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const keyId = toBase64(await sha256(publicKey));
  const rpIdHash = await sha256(new TextEncoder().encode(appId));
  let counter = 0;
  const assert = async (data: Uint8Array, options: { counter?: number; rpIdHash?: Uint8Array } = {}) => {
    counter = options.counter ?? counter + 1;
    const authenticatorData = new Uint8Array(37);
    authenticatorData.set(options.rpIdHash ?? rpIdHash);
    new DataView(authenticatorData.buffer).setUint32(33, counter);
    const nonce = await sha256(new Uint8Array([...authenticatorData, ...(await sha256(data))]));
    const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, nonce));
    return cborMap({ signature: derSignature(raw), authenticatorData });
  };
  return { publicKey, keyId, assert };
}

describe("assertion", () => {
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
    await expect(verifyAssertion({ ...input, assertion: await device.assert(data, { counter: 6 }), clientData: new Uint8Array(1) })).rejects.toThrow(
      "invalid signature",
    );
    await expect(verifyAssertion({ ...input, assertion: await device.assert(data, { counter: 7, rpIdHash: new Uint8Array(32) }) })).rejects.toThrow(
      "App ID mismatch",
    );
    await expect(verifyAssertion({ ...input, assertion: await device.assert(data, { counter: 5 }) })).rejects.toThrow("counter");
  });

  it("converts DER signatures with and without leading zeros", () => {
    const der = Uint8Array.from([0x30, 0x07, 0x02, 0x02, 0x00, 0x80, 0x02, 0x01, 0x01]);
    const raw = rawSignature(der, 32);
    expect(raw[31]).toBe(0x80);
    expect(raw[63]).toBe(0x01);
    expect(raw.slice(0, 31).every((byte) => byte === 0)).toBe(true);
  });
});

describe("device registration endpoint", () => {
  const token = "ab".repeat(32);
  const registration = { environment: "sandbox", categories: ["SW"], cancellation: true, rescheduling: true, locale: "fr-FR", timeZone: "Europe/Paris" };

  async function setUp() {
    const env = { DB: makeD1(), APNS_TEAM_ID: "TEAM123456", APNS_TOPIC: "com.fouteox.biathlon" } as unknown as Env;
    const device = await makeDevice();
    await env.DB.prepare(
      "INSERT INTO app_attest_keys (key_id, public_key, environment, counter, receipt, created_at) VALUES (?1, ?2, 'development', 0, '', 0)",
    )
      .bind(device.keyId, toBase64(device.publicKey))
      .run();
    const call = (request: Request) => worker.fetch!(request as never, env, {} as ExecutionContext);
    const challenge = async () => {
      const response = await call(new Request("https://server.test/v1/app-attest/challenges", { method: "POST" }));
      return ((await response.json()) as { challenge: string }).challenge;
    };
    /** Signs the request the way the app does (PushRegistration.swift). */
    const signed = async (method: string, deviceToken: string, body?: unknown, tamper?: (body: string) => string) => {
      const value = await challenge();
      const text = body === undefined ? "" : JSON.stringify(body);
      const path = `/v1/devices/${deviceToken}`;
      const assertion = await device.assert(clientData(value, method, path, new TextEncoder().encode(text)));
      const headers = { [HEADERS.keyId]: device.keyId, [HEADERS.assertion]: toBase64(assertion), [HEADERS.challenge]: value };
      return new Request(`https://server.test${path}`, { method, headers, body: tamper ? tamper(text) : text || undefined });
    };
    const tokens = async () => (await env.DB.prepare("SELECT token FROM devices").all<{ token: string }>()).results.map((row) => row.token);
    return { env, call, signed, tokens };
  }

  it("registers and unregisters with a valid assertion", async () => {
    const { call, signed, tokens } = await setUp();
    expect((await call(await signed("PUT", token, registration))).status).toBe(204);
    expect(await tokens()).toEqual([token]);
    expect((await call(await signed("DELETE", token))).status).toBe(204);
    expect(await tokens()).toEqual([]);
  });

  it("rejects unsigned, replayed and tampered requests", async () => {
    const { call, signed, tokens } = await setUp();
    const unsigned = new Request(`https://server.test/v1/devices/${token}`, { method: "PUT", body: JSON.stringify(registration) });
    expect((await call(unsigned)).status).toBe(401);

    const request = await signed("PUT", token, registration);
    expect((await call(request.clone())).status).toBe(204);
    const replay = await call(request);
    expect(replay.status).toBe(401);
    expect(await replay.json()).toEqual({ error: "invalid challenge" });

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

  it("keeps one token per key", async () => {
    const { call, signed, tokens } = await setUp();
    await call(await signed("PUT", token, registration));
    await call(await signed("PUT", "cd".repeat(32), registration));
    expect(await tokens()).toEqual(["cd".repeat(32)]);
  });
});

/** Encodes a CBOR map with text keys and byte string values. */
function cborMap(entries: Record<string, Uint8Array>): Uint8Array {
  const head = (major: number, length: number) =>
    length < 24 ? [(major << 5) | length] : length < 256 ? [(major << 5) | 24, length] : [(major << 5) | 25, length >> 8, length & 0xff];
  const bytes = [...head(5, Object.keys(entries).length)];
  for (const [key, value] of Object.entries(entries)) {
    const text = new TextEncoder().encode(key);
    bytes.push(...head(3, text.length), ...text, ...head(2, value.length), ...value);
  }
  return Uint8Array.from(bytes);
}

/** r || s to DER, as App Attest encodes signatures. */
function derSignature(raw: Uint8Array): Uint8Array {
  const integer = (value: Uint8Array) => {
    let start = 0;
    while (start < value.length - 1 && value[start] === 0) start++;
    const trimmed = [...value.subarray(start)];
    if (trimmed[0]! & 0x80) trimmed.unshift(0);
    return [0x02, trimmed.length, ...trimmed];
  };
  const body = [...integer(raw.subarray(0, 32)), ...integer(raw.subarray(32))];
  return Uint8Array.from([0x30, body.length, ...body]);
}
