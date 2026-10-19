import { AttestationError, fromBase64, sha256, toBase64, verifyAssertion, verifyAttestation } from "./attestation";

/**
 * App Attest storage and request checks. The app attests one key per install
 * (`POST /v1/app-attest/keys`), then signs each device registration with it.
 * Every attestation and assertion embeds a one-time challenge from
 * `POST /v1/app-attest/challenges`, as Apple asks.
 */

const CHALLENGE_TTL_MS = 5 * 60 * 1000;

/** Request headers that carry an assertion. */
export const HEADERS = {
  keyId: "X-App-Attest-Key-Id",
  assertion: "X-App-Attest-Assertion",
  challenge: "X-App-Attest-Challenge",
} as const;

/** App ID the attested keys belong to: App ID prefix (the team ID), a period, the bundle ID. */
export function appId(env: Env): string {
  return `${env.APNS_TEAM_ID}.${env.APNS_TOPIC}`;
}

/** 32 random bytes, base64url, stored until used or expired. */
export async function issueChallenge(db: D1Database, now: number): Promise<string> {
  const challenge = toBase64(crypto.getRandomValues(new Uint8Array(32)))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
  await db.prepare("INSERT INTO challenges (value, expires_at) VALUES (?1, ?2)").bind(challenge, now + CHALLENGE_TTL_MS).run();
  return challenge;
}

/** Deletes the challenge and tells whether it was still valid: each challenge works once. */
async function consumeChallenge(db: D1Database, challenge: string, now: number): Promise<boolean> {
  const row = await db
    .prepare("DELETE FROM challenges WHERE value = ?1 RETURNING expires_at AS expiresAt")
    .bind(challenge)
    .first<{ expiresAt: number }>();
  return row !== null && row.expiresAt > now;
}

export async function pruneChallenges(db: D1Database, now: number): Promise<void> {
  await db.prepare("DELETE FROM challenges WHERE expires_at <= ?1").bind(now).run();
}

export type Failure = { status: 400 | 401; error: string };

/** Verifies and stores a new key. Body: `{ keyId, attestation, challenge }`, binary fields in base64. */
export async function registerKey(env: Env, body: unknown, now: number): Promise<Failure | undefined> {
  if (typeof body !== "object" || body === null) return { status: 400, error: "body must be a JSON object" };
  const { keyId, attestation, challenge } = body as Record<string, unknown>;
  if (typeof keyId !== "string" || typeof attestation !== "string" || typeof challenge !== "string") {
    return { status: 400, error: "keyId, attestation and challenge must be strings" };
  }
  const keyBytes = decodeBase64(keyId);
  const attestationBytes = decodeBase64(attestation);
  if (keyBytes?.length !== 32 || !attestationBytes) return { status: 400, error: "invalid base64" };
  if (!(await consumeChallenge(env.DB, challenge, now))) return { status: 401, error: "invalid challenge" };

  try {
    const key = await verifyAttestation({
      attestation: attestationBytes,
      keyId: keyBytes,
      clientDataHash: await sha256(new TextEncoder().encode(challenge)),
      appId: appId(env),
      now,
    });
    // Apple: make sure the key isn't already associated, so an attestation can't be replayed.
    const inserted = await env.DB.prepare(
      `INSERT INTO app_attest_keys (key_id, public_key, environment, counter, receipt, validation_category, bundle_version, created_at)
       VALUES (?1, ?2, ?3, 0, ?4, ?5, ?6, ?7) ON CONFLICT (key_id) DO NOTHING`,
    )
      .bind(
        toBase64(keyBytes),
        toBase64(key.publicKey),
        key.environment,
        toBase64(key.receipt),
        key.validationCategory ?? null,
        key.bundleVersion ?? null,
        now,
      )
      .run();
    if (inserted.meta.changes !== 1) return { status: 401, error: "key already attested" };
    return undefined;
  } catch (error) {
    if (error instanceof AttestationError) return { status: 401, error: `attestation rejected: ${error.message}` };
    throw error;
  }
}

/**
 * The bytes the app signs for a request: the challenge, the method and path,
 * then the raw body, so the assertion covers the whole request.
 */
export function clientData(challenge: string, method: string, path: string, body: Uint8Array): Uint8Array {
  const head = new TextEncoder().encode(`${challenge}\n${method} ${path}\n`);
  const result = new Uint8Array(head.length + body.length);
  result.set(head);
  result.set(body, head.length);
  return result;
}

/**
 * Checks the assertion on a request and returns the key identifier that signed
 * it. "unknown key" tells the app to attest a new key.
 */
export async function authorize(
  env: Env,
  request: Request,
  body: Uint8Array,
  now: number,
): Promise<{ keyId: string } | Failure> {
  const keyBytes = decodeBase64(request.headers.get(HEADERS.keyId) ?? "");
  const keyId = keyBytes && toBase64(keyBytes);
  const assertion = decodeBase64(request.headers.get(HEADERS.assertion) ?? "");
  const challenge = request.headers.get(HEADERS.challenge);
  if (!keyId || !assertion || !challenge) return { status: 401, error: "missing assertion" };

  const key = await env.DB.prepare("SELECT public_key AS publicKey, counter FROM app_attest_keys WHERE key_id = ?1")
    .bind(keyId)
    .first<{ publicKey: string; counter: number }>();
  if (!key) return { status: 401, error: "unknown key" };
  if (!(await consumeChallenge(env.DB, challenge, now))) return { status: 401, error: "invalid challenge" };

  let counter: number;
  try {
    counter = await verifyAssertion({
      assertion,
      clientData: clientData(challenge, request.method, new URL(request.url).pathname, body),
      publicKey: fromBase64(key.publicKey),
      appId: appId(env),
      previousCounter: key.counter,
    });
  } catch (error) {
    if (error instanceof AttestationError) return { status: 401, error: `assertion rejected: ${error.message}` };
    throw error;
  }
  // Conditional update: of two requests racing with the same key, only the newer counter wins.
  const updated = await env.DB.prepare("UPDATE app_attest_keys SET counter = ?1, used_at = ?2 WHERE key_id = ?3 AND counter < ?1")
    .bind(counter, now, keyId)
    .run();
  if (updated.meta.changes !== 1) return { status: 401, error: "assertion rejected: counter did not increase" };
  return { keyId };
}

function decodeBase64(text: string): Uint8Array | undefined {
  try {
    return text.length > 0 ? fromBase64(text) : undefined;
  } catch {
    return undefined;
  }
}
