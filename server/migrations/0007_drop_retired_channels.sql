-- Each race's Durable Object (src/raceActivity.ts) keeps the channels left to delete at APNs
-- in its own storage since 2026-10-25: no deployed code reads this table any more.
DROP TABLE retired_channels;
