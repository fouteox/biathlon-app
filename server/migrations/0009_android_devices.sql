-- Android devices, which Firebase Cloud Messaging reaches by their Firebase Installation ID
-- (see src/fcm.ts), share the devices and the outbox with the iOS ones. They have no APNs
-- environment and no App Attest key: Play Integrity checks each of their registrations instead.
-- SQLite can't change a column's constraints in place: both tables are rebuilt, their rows
-- kept as iOS ones. `platform` defaults to 'ios' for the code still deployed while the
-- migration runs, which doesn't name it.
CREATE TABLE devices_with_platform (
  -- An APNs device token (hex) or a Firebase Installation ID.
  token TEXT PRIMARY KEY,
  platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android')),
  environment TEXT CHECK (environment IN ('sandbox', 'production')),
  -- JSON array of IBU category ids: SM (men), SW (women), MX (mixed).
  categories TEXT NOT NULL,
  cancellation INTEGER NOT NULL,
  rescheduling INTEGER NOT NULL,
  locale TEXT NOT NULL,
  time_zone TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  app_attest_key_id TEXT REFERENCES app_attest_keys (key_id),
  CHECK ((platform = 'ios') = (environment IS NOT NULL)),
  CHECK (platform = 'ios' OR app_attest_key_id IS NULL)
);
INSERT INTO devices_with_platform
  (token, platform, environment, categories, cancellation, rescheduling, locale, time_zone, updated_at, app_attest_key_id)
  SELECT token, 'ios', environment, categories, cancellation, rescheduling, locale, time_zone, updated_at, app_attest_key_id
  FROM devices;
DROP TABLE devices;
ALTER TABLE devices_with_platform RENAME TO devices;
CREATE INDEX devices_by_app_attest_key ON devices (app_attest_key_id);

CREATE TABLE outbox_with_platform (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform IN ('ios', 'android')),
  environment TEXT CHECK (environment IN ('sandbox', 'production')),
  kind TEXT NOT NULL CHECK (kind IN ('cancelled', 'rescheduled')),
  race_id TEXT NOT NULL,
  race_name TEXT NOT NULL,
  start_time TEXT NOT NULL,
  locale TEXT NOT NULL,
  time_zone TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  CHECK ((platform = 'ios') = (environment IS NOT NULL))
);
INSERT INTO outbox_with_platform
  (id, token, platform, environment, kind, race_id, race_name, start_time, locale, time_zone, attempts, created_at)
  SELECT id, token, 'ios', environment, kind, race_id, race_name, start_time, locale, time_zone, attempts, created_at
  FROM outbox;
DROP TABLE outbox;
ALTER TABLE outbox_with_platform RENAME TO outbox;
