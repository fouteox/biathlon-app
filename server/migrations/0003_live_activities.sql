-- APNs broadcast channels of the races' Live Activities (see src/live.ts):
-- one per race and APNs environment, deleted at APNs a while after the race is over.
CREATE TABLE live_channels (
  race_id TEXT NOT NULL REFERENCES races (id),
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  -- Base64 identifier from the apns-channel-id response header.
  channel_id TEXT NOT NULL,
  -- Last content-state published on the channel, as JSON.
  state TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  -- When the activity ended, NULL while the race is followed; when its end event was last
  -- sent, NULL until it goes through.
  ended_at INTEGER,
  end_sent_at INTEGER,
  -- When the channel was deleted at APNs, or found unknown there: the row stays, for the
  -- app to learn the activity is over, or for a new channel to replace it while the race is followed.
  deleted_at INTEGER,
  -- When a run last looked up the race's results for it, then last tried to send its end
  -- again: the least recent go first, so a short subrequest budget takes turns among them.
  attempted_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (race_id, environment)
);

-- Channels waiting for their deletion at APNs, a few per run (channels are limited to
-- 10,000): those of races over or reinstated, and those a cron run created after an
-- overlapping run had recorded one.
CREATE TABLE retired_channels (
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  channel_id TEXT NOT NULL,
  -- When its deletion last failed: the oldest attempts go first, so failures can't hold the others back.
  attempted_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (environment, channel_id)
);
