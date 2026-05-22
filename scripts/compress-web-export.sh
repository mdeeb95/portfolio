#!/usr/bin/env bash
# Cloudflare Pages rejects single files over 25 MiB. Godot 4.6 web wasm is ~36 MiB;
# gzip shrinks it to ~9 MiB. Patch HTML/JS so the loader fetches and inflates .wasm.gz.
set -euo pipefail

ROOT="${1:-build/web}"

if [[ ! -d "$ROOT" ]]; then
  echo "compress-web-export: directory not found: $ROOT" >&2
  exit 1
fi

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

export WASM_GZ_SIZE
python3 << 'PY'
import os
import pathlib
import re
import sys

root = pathlib.Path(".")
html = root / "index.html"
js = root / "index.js"
gz_size = int(os.environ["WASM_GZ_SIZE"])

html_text = html.read_text()
html_text, n = re.subn(
    r'"index\.wasm(?:\.gz)?":\d+',
    f'"index.wasm.gz":{gz_size}',
    html_text,
    count=1,
)
if n != 1:
    sys.exit("compress-web-export: could not patch index.html fileSizes")
html.write_text(html_text)

js_text = js.read_text()
replacements = [
    (
        "preloader.loadPromise(`${loadPath}.wasm`, size, true);",
        "preloader.loadPromise(`${loadPath}.wasm.gz`, size, true);",
    ),
    (
        "Engine.load(basePath, this.config.fileSizes[`${basePath}.wasm`]);",
        "Engine.load(basePath, this.config.fileSizes[`${basePath}.wasm.gz`]);",
    ),
]
for old, new in replacements:
    if old not in js_text:
        sys.exit(f"compress-web-export: missing expected JS fragment: {old[:60]}...")
    js_text = js_text.replace(old, new)

old_fetch = "\t\treturn fetch(file).then(function (response) {\n\t\t\tif (!response.ok) {\n\t\t\t\treturn Promise.reject(new Error(`Failed loading file '${file}'`));\n\t\t\t}\n\t\t\tconst tr = getTrackedResponse(response, tracker[file]);\n\t\t\tif (raw) {\n\t\t\t\treturn Promise.resolve(tr);\n\t\t\t}\n\t\t\treturn tr.arrayBuffer();\n\t\t});"
new_fetch = "\t\treturn fetch(file).then(function (response) {\n\t\t\tif (!response.ok) {\n\t\t\t\treturn Promise.reject(new Error(`Failed loading file '${file}'`));\n\t\t\t}\n\t\t\tconst tr = getTrackedResponse(response, tracker[file]);\n\t\t\tif (file.endsWith('.gz')) {\n\t\t\t\tconst stream = tr.body.pipeThrough(new DecompressionStream('gzip'));\n\t\t\t\tconst decompressed = new Response(stream, { headers: response.headers });\n\t\t\t\tif (raw) {\n\t\t\t\t\treturn Promise.resolve(decompressed);\n\t\t\t\t}\n\t\t\t\treturn decompressed.arrayBuffer();\n\t\t\t}\n\t\t\tif (raw) {\n\t\t\t\treturn Promise.resolve(tr);\n\t\t\t}\n\t\t\treturn tr.arrayBuffer();\n\t\t});"
if old_fetch in js_text:
    js_text = js_text.replace(old_fetch, new_fetch)
elif "DecompressionStream('gzip')" not in js_text:
    sys.exit("compress-web-export: could not patch index.js fetch handler")

if "preloader.loadPromise(`${loadPath}.wasm`, size, true);" in js_text:
    sys.exit("compress-web-export: index.js still loads uncompressed .wasm")
if "fileSizes[`${basePath}.wasm`]" in js_text:
    sys.exit("compress-web-export: index.js still reads uncompressed .wasm file size")

js.write_text(js_text)
print(f"Compressed wasm -> index.wasm.gz ({gz_size} bytes)")
PY
