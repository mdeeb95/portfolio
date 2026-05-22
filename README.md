# Portfolio Town

Walkable 3D portfolio for [Mathew Deeb](https://mdeeb.dev) — explore a small town to learn about work, hobbies, accomplishments, and contact info.

Built with **Godot 4.6** (GL Compatibility) for **web** deployment on **Cloudflare Pages**.

## Live site

https://mdeeb.dev

## Local development

1. Install [Godot 4.6](https://godotengine.org/download) with export templates (**Editor → Manage Export Templates**).
2. Open this folder in Godot.
3. Press **F5** to run.

**Controls (desktop):** WASD move · Space jump · E or click to interact  
**Controls (mobile):** Tap ground to move · Tap buildings or Mathew to talk

## Web export (manual)

1. **Project → Export** → preset **Web** → **Export Project** → `build/web/index.html`
2. Serve locally: `npx --yes serve build/web -p 8080`

## Deployment

Pushes to `main` run [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml):

1. Export Godot Web build in CI
2. Deploy `build/web/` to Cloudflare Pages

### One-time setup (repo maintainer)

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for:

- GitHub Actions secrets (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`)
- Cloudflare Pages project + custom domains (`mdeeb.dev`, `www`)
- www → apex redirect

## Godot MCP Pro (optional, local only)

The paid [Godot MCP Pro](https://godot-mcp.abyo.net) addon is **not** in this repo. For AI-assisted editing in Cursor:

1. Install the addon from your licensed zip into `addons/godot_mcp/`
2. Enable **Godot MCP Pro** in **Project → Plugins**
3. Use [`.cursor/mcp.json.example`](.cursor/mcp.json.example) as a template for `.cursor/mcp.json` (gitignored)

## Project structure

```
scenes/          Main, player, town, UI
scripts/         Movement, dialogue, interactables
data/resume.json In-game copy (work, hobbies, about, etc.)
```

## License

Personal portfolio project. Game code: all rights reserved unless otherwise noted.
