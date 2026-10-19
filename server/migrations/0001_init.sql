-- Devices that accept push alerts.
CREATE TABLE devices (
  token TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  -- Comma-separated IBU category ids: SM (men), SW (women), MX (mixed).
  categories TEXT NOT NULL,
  cancellation INTEGER NOT NULL,
  rescheduling INTEGER NOT NULL,
  locale TEXT NOT NULL,
  time_zone TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Last known state of each watched race, to detect changes between polls.
CREATE TABLE races (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  start_time TEXT NOT NULL,
  status TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Pushes waiting to be sent, drained a few at a time by the cron.
CREATE TABLE outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT NOT NULL,
  environment TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('cancelled', 'rescheduled')),
  race_id TEXT NOT NULL,
  race_name TEXT NOT NULL,
  start_time TEXT NOT NULL,
  locale TEXT NOT NULL,
  time_zone TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Small key-value store: cached APNs provider token and IBU calendar.
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
