# Analytics (first-party, Cloudflare Worker + D1)

Self-hosted, ad-blocker-proof analytics. The site beacons events to `https://mdeeb.dev/api/event`,
a Cloudflare Worker ([`analytics-worker/`](../analytics-worker/)) that writes rows to a D1 (SQLite)
database. Because the endpoint is first-party (same domain as the site), ad blockers do not block it.
Costs $0/month on the Workers/D1 free tier.

## Architecture

```
web/godot_shell.html ── window.__analytics.track(name, props) ──┐
                                                                ├─ sendBeacon POST /api/event
scripts/analytics.gd ── JavaScriptBridge ── window.__analytics ─┘          │
                                                                Worker: portfolio-analytics
                                                                (route mdeeb.dev/api/*)
                                                                           │
                                                                D1: portfolio_analytics → events table
```

- **One sending path**: the shell defines `window.__analytics.track()`; boot-funnel events are sent
  by the shell itself, gameplay events by the `Analytics` autoload via `JavaScriptBridge`.
  `Analytics` no-ops outside web builds, so in-editor runs are unaffected.
- **Privacy**: no cookies, no raw IPs stored, raw user-agent discarded after deriving
  `mobile`/`desktop`. `session_id` is a random per-page-load UUID; `visitor_id` is a random UUID
  persisted in localStorage so return visits are countable (no identity attached — if storage is
  blocked it silently degrades to per-session anonymity). Geo/network context (`country`, `city`,
  `region`, network `org`) comes from Cloudflare's edge metadata, not from storing addresses.
- **Deploys**: [`deploy-worker.yml`](../.github/workflows/deploy-worker.yml) runs on pushes touching
  `analytics-worker/**` — applies `schema.sql` (idempotent), then `wrangler deploy`. The Pages deploy
  (`deploy.yml`) is untouched and independent.

## Events

| Event | Sender | Means |
|---|---|---|
| `page_load` | shell | someone opened the page (carries `?src=`, referrer, viewport) |
| `boot_ready` | shell | WASM finished loading; "hold to enter" shown (`load_ms`) |
| `enter_completed` | shell | visitor held to enter (`wait_ms` = time spent deciding) |
| `boot_error` | shell | engine failed to start / WebGL missing (`fatal`), swarm fallback (non-fatal) |
| `session_ping` | shell | seconds-on-page checkpoint, sent on tab hide/close; MAX(t) = session length |
| `game_started` | Godot | engine alive, intro shown (carries `mobile`, `touch`, `tier`) |
| `first_move` | Godot | visitor actually started playing |
| `zone_visited` | Godot | walked up to a zone/NPC (once per zone per session) |
| `dialogue_opened` / `dialogue_completed` | Godot | opened / read-to-the-end a dialogue |

Funnel: `page_load → boot_ready → enter_completed → game_started → first_move`.

## One-time setup (manual)

1. **API token** — the token in the `CLOUDFLARE_API_TOKEN` GitHub secret needs, in addition to
   the existing **Account → Cloudflare Pages → Edit**:
   - **Account → Workers Scripts → Edit**
   - **Account → D1 → Edit**
   - **Zone (mdeeb.dev) → Workers Routes → Edit**
2. **Create the database** (locally):
   ```bash
   cd analytics-worker
   npx wrangler d1 create portfolio_analytics
   ```
   Paste the returned `database_id` into `analytics-worker/wrangler.toml`.
3. **First deploy** — push, or trigger the *Deploy Analytics Worker* workflow manually, or:
   ```bash
   cd analytics-worker && npx wrangler deploy
   ```
   Confirm the `mdeeb.dev/api/*` route under the zone's Workers Routes in the dashboard.
4. **Tag inbound links** so sources are attributable — this is what answers
   "is anyone clicking the resume link":
   - resume PDF → `https://mdeeb.dev/?src=resume`
   - LinkedIn profile → `https://mdeeb.dev/?src=li`
   - GitHub profile → `https://mdeeb.dev/?src=gh`

## Reading the data

```bash
./scripts/stats.sh daily      # visitors per day
./scripts/stats.sh funnel     # load → enter → play conversion
./scripts/stats.sh sources    # where visitors came from (?src= + referrer)
./scripts/stats.sh companies  # visits by network org + city ("someone at Google in NYC")
./scripts/stats.sh returning  # visitors who came back, with visit counts
./scripts/stats.sh zones      # which zones get explored
./scripts/stats.sh dialogues  # opened vs finished per zone
./scripts/stats.sh duration   # p50/p90 session length
./scripts/stats.sh errors     # boot failures
./scripts/stats.sh tech       # device / country / tier
```

Tip — the strongest "who" signal is minting a unique link per recipient: put
`https://mdeeb.dev/?src=acme-2026` on the resume you send to Acme and a hit on that tag identifies
the application it came from. `org`/`city` only identify corporate networks (home ISPs show as
e.g. "Comcast").

Auth: `npx wrangler login` once (or `CLOUDFLARE_API_TOKEN` in the env). Add `--local` to query the
local `wrangler dev` database. Ad-hoc SQL: Cloudflare dashboard → Storage & Databases → D1 →
`portfolio_analytics` → Console, or `npx wrangler d1 execute portfolio_analytics --remote --command "..."`.

## Verifying end-to-end

```bash
npx wrangler tail portfolio-analytics   # live request log
```

Then play through https://mdeeb.dev/?src=test (load → hold-to-enter → move → walk to a zone →
open and finish a dialogue → close the tab) and watch the events arrive; check `stats.sh funnel`.

## Local development

```bash
cd analytics-worker
npx wrangler d1 execute portfolio_analytics --local --file=schema.sql   # once
npx wrangler dev --local                                                # serves :8787
curl -i -X POST localhost:8787/api/event \
  -H 'User-Agent: Mozilla/5.0' \
  -d '{"sid":"test-session-0001","n":"page_load","p":{}}'               # expect 204
```

The Worker rejects: unknown event names, bad/missing session ids (400), bodies >2 KB (413),
bot user-agents and foreign origins (silent 204, nothing stored).
