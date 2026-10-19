-- APNs broadcast channels of the races' Live Activities (see src/live.ts):
-- one per race and APNs environment, deleted a while after the race is over.
CREATE TABLE live_channels (
  race_id TEXT NOT NULL REFERENCES races (id),
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  -- Base64 identifier from the apns-channel-id response header.
  channel_id TEXT NOT NULL,
  -- Last content-state published on the channel, as JSON.
  state TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  -- When the end event was first sent, then last sent; NULL while the race is followed.
  ended_at INTEGER,
  end_sent_at INTEGER,
  PRIMARY KEY (race_id, environment)
);

-- Channels created by a cron run that an overlapping run beat to the race's row:
-- deleted at APNs by a later run, since channels are limited to 10,000.
CREATE TABLE orphaned_channels (
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  channel_id TEXT NOT NULL,
  PRIMARY KEY (environment, channel_id)
);
