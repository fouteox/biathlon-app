-- App Attest keys, one per app install (see src/keys.ts).
CREATE TABLE app_attest_keys (
  -- Base64 key identifier from DCAppAttestService.generateKey.
  key_id TEXT PRIMARY KEY,
  -- Base64 X9.62 uncompressed P-256 point from the credential certificate.
  public_key TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('development', 'production')),
  -- Counter of the last accepted assertion.
  counter INTEGER NOT NULL,
  -- Base64 receipt, kept for Apple's fraud metric.
  receipt TEXT NOT NULL,
  validation_category INTEGER,
  bundle_version TEXT,
  created_at INTEGER NOT NULL,
  used_at INTEGER
);

-- Registrations made before App Attest carry no proof: drop them. Each device
-- registers again, with an attested key, at the next launch of the app.
DELETE FROM outbox;
DELETE FROM devices;

ALTER TABLE devices ADD COLUMN app_attest_key_id TEXT REFERENCES app_attest_keys (key_id);
CREATE INDEX devices_by_app_attest_key ON devices (app_attest_key_id);
