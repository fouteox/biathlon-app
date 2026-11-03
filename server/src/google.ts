import { signJWT } from "./jwt";
import type { SubrequestBudget } from "./subrequests";

/**
 * Google APIs with a service account: Firebase Cloud Messaging and Play Integrity, through one
 * access token for both scopes. "Using OAuth 2.0 for Server to Server Applications"
 * (https://developers.google.com/identity/protocols/oauth2/service-account, read on 2026-11-03).
 */

/** The scopes of the token, space-delimited as Google asks. */
export const SCOPES = [
  "https://www.googleapis.com/auth/firebase.messaging",
  "https://www.googleapis.com/auth/playintegrity",
].join(" ");

const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";

/** Google: the assertion expires at most an hour after it is issued. */
const ASSERTION_LIFETIME_S = 60 * 60;

/** The fields of a service account's JSON key that sign and address the requests. */
export interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

/** Reads the `GOOGLE_SERVICE_ACCOUNT` secret: the JSON key file downloaded from the Google Cloud console. */
export function serviceAccount(secret: string): ServiceAccount {
  const key = JSON.parse(secret) as Record<string, unknown>;
  const { project_id: projectId, client_email: clientEmail, private_key: privateKey } = key;
  if (typeof projectId !== "string" || typeof clientEmail !== "string" || typeof privateKey !== "string") {
    throw new Error("GOOGLE_SERVICE_ACCOUNT lacks project_id, client_email or private_key");
  }
  return { projectId, clientEmail, privateKey };
}

export interface AccessToken {
  token: string;
  /** UNIX time in milliseconds. */
  expiresAt: number;
}

/** Trades a signed assertion for an access token; throws on any failure, which a later request retries. */
export async function fetchAccessToken(
  account: ServiceAccount,
  now: number,
  signal?: AbortSignal,
): Promise<AccessToken> {
  const issuedAt = Math.floor(now / 1000);
  const assertion = await signJWT(
    "RS256",
    account.privateKey,
    { typ: "JWT" },
    {
      iss: account.clientEmail,
      scope: SCOPES,
      aud: TOKEN_ENDPOINT,
      iat: issuedAt,
      exp: issuedAt + ASSERTION_LIFETIME_S,
    },
  );
  const response = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
    signal,
  });
  if (!response.ok) throw new Error(`Google token endpoint: ${response.status} ${await response.text()}`);
  const { access_token: token, expires_in: expiresIn } = await response.json<{
    access_token?: string;
    expires_in?: number;
  }>();
  if (typeof token !== "string" || typeof expiresIn !== "number")
    throw new Error("Google token endpoint: malformed response");
  return { token, expiresAt: now + expiresIn * 1000 };
}

/** A token is no longer handed out this close to its expiry, so a request never carries an expired one. */
const EXPIRY_MARGIN_MS = 5 * 60 * 1000;

const CACHE_KEY = "google_access_token";

/**
 * The access token cached in D1 while it stays valid, or a new one, cached for the next requests:
 * Google lets a token be reused until it expires. `refresh` fetches a new one, as after Google
 * rejected the cached token. A cron run's fetch spends a subrequest of its `budget`, and throws
 * once none is left.
 */
export async function accessToken(
  env: Pick<Env, "DB" | "GOOGLE_SERVICE_ACCOUNT">,
  now: number,
  options: { refresh?: boolean; budget?: SubrequestBudget } = {},
): Promise<string> {
  if (!options.refresh) {
    const cached = await env.DB.prepare("SELECT value FROM settings WHERE key = ?1")
      .bind(CACHE_KEY)
      .first<{ value: string }>();
    const token = cached && (JSON.parse(cached.value) as AccessToken);
    if (token && token.expiresAt - now > EXPIRY_MARGIN_MS) return token.token;
  }
  const { budget } = options;
  if (budget && !budget.take()) throw new Error("no subrequest left for a Google access token");
  const token = await fetchAccessToken(serviceAccount(env.GOOGLE_SERVICE_ACCOUNT), now, budget?.signal());
  await env.DB.prepare(
    `INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
     ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  )
    .bind(CACHE_KEY, JSON.stringify(token), now)
    .run();
  return token.token;
}
