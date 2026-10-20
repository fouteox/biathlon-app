import { AttestationError, fromBase64, sha256, toBase64, verifyAssertion, verifyAttestation } from "./attestation";
import { checkChallenge } from "./challenges";

/**
 * App Attest storage and request checks. The app attests one key per install
 * (`POST /v1/app-attest/keys`), then signs each device registration with it.
 * Every attestation and assertion embeds a challenge from
 * `POST /v1/app-attest/challenges?purpose=attest|assert` (challenges.ts).
 */

/** Request headers that carry an assertion. */
export const HEADERS = {
  keyId: "X-App-Attest-Key-Id",
  assertion: "X-App-Attest-Assertion",
  challenge: "X-App-Attest-Challenge",
} as const;

/** Keys no device uses are deleted after this long; their app attests a new key if it comes back. */
const UNUSED_KEY_LIFETIME_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Deletes keys that no device or push-to-start token references and that signed nothing
 * for 30 days: reinstalls, device migrations and restores leave such keys behind.
 */
export async function pruneKeys(db: D1Database, now: number): Promise<void> {
  await db
    .prepare(
      `DELETE FROM app_attest_keys
       WHERE COALESCE(used_at, created_at) < ?1
         AND key_id NOT IN (SELECT app_attest_key_id FROM devices WHERE app_attest_key_id IS NOT NULL)
         AND key_id NOT IN (SELECT app_attest_key_id FROM live_start_tokens)`,
    )
    .bind(now - UNUSED_KEY_LIFETIME_MS)
    .run();
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
  if (!(await checkChallenge(env.APP_ATTEST_SECRET, challenge, "attest", now))) {
    return { status: 401, error: "invalid challenge" };
  }

  try {
    const key = await verifyAttestation({
      attestation: attestationBytes,
      keyId: keyBytes,
      clientDataHash: await sha256(new TextEncoder().encode(challenge)),
      appId: env.APP_ATTEST_APP_ID,
      now,
      minBundleVersion: env.APP_ATTEST_MIN_BUNDLE_VERSION,
    });
    // Apple: make sure the key isn't already associated. This also stops replayed attestations.
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
  // Checked first: it needs no D1 query.
  if (!(await checkChallenge(env.APP_ATTEST_SECRET, challenge, "assert", now))) {
    return { status: 401, error: "invalid challenge" };
  }

  const key = await env.DB.prepare("SELECT public_key AS publicKey, counter FROM app_attest_keys WHERE key_id = ?1")
    .bind(keyId)
    .first<{ publicKey: string; counter: number }>();
  if (!key) return { status: 401, error: "unknown key" };

  let counter: number;
  try {
    counter = await verifyAssertion({
      assertion,
      clientData: clientData(challenge, request.method, new URL(request.url).pathname, body),
      publicKey: fromBase64(key.publicKey),
      appId: env.APP_ATTEST_APP_ID,
      previousCounter: key.counter,
      minBundleVersion: env.APP_ATTEST_MIN_BUNDLE_VERSION,
    });
  } catch (error) {
    if (error instanceof AttestationError) return { status: 401, error: `assertion rejected: ${error.message}` };
    throw error;
  }
  // The counter rejects replayed assertions. Conditional update: of two requests racing
  // with the same key, only the newer counter wins.
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
