# Deployment guide (Cloudflare Pages)

Automated deploys run on every push to `main` via [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).

## Architecture

```
git push main → GitHub Actions → Godot 4.6 web export → build/web/ → Cloudflare Pages → mdeeb.dev
```

## 1. GitHub Actions secrets

In **GitHub → mdeeb95/portfolio → Settings → Secrets and variables → Actions**, add:

| Secret | How to get it |
|--------|----------------|
| `CLOUDFLARE_API_TOKEN` | [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens) → Create Token → use **Edit Cloudflare Workers** template, or custom token with **Account → Cloudflare Pages → Edit**. Use a dedicated token (not a short-lived OAuth token from `wrangler login`). |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare dashboard → any zone → right sidebar **Account ID** |

Set secrets via CLI (replace values):

```bash
gh secret set CLOUDFLARE_API_TOKEN
gh secret set CLOUDFLARE_ACCOUNT_ID
```

## 2. Cloudflare Pages project

The workflow creates/updates project **`portfolio`** on each deploy.

Optional manual create:

```bash
wrangler pages project create portfolio --production-branch main
```

**Important:** Do not attach a separate “build” on the Pages dashboard that also compiles the repo — CI already exports Godot. Pages should only receive the uploaded `build/web` artifact from the Action.

## 3. Custom domains

Custom domains are registered on the **`portfolio`** Pages project. Finish DNS in the **mdeeb.dev** zone (Cloudflare dashboard → DNS):

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| CNAME | `@` | `portfolio-7fw.pages.dev` | Proxied |
| CNAME | `www` | `portfolio-7fw.pages.dev` | Proxied |

Until those records exist, the game is live at **https://portfolio-7fw.pages.dev** (and each deployment preview URL).

Check domain status: **Workers & Pages → portfolio → Custom domains** (should move from *Pending* to *Active*).

## 4. Redirect www → apex (canonical)

**Rules → Redirect Rules** (or **Bulk Redirects**) on zone `mdeeb.dev`:

| Field | Value |
|-------|--------|
| When | Hostname equals `www.mdeeb.dev` |
| Then | Static redirect to `https://mdeeb.dev/${uri.path}` |
| Status | 301 |

## 5. Verify production

After a green Actions run:

- https://mdeeb.dev loads the game
- https://www.mdeeb.dev redirects to apex
- Mobile: tap to move, tap zones to interact
- Desktop: WASD, Space, E / click

## 6. Troubleshooting

| Issue | Fix |
|-------|-----|
| Action fails on export | Open repo in Godot 4.6 locally; confirm **Web** preset exports to `build/web/index.html`. Keep `vram_texture_compression/for_mobile=false` unless the project imports ETC2/ASTC. |
| Deploy fails: missing secrets | Add both Cloudflare secrets (step 1) |
| Deploy fails: file too large | CI runs `scripts/compress-web-export.sh` to gzip `index.wasm` (Pages 25 MiB limit) |
| Blank page in browser | Check browser console; if using threads later, add COOP/COEP via `public/_headers` |
| MCP missing locally | Copy addon from your zip to `addons/godot_mcp/`; not required for production |

## 7. Threaded export (future)

Current export uses `variant/thread_support=false` (no SharedArrayBuffer). To enable threads later:

1. Set `variant/thread_support=true` in `export_presets.cfg`
2. Uncomment headers in [`public/_headers`](../public/_headers) and copy into `build/web/` in the workflow
