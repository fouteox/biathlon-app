-- Device categories become a JSON array, read with json_each like the favorites of
-- live_start_tokens. The server writes them so since 2026-10-25 and read both forms until
-- this migration: it converts the rows still comma-separated.
UPDATE devices
SET categories = CASE WHEN categories = '' THEN '[]' ELSE '["' || replace(categories, ',', '","') || '"]' END
WHERE NOT json_valid(categories);
