import { fromBase64, toBase64 } from "./attestation";

/**
 * Stateless App Attest challenges: `<purpose>.<issued ms>.<random>.<HMAC>`,
 * signed with the `APP_ATTEST_SECRET` secret. Issuing one costs no storage,
 * so the public endpoint can't be used to fill D1.
 *
 * Replays stay rejected without remembering challenges: an attestation is
 * accepted once per key (keys.ts inserts it once), and an assertion only when
 * its counter grows.
 */

const LIFETIME_MS = {
  // Long enough to retry an attestation with the same clientDataHash, as Apple
  // asks after a `serverUnavailable` error.
  attest: 24 * 60 * 60 * 1000,
  assert: 5 * 60 * 1000,
} as const;

/** Tolerated clock difference between Worker locations. */
const CLOCK_SKEW_MS = 60 * 1000;

export type Purpose = keyof typeof LIFETIME_MS;

export function isPurpose(value: unknown): value is Purpose {
  return value === "attest" || value === "assert";
}

export async function issueChallenge(secret: string, purpose: Purpose, now: number): Promise<string> {
  const payload = `${purpose}.${now}.${base64url(crypto.getRandomValues(new Uint8Array(16)))}`;
  const mac = await crypto.subtle.sign("HMAC", await hmacKey(secret), new TextEncoder().encode(payload));
  return `${payload}.${base64url(new Uint8Array(mac))}`;
}

/** Tells whether `challenge` was issued here for `purpose` and is still valid. */
export async function checkChallenge(secret: string, challenge: string, purpose: Purpose, now: number): Promise<boolean> {
  const separator = challenge.lastIndexOf(".");
  if (separator < 0) return false;
  const payload = challenge.slice(0, separator);
  const mac = fromBase64url(challenge.slice(separator + 1));
  if (!mac) return false;
  // crypto.subtle.verify compares the MAC in constant time.
  const valid = await crypto.subtle.verify("HMAC", await hmacKey(secret), mac, new TextEncoder().encode(payload));
  if (!valid) return false;
  const [kind, issued] = payload.split(".");
  const issuedAt = Number(issued);
  return kind === purpose && Number.isSafeInteger(issuedAt) && issuedAt <= now + CLOCK_SKEW_MS && now - issuedAt <= LIFETIME_MS[purpose];
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
    "verify",
  ]);
}

function base64url(data: Uint8Array): string {
  return toBase64(data).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64url(text: string): Uint8Array<ArrayBuffer> | undefined {
  if (!/^[A-Za-z0-9_-]+$/.test(text)) return undefined;
  const padded = text.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (text.length % 4)) % 4);
  try {
    return new Uint8Array(fromBase64(padded));
  } catch {
    return undefined;
  }
}
