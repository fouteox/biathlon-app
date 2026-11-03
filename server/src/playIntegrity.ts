import { sha256 } from "./attestation";
import { accessToken } from "./google";
import { base64url } from "./jwt";

/**
 * Play Integrity standard requests (https://developer.android.com/google/play/integrity/standard and
 * …/verdicts, read on 2026-11-03), the Android counterpart of App Attest: each registration of an
 * Android device carries an integrity token bound to the request by its `requestHash`. Google
 * decrypts the token and protects standard requests against replay itself.
 */

/** Request header that carries the token. */
export const HEADER = "X-Play-Integrity-Token";

/** How old a token may be, and how far ahead of this server's clock. */
const MAX_AGE_MS = 5 * 60 * 1000;
const CLOCK_SKEW_MS = 60 * 1000;

/**
 * The `requestHash` the app sets on its token: the unpadded base64url SHA-256 of the method, the
 * path and the raw body, as App Attest assertions cover the whole request.
 */
export async function requestHash(method: string, path: string, body: Uint8Array): Promise<string> {
  const head = new TextEncoder().encode(`${method} ${path}\n`);
  const bytes = new Uint8Array(head.length + body.length);
  bytes.set(head);
  bytes.set(body, head.length);
  return base64url(await sha256(bytes));
}

/** The decrypted payload's fields this server reads; Google gives no order. */
export interface Verdict {
  requestDetails?: { requestPackageName?: string; requestHash?: string; timestampMillis?: string };
  appIntegrity?: { appRecognitionVerdict?: string; packageName?: string; versionCode?: string };
  deviceIntegrity?: { deviceRecognitionVerdict?: string[] };
}

/**
 * Why the verdict is refused, or `undefined` when it vouches for this request from this app,
 * distributed by Google Play, on a genuine and certified device, in a version still supported.
 */
export function refusal(
  verdict: Verdict,
  expected: { packageName: string; requestHash: string; minVersionCode: number; now: number },
): string | undefined {
  // Google: check the request details first.
  const { requestDetails: request, appIntegrity: app, deviceIntegrity: device } = verdict;
  if (request?.requestPackageName !== expected.packageName) return "package mismatch";
  if (request.requestHash !== expected.requestHash) return "request hash mismatch";
  const age = expected.now - Number(request.timestampMillis);
  if (!(age <= MAX_AGE_MS && age >= -CLOCK_SKEW_MS)) return "token too old";
  if (app?.appRecognitionVerdict !== "PLAY_RECOGNIZED" || app.packageName !== expected.packageName) {
    return "app not recognized by Google Play";
  }
  if (!(Number(app.versionCode) >= expected.minVersionCode)) return `version ${app.versionCode} no longer supported`;
  if (!device?.deviceRecognitionVerdict?.includes("MEETS_DEVICE_INTEGRITY")) return "device integrity not met";
  return undefined;
}

export type Failure = { status: 401 | 503; error: string };

/** Checks the integrity token of a request whose raw body is `body`. */
export async function checkIntegrity(
  env: Env,
  request: Request,
  body: Uint8Array,
  now: number,
): Promise<Failure | undefined> {
  const token = request.headers.get(HEADER);
  if (!token) return { status: 401, error: "missing integrity token" };
  const packageName = env.ANDROID_PACKAGE_NAME;
  let verdict: Verdict | undefined;
  try {
    verdict = await decode(env, packageName, token, now);
  } catch (error) {
    console.error("Play Integrity unavailable", error);
    return { status: 503, error: "integrity check unavailable" };
  }
  if (!verdict) return { status: 401, error: "integrity token rejected" };
  const reason = refusal(verdict, {
    packageName,
    requestHash: await requestHash(request.method, new URL(request.url).pathname, body),
    minVersionCode: Number(env.PLAY_INTEGRITY_MIN_VERSION_CODE),
    now,
  });
  return reason ? { status: 401, error: `integrity verdict rejected: ${reason}` } : undefined;
}

/**
 * Has Google decrypt the token: the verdict, or `undefined` for a token Google refuses (400).
 * Throws when Google can't be reached or fails, with the access token signed again once if
 * Google rejects it.
 */
async function decode(env: Env, packageName: string, token: string, now: number): Promise<Verdict | undefined> {
  const call = async (refresh: boolean) =>
    fetch(`https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${await accessToken(env, now, { refresh })}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ integrityToken: token }),
    });
  let response = await call(false);
  if (response.status === 401) response = await call(true);
  if (response.status === 400) return undefined;
  if (!response.ok) throw new Error(`decodeIntegrityToken: ${response.status} ${await response.text()}`);
  return (await response.json<{ tokenPayloadExternal?: Verdict }>()).tokenPayloadExternal ?? {};
}
