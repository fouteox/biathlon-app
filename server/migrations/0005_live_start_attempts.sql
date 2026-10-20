-- Counts the failed sends of each Live Activity start (see src/liveStarts.ts), which stops
-- being retried after a few: a lasting APNs outage would otherwise claim then give back the
-- same rows every minute, spending the day's D1 row writes of the Workers Free plan.
-- SQLite can't change a CHECK constraint in place: the table is rebuilt, a start given back
-- keeping its row with neither a channel nor entrants.
CREATE TABLE live_starts_with_attempts (
  race_id TEXT NOT NULL REFERENCES races (id),
  app_attest_key_id TEXT NOT NULL REFERENCES app_attest_keys (key_id) ON DELETE CASCADE,
  -- The channel the activity was started on, which a failed start gives back only while it
  -- is the one claimed; NULL when none of the favorites was on the start list, or when the
  -- start failed.
  channel_id TEXT,
  -- When none was: the SHA-256 of the entrants checked against.
  entrants TEXT,
  -- The sends of the start that failed and are to be retried.
  attempts INTEGER NOT NULL DEFAULT 0,
  CHECK (channel_id IS NULL OR entrants IS NULL),
  PRIMARY KEY (race_id, app_attest_key_id)
);
INSERT INTO live_starts_with_attempts (race_id, app_attest_key_id, channel_id, entrants)
  SELECT race_id, app_attest_key_id, channel_id, entrants FROM live_starts;
DROP TABLE live_starts;
ALTER TABLE live_starts_with_attempts RENAME TO live_starts;
