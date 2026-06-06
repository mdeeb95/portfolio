#!/usr/bin/env bash
# Preview the custom boot screen (boids loader -> "tap and hold to enter" -> iris)
# WITHOUT a Godot export. Substitutes the export placeholders in godot_shell.html
# and stubs the engine so you can iterate on the visuals in a real browser.
#
# Usage:  ./web/preview.sh   then open http://localhost:8060
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=".preview"
mkdir -p "$OUT"

python3 - "$OUT" <<'PY'
import sys, pathlib
out = pathlib.Path(sys.argv[1])
shell = pathlib.Path("web/godot_shell.html").read_text()

# Fake engine: ~2s of fake "download" progress, then resolves -> ready phase.
stub = (
  '<script>'
  'window.Engine=function(){};'
  'Engine.getMissingFeatures=function(){return[];};'
  'Engine.prototype.startGame=function(o){return new Promise(function(res){'
  'var p=0;var iv=setInterval(function(){p+=0.08;'
  'if(o&&o.onProgress)o.onProgress(p*9e6,9e6);'
  'if(p>=1){clearInterval(iv);setTimeout(res,300);}},180);});};'
  '</script>'
)
# Visible stand-in for the game so the iris reveal shows something.
fake_game = ('<style>#canvas{width:100vw;height:100vh;'
  'background:radial-gradient(circle at 50% 40%,#2b9d5e,#063a1f)}</style>')

html = (shell
  .replace("$GODOT_PROJECT_NAME", "preview")
  .replace("$GODOT_HEAD_INCLUDE", fake_game)
  .replace('<script src="$GODOT_URL"></script>', stub)
  .replace("$GODOT_CONFIG", "{}")
  .replace("$GODOT_THREADS_ENABLED", "false"))

(out / "index.html").write_text(html)
print("wrote", out / "index.html")
PY

echo "Serving preview at http://localhost:8060  (Ctrl+C to stop)"
exec python3 -m http.server 8060 --directory "$OUT"
