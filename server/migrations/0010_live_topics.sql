-- Each race's FCM topic, which stands for its broadcast channel on Android (see src/live.ts), is
-- recorded next to its APNs channels, `environment` 'fcm' and `channel_id` the topic's name.
-- SQLite can't change a column's constraints in place: the table is rebuilt, its rows kept.
CREATE TABLE live_channels_with_topics (
  race_id TEXT NOT NULL REFERENCES races (id),
  -- The APNs environment of the channel, or 'fcm' for the race's topic.
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production', 'fcm')),
  -- Base64 identifier from the apns-channel-id response header, or the topic's name.
  channel_id TEXT NOT NULL,
  state TEXT NOT NULL,
  published_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  ended_at INTEGER,
  end_sent_at INTEGER,
  deleted_at INTEGER,
  attempted_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (race_id, environment)
);
INSERT INTO live_channels_with_topics
  (race_id, environment, channel_id, state, published_at, created_at, ended_at, end_sent_at, deleted_at, attempted_at)
  SELECT race_id, environment, channel_id, state, published_at, created_at, ended_at, end_sent_at, deleted_at, attempted_at
  FROM live_channels;
DROP TABLE live_channels;
ALTER TABLE live_channels_with_topics RENAME TO live_channels;
