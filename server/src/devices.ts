import type { APNsEnvironment } from "./apns";

export const CATEGORIES = ["SM", "SW", "MX"] as const;
export type Category = (typeof CATEGORIES)[number];

export interface DeviceRegistration {
  token: string;
  environment: APNsEnvironment;
  categories: Category[];
  cancellation: boolean;
  rescheduling: boolean;
  locale: string;
  timeZone: string;
}

/** Apple: "Don't make assumptions about device token size." It is hex, though. */
const TOKEN_PATTERN = /^[0-9a-f]{32,512}$/;

export function isDeviceToken(value: unknown): value is string {
  return typeof value === "string" && TOKEN_PATTERN.test(value);
}

/** Validates the JSON body of `PUT /v1/devices/:token`. */
export function parseRegistration(token: string, body: unknown): DeviceRegistration | string {
  const normalized = token.toLowerCase();
  if (!isDeviceToken(normalized)) return "invalid device token";
  if (typeof body !== "object" || body === null) return "body must be a JSON object";
  const input = body as Record<string, unknown>;
  if (input.environment !== "sandbox" && input.environment !== "production") return "invalid environment";
  if (!Array.isArray(input.categories) || !input.categories.every((c) => CATEGORIES.includes(c))) {
    return "invalid categories";
  }
  if (typeof input.cancellation !== "boolean" || typeof input.rescheduling !== "boolean") {
    return "cancellation and rescheduling must be booleans";
  }
  const locale = typeof input.locale === "string" && input.locale.length <= 35 ? input.locale : "en";
  const timeZone = typeof input.timeZone === "string" && input.timeZone.length <= 64 ? input.timeZone : "UTC";
  return {
    token: normalized,
    environment: input.environment,
    categories: [...new Set(input.categories as Category[])],
    cancellation: input.cancellation,
    rescheduling: input.rescheduling,
    locale,
    timeZone,
  };
}

export async function saveDevice(db: D1Database, device: DeviceRegistration, now: number): Promise<void> {
  await db
    .prepare(
      `INSERT INTO devices (token, environment, categories, cancellation, rescheduling, locale, time_zone, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
       ON CONFLICT (token) DO UPDATE SET
         environment = excluded.environment, categories = excluded.categories,
         cancellation = excluded.cancellation, rescheduling = excluded.rescheduling,
         locale = excluded.locale, time_zone = excluded.time_zone, updated_at = excluded.updated_at`,
    )
    .bind(
      device.token,
      device.environment,
      device.categories.join(","),
      device.cancellation ? 1 : 0,
      device.rescheduling ? 1 : 0,
      device.locale,
      device.timeZone,
      now,
    )
    .run();
}

export async function deleteDevice(db: D1Database, token: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM devices WHERE token = ?1").bind(token),
    db.prepare("DELETE FROM outbox WHERE token = ?1").bind(token),
  ]);
}
