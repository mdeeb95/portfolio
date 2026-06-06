# Portfolio Town

Walkable 3D portfolio for [Mathew Deeb](https://mdeeb.dev) — explore a small town to learn about work, hobbies, accomplishments, and contact info.

Built with **Godot 4.6** (GL Compatibility) for **web** deployment on **Cloudflare Pages**.

## Live site

https://mdeeb.dev

## Local development

1. Install [Godot 4.6](https://godotengine.org/download) with export templates (**Editor → Manage Export Templates**).
2. Open this folder in Godot.
3. Press **F5** to run.

**Controls (desktop):** WASD move · E or click to interact  
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
assets/          Kenney character models, animations, skins
scenes/          Main, player, town, UI, characters
scripts/         Movement, dialogue, interactables, animation
data/resume.json In-game copy (work, hobbies, about, etc.)
```

## Assets

Character model and skins from [Kenney Animated Characters Bundle](https://kenney.nl/assets) (CC0). Character animations (idle, walk, talk) from [Adobe Mixamo](https://www.mixamo.com), retargeted onto the Kenney rig in Mixamo and committed under `assets/characters/mixamo/` (per Mixamo's usage terms).

Environment art from Kenney Space Station Kit (CC0). Models import at **2.5×** baked into each FBX (`nodes/root_scale=2.5` in `models/*.fbx.import`) so props match characters at any parent. Use [Godot Asset Placer](https://godotengine.org/asset-library/asset/4244) on `town_square.tscn` — Plane mode **Y = 0.2**, grid snap **2.5 m**. `Environment/Floor` etc. are optional folders for organization.

**WYSIWYG:** `town_square.tscn` is the source of truth — what you see in the editor is what runs in game. The player lives under `PlayerSpawn`; move that marker to reposition spawn. No runtime reparenting, scaling, or visibility toggles.

**Grid Fill (Asset Placer):** In the Asset Placer options, choose **Grid Fill** placement mode. Set plane origin **Y = 0.2**, then **click and drag** across the floor to fill a rectangle of tiles in one undo step. Spacing is derived automatically from each asset's size (e.g. 2.5 m for floor tiles). Grid snap settings only affect single-tile placement, not fill spacing. Cycle modes with the plane-mode shortcut (default `Q`): Surface → Plane → Grid Fill → Surface.

## License

Personal portfolio project. Game code: all rights reserved unless otherwise noted.
