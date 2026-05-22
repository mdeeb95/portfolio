#!/usr/bin/env bash
# Cloudflare Pages rejects single files over 25 MiB. Godot 4.6 web wasm is ~36 MiB;
# gzip shrinks it to ~9 MiB. Patch the loader to fetch the .gz asset with correct headers.
set -euo pipefail

ROOT="${1:-build/web}"

if [[ ! -d "$ROOT" ]]; then
  echo "compress-web-export: directory not found: $ROOT" >&2
  exit 1
fi

# godot-export may place files directly in build/web or one level deeper.
WASM_PATH="$(find "$ROOT" -name 'index.wasm' -print -quit)"
if [[ -z "$WASM_PATH" ]]; then
  echo "compress-web-export: index.wasm not found under $ROOT" >&2
  find "$ROOT" -maxdepth 3 -type f | head -30 >&2 || true
  exit 1
fi

cd "$(dirname "$WASM_PATH")"

gzip -9 -k -f index.wasm
WASM_GZ_SIZE=$(stat -c%s index.wasm.gz)
rm -f index.wasm

python3 << PY
import pathlib
import re

root = pathlib.Path(".")
html = root / "index.html"
js = root / "index.js"
gz_size = int("${WASM_GZ_SIZE}")

html_text = html.read_text()
html_text = re.sub(
    r'"index\.wasm":\d+',
    f'"index.wasm.gz":{gz_size}',
    html_text,
    count=1,
)
html.write_text(html_text)

js_text = js.read_text()
js_text = js_text.replace(
    "preloader.loadPromise(\`\${loadPath}.wasm\`, size, true);",
    "preloader.loadPromise(\`\${loadPath}.wasm.gz\`, size, true);",
)
js_text = js_text.replace(
    "this.config.fileSizes[\`\${basePath}.wasm\`]",
    "this.config.fileSizes[\`\${basePath}.wasm.gz\`]",
)
js.write_text(js_text)
print(f"Compressed wasm -> index.wasm.gz ({gz_size} bytes)")
PY
