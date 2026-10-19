# Biathlon server

Cloudflare Worker that:

- polls biathlonresults.com every minute (Cron Trigger) during World Cup events and detects cancelled races and start time changes;
- sends the matching alerts through APNs to registered devices (texts are localized on the device, see `src/payload.ts`);
- runs one Live Activity per race (`src/live.ts`): it opens an APNs broadcast channel per race and environment for the upcoming races, publishes each new state (start time, phase, first three) on it while the race runs, then ends the activity, sends the end again every 10 minutes for an hour for devices that were offline (the channels store no messages), and deletes the channel;
- exposes a read-only cache of the IBU API under `/ibu/`, which the app reads instead of biathlonresults.com. The Cache API also works on `*.workers.dev` (`cf-cache-status: HIT`, measured on 2026-10-19).

## API

| Method | Path | Body |
|---|---|---|
| `POST` | `/v1/app-attest/challenges?purpose=attest\|assert` | Returns `{"challenge":"…"}`, valid for a day (attest) or 5 minutes (assert). |
| `POST` | `/v1/app-attest/keys` | `{ "keyId": "<base64>", "attestation": "<base64>", "challenge": "…" }` |
| `PUT` | `/v1/devices/:token` | `{ "environment": "sandbox" \| "production", "categories": ["SM","SW","MX"], "cancellation": true, "rescheduling": true, "locale": "fr-FR", "timeZone": "Europe/Paris" }` |
| `DELETE` | `/v1/devices/:token` | |
| `GET` | `/v1/races/:raceId/channels/:environment` | Returns `{"channelId":"…"}`, the broadcast channel the app subscribes the race's Live Activity to (`404` when the race has none). |
| `GET` | `/v1/health` | Returns `{"apns":{"pushes":{"http2":true},"channels":{"http2":true}}}` when the Worker reaches APNs over HTTP/2, for pushes and for channel management. |
| `GET` | `/ibu/<endpoint>?…` | Same paths and query strings as the IBU API. |

### App Attest

Device registrations must come from the app on a genuine Apple device ([App Attest](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server)). At its first sync, the app generates a key, attests it with the SHA-256 of a challenge as `clientDataHash`, and posts the attestation to `/v1/app-attest/keys`. The server checks it against Apple's App Attestation Root CA and the `APP_ATTEST_APP_ID` secret (App ID prefix, a period, the bundle ID), then stores the public key. Challenges are stateless, signed with the `APP_ATTEST_SECRET` secret: replays are stopped by the one attestation per key and the assertion counter. Keys no device has used for 30 days are deleted once a day. Attestations and assertions from builds older than the `APP_ATTEST_MIN_BUNDLE_VERSION` variable (a `CFBundleVersion`) are rejected: raise it in `wrangler.jsonc` and deploy to shut out the builds before a fix.

Each `PUT` and `DELETE` on `/v1/devices/:token` then carries three headers: `X-App-Attest-Key-Id`, `X-App-Attest-Challenge` (a fresh challenge) and `X-App-Attest-Assertion`, an assertion whose `clientData` is the UTF-8 bytes of `"<challenge>\n<METHOD> <path>\n"` followed by the raw request body. A `401` with `{"error":"unknown key"}` tells the app to attest a new key. Each key holds one device token, and only that key can change or delete it (`403` otherwise): the token changes on reinstall, restore and migration, like the key.

## Deploy

1. In the Apple Developer account (Certificates, Identifiers & Profiles > Keys), create two team-scoped APNs keys, one for Sandbox and one for Production, as Apple recommends one key per environment. Note each Key ID and the Team ID (Membership details).
   In Identifiers, open `com.fouteox.biathlon` and check **Broadcast Capability** under Push Notifications: Live Activity channels need it, and Xcode can't enable it.
2. From this folder:

   ```sh
   npm ci
   npx wrangler login
   npx wrangler d1 create biathlon          # paste the printed database_id into wrangler.jsonc
   npx wrangler d1 migrations apply biathlon --remote
   npx wrangler secret put APNS_TEAM_ID
   npx wrangler secret put APP_ATTEST_APP_ID   # <App ID prefix>.com.fouteox.biathlon, from Identifiers
   openssl rand -base64 32 | npx wrangler secret put APP_ATTEST_SECRET
   npx wrangler secret put APNS_SANDBOX_KEY_ID
   npx wrangler secret put APNS_SANDBOX_KEY < AuthKey_SANDBOXKEYID.p8
   npx wrangler secret put APNS_PRODUCTION_KEY_ID
   npx wrangler secret put APNS_PRODUCTION_KEY < AuthKey_PRODKEYID.p8
   npx wrangler deploy
   curl https://biathlon-server.<subdomain>.workers.dev/v1/health
   ```

## Limits (Workers Free plan)

Each request to APNs or to the IBU API is a subrequest, and the Free plan allows 50 per invocation (D1 queries count separately, up to 1,000). `MAX_PUSHES_PER_RUN` (30 by default) caps the alerts sent per minute; the rest wait in the `outbox` table for the next runs, and alerts older than 30 minutes are dropped. On the Paid plan, raise it.

Live Activities take the rest: at most 4 channel creations per run, then for each race running or just over, one IBU request and one broadcast per environment, and for an hour after the end, one broadcast per environment every 10 minutes. A broadcast reaches every subscriber at once, so their number doesn't count.

## Develop

```sh
npm ci
npm test
npx wrangler d1 migrations apply biathlon --local
cp .dev.vars.example .dev.vars   # fill in a key
npx wrangler dev
curl "http://localhost:8787/cdn-cgi/local/scheduled?format=json"
```

Run `npx wrangler types` after editing `wrangler.jsonc`.
