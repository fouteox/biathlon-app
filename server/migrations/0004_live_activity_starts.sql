-- Push-to-start tokens of the devices that start a race's Live Activity when one of their
-- favorites races (see src/liveStarts.ts): sent by the app only while the user turned it on.
CREATE TABLE live_start_tokens (
  -- Hex token from ActivityKit's pushToStartTokenUpdates.
  token TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  -- JSON arrays of the favorite athletes' IBU ids and of the favorite nations' IOC codes.
  athletes TEXT NOT NULL,
  nations TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  -- One token per App Attest key, like the devices table.
  app_attest_key_id TEXT NOT NULL REFERENCES app_attest_keys (key_id)
);
CREATE INDEX live_start_tokens_by_app_attest_key ON live_start_tokens (app_attest_key_id);

-- The installs a race was checked for, by App Attest key rather than by token, which
-- ActivityKit can replace: started (or being started) on a channel when one of their
-- favorites is on its start list, so each install gets one start per channel of the race. Changed
-- favorites, or a changed start list, check again the races that started nothing; a new
-- channel for the race (replacing a dropped one, or reinstating the race), the starts too.
CREATE TABLE live_starts (
  race_id TEXT NOT NULL REFERENCES races (id),
  app_attest_key_id TEXT NOT NULL REFERENCES app_attest_keys (key_id) ON DELETE CASCADE,
  -- The channel the activity was started on, which a failed start releases only while it
  -- is the one claimed; NULL when none of the favorites was on the start list.
  channel_id TEXT,
  -- When none was: the SHA-256 of the entrants checked against.
  entrants TEXT,
  CHECK ((channel_id IS NULL) <> (entrants IS NULL)),
  PRIMARY KEY (race_id, app_attest_key_id)
);
