-- APNs broadcast channels of the races' Live Activities (see src/live.ts):
-- one per race and APNs environment, deleted once the race is over.
CREATE TABLE live_channels (
  race_id TEXT NOT NULL REFERENCES races (id),
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  -- Base64 identifier from the apns-channel-id response header.
  channel_id TEXT NOT NULL,
  -- Last content-state published on the channel, as JSON.
  state TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (race_id, environment)
);
