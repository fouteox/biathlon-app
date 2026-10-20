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
-- ActivityKit can replace: started (or being started) when one of their favorites is on its
-- start list, so each install gets at most one start per race. Changed favorites check
-- again the races that started nothing; a race reinstated after its end, every install.
CREATE TABLE live_starts (
  race_id TEXT NOT NULL REFERENCES races (id),
  app_attest_key_id TEXT NOT NULL REFERENCES app_attest_keys (key_id) ON DELETE CASCADE,
  started INTEGER NOT NULL CHECK (started IN (0, 1)),
  PRIMARY KEY (race_id, app_attest_key_id)
);
