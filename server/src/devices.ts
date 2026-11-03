import { isEnvironment, type APNsEnvironment } from "./apns";

export const CATEGORIES = ["SM", "SW", "MX"] as const;
export type Category = (typeof CATEGORIES)[number];

/** What a device asks to be alerted of, on either platform, and how to word it. */
export interface AlertPreferences {
  categories: Category[];
  cancellation: boolean;
  rescheduling: boolean;
  locale: string;
  timeZone: string;
}

export interface DeviceRegistration extends AlertPreferences {
  token: string;
  environment: APNsEnvironment;
}

/** An Android device, by its Firebase Installation ID. */
export interface AndroidRegistration extends AlertPreferences {
  fid: string;
}

/** Apple: "Don't make assumptions about device token size." It is hex, though. */
const TOKEN_PATTERN = /^[0-9a-f]{32,512}$/;

export function isDeviceToken(value: unknown): value is string {
  return typeof value === "string" && TOKEN_PATTERN.test(value);
}

/** Validates the JSON body of `PUT /v1/devices/:token`, for a token `isDeviceToken` accepted. */
export function parseRegistration(token: string, body: unknown): DeviceRegistration | string {
  if (typeof body !== "object" || body === null) return "body must be a JSON object";
  const { environment } = body as Record<string, unknown>;
  if (!isEnvironment(environment)) return "invalid environment";
  const preferences = parsePreferences(body);
  return typeof preferences === "string" ? preferences : { token, environment, ...preferences };
}

/** Validates the JSON body of `PUT /v1/android-devices/:fid`, for an ID `isInstallationId` accepted. */
export function parseAndroidRegistration(fid: string, body: unknown): AndroidRegistration | string {
  const preferences = parsePreferences(body);
  return typeof preferences === "string" ? preferences : { fid, ...preferences };
}

function parsePreferences(body: unknown): AlertPreferences | string {
  if (typeof body !== "object" || body === null) return "body must be a JSON object";
  const input = body as Record<string, unknown>;
  if (!Array.isArray(input.categories) || !input.categories.every((c) => CATEGORIES.includes(c))) {
    return "invalid categories";
  }
  if (typeof input.cancellation !== "boolean" || typeof input.rescheduling !== "boolean") {
    return "cancellation and rescheduling must be booleans";
  }
  const locale = typeof input.locale === "string" && input.locale.length <= 35 ? input.locale : "en";
  const timeZone = typeof input.timeZone === "string" && input.timeZone.length <= 64 ? input.timeZone : "UTC";
  return {
    categories: [...new Set(input.categories as Category[])],
    cancellation: input.cancellation,
    rescheduling: input.rescheduling,
    locale,
    timeZone,
  };
}

/**
 * Saves the device for the App Attest key that signed the request. A key holds
 * one token: registering a new token (APNs issued another one) replaces the
 * previous token, so one attested install can't register many tokens.
 */
export async function saveDevice(
  db: D1Database,
  device: DeviceRegistration,
  keyId: string,
  now: number,
): Promise<void> {
  await db.batch([
    db
      .prepare(
        "DELETE FROM outbox WHERE token IN (SELECT token FROM devices WHERE app_attest_key_id = ?1 AND token <> ?2)",
      )
      .bind(keyId, device.token),
    db.prepare("DELETE FROM devices WHERE app_attest_key_id = ?1 AND token <> ?2").bind(keyId, device.token),
    db
      .prepare(
        `INSERT INTO devices (token, platform, environment, categories, cancellation, rescheduling, locale, time_zone, updated_at, app_attest_key_id)
         VALUES (?1, 'ios', ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT (token) DO UPDATE SET
           environment = excluded.environment, categories = excluded.categories,
           cancellation = excluded.cancellation, rescheduling = excluded.rescheduling,
           locale = excluded.locale, time_zone = excluded.time_zone, updated_at = excluded.updated_at,
           app_attest_key_id = excluded.app_attest_key_id
         WHERE devices.platform = 'ios'
           AND (devices.app_attest_key_id IS NULL OR devices.app_attest_key_id = excluded.app_attest_key_id)`,
      )
      .bind(
        device.token,
        device.environment,
        JSON.stringify(device.categories),
        device.cancellation ? 1 : 0,
        device.rescheduling ? 1 : 0,
        device.locale,
        device.timeZone,
        now,
        keyId,
      ),
  ]);
}

/**
 * Whether `keyId` may change the registration of `token`: a token belongs to the
 * key that registered it. Apple: the token changes when the app is reinstalled,
 * the device is restored or migrated, the same events that end an App Attest key,
 * so a new key never needs a token an older key holds (Apple engineer, March 2026:
 * https://developer.apple.com/forums/thread/818187).
 * A row without a key, written before App Attest, goes to the first key that claims it.
 * `saveDevice` and `deleteOwnedDevice` repeat this check in their own statements, so a
 * request racing with another key's can't slip between the check and the write.
 */
export async function ownsDevice(db: D1Database, token: string, keyId: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT platform, app_attest_key_id AS keyId FROM devices WHERE token = ?1")
    .bind(token)
    .first<{ platform: string; keyId: string | null }>();
  return row === null || (row.platform === "ios" && (row.keyId === null || row.keyId === keyId));
}

/** Deletes the tokens APNs reported as no longer valid, with their queued alerts. */
export async function deleteDevices(db: D1Database, tokens: string[]): Promise<void> {
  const list = JSON.stringify(tokens);
  await db.batch([
    db.prepare("DELETE FROM devices WHERE token IN (SELECT value FROM json_each(?1))").bind(list),
    db.prepare("DELETE FROM outbox WHERE token IN (SELECT value FROM json_each(?1))").bind(list),
  ]);
}

/** Deletes `token` on behalf of `keyId`, only if that key may (see `ownsDevice`). */
export async function deleteOwnedDevice(db: D1Database, token: string, keyId: string): Promise<void> {
  const owned =
    "SELECT token FROM devices WHERE token = ?1 AND platform = 'ios' AND (app_attest_key_id IS NULL OR app_attest_key_id = ?2)";
  await db.batch([
    // The outbox first: its condition reads the device row.
    db.prepare(`DELETE FROM outbox WHERE token IN (${owned})`).bind(token, keyId),
    db.prepare(`DELETE FROM devices WHERE token IN (${owned})`).bind(token, keyId),
  ]);
}

/**
 * Saves an Android device. Each registration carries its own Play Integrity verdict, and the
 * Firebase Installation ID is only known to its install: whoever registers it is its app. An
 * iOS device's token is never taken over.
 */
export async function saveAndroidDevice(db: D1Database, device: AndroidRegistration, now: number): Promise<void> {
  await db
    .prepare(
      `INSERT INTO devices (token, platform, categories, cancellation, rescheduling, locale, time_zone, updated_at)
       VALUES (?1, 'android', ?2, ?3, ?4, ?5, ?6, ?7)
       ON CONFLICT (token) DO UPDATE SET
         categories = excluded.categories, cancellation = excluded.cancellation, rescheduling = excluded.rescheduling,
         locale = excluded.locale, time_zone = excluded.time_zone, updated_at = excluded.updated_at
       WHERE devices.platform = 'android'`,
    )
    .bind(
      device.fid,
      JSON.stringify(device.categories),
      device.cancellation ? 1 : 0,
      device.rescheduling ? 1 : 0,
      device.locale,
      device.timeZone,
      now,
    )
    .run();
}

/** Deletes an Android device, with its queued alerts. */
export async function deleteAndroidDevice(db: D1Database, fid: string): Promise<void> {
  const owned = "SELECT token FROM devices WHERE token = ?1 AND platform = 'android'";
  await db.batch([
    db.prepare(`DELETE FROM outbox WHERE token IN (${owned})`).bind(fid),
    db.prepare(`DELETE FROM devices WHERE token IN (${owned})`).bind(fid),
  ]);
}
