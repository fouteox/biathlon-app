-- The races a device follows on the Lock Screen (see src/liveStarts.ts): the server starts
-- their Live Activities like those of the favorites' races, whenever the user turned them on,
-- without waiting for a start list. A JSON array of IBU race ids; empty for app versions
-- that only send favorites.
ALTER TABLE live_start_tokens ADD COLUMN races TEXT NOT NULL DEFAULT '[]';
