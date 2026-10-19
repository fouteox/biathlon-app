# Biathlon server

Cloudflare Worker that:

- polls biathlonresults.com every minute (Cron Trigger) during World Cup events and detects cancelled races and start time changes;
- sends the matching alerts through APNs to registered devices (texts are localized on the device, see `src/payload.ts`);
- exposes a read-only cache of the IBU API under `/ibu/`, which the app reads instead of biathlonresults.com. The Cache API also works on `*.workers.dev` (`cf-cache-status: HIT`, measured on 2026-10-19).

## API

| Method | Path | Body |
|---|---|---|
| `PUT` | `/v1/devices/:token` | `{ "environment": "sandbox" \| "production", "categories": ["SM","SW","MX"], "cancellation": true, "rescheduling": true, "locale": "fr-FR", "timeZone": "Europe/Paris" }` |
| `DELETE` | `/v1/devices/:token` | |
| `GET` | `/v1/health` | Returns `{"apns":{"http2":true}}` when the Worker reaches APNs over HTTP/2. |
| `GET` | `/ibu/<endpoint>?…` | Same paths and query strings as the IBU API. |

## Deploy

1. In the Apple Developer account (Certificates, Identifiers & Profiles > Keys), create two team-scoped APNs keys, one for Sandbox and one for Production, as Apple recommends one key per environment. Note each Key ID and the Team ID (Membership details).
2. From this folder:

   ```sh
   npm ci
   npx wrangler login
   npx wrangler d1 create biathlon          # paste the printed database_id into wrangler.jsonc
   npx wrangler d1 migrations apply biathlon --remote
   npx wrangler secret put APNS_TEAM_ID
   npx wrangler secret put APNS_SANDBOX_KEY_ID
   npx wrangler secret put APNS_SANDBOX_KEY < AuthKey_SANDBOXKEYID.p8
   npx wrangler secret put APNS_PRODUCTION_KEY_ID
   npx wrangler secret put APNS_PRODUCTION_KEY < AuthKey_PRODKEYID.p8
   npx wrangler deploy
   curl https://biathlon-server.<subdomain>.workers.dev/v1/health
   ```

## Limits (Workers Free plan)

Each APNs request is a subrequest, and the Free plan allows 50 per invocation, D1 queries included. `MAX_PUSHES_PER_RUN` (30 by default) caps the pushes sent per minute; the rest wait in the `outbox` table for the next runs, and alerts older than 30 minutes are dropped. On the Paid plan, raise it.

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
