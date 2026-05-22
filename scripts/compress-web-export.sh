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

WASM_GZ_SIZE="$WASM_GZ_SIZE" python3 << 'PY'
import os
import pathlib
import re

root = pathlib.Path(".")
html = root / "index.html"
js = root / "index.js"
gz_size = int(os.environ["WASM_GZ_SIZE"])

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
# Cloudflare Pages may not set Content-Encoding on .wasm.gz; decompress in the loader.
old_fetch = """\t\treturn fetch(file).then(function (response) {
\t\t\tif (!response.ok) {
\t\t\t\treturn Promise.reject(new Error(`Failed loading file '${file}'`));
\t\t\t}
\t\t\tconst tr = getTrackedResponse(response, tracker[file]);
\t\t\tif (raw) {
\t\t\t\treturn Promise.resolve(tr);
\t\t\t}
\t\t\treturn tr.arrayBuffer();
\t\t});"""
new_fetch = """\t\treturn fetch(file).then(function (response) {
\t\t\tif (!response.ok) {
\t\t\t\treturn Promise.reject(new Error(`Failed loading file '${file}'`));
\t\t\t}
\t\t\tconst tr = getTrackedResponse(response, tracker[file]);
\t\t\tif (file.endsWith('.gz')) {
\t\t\t\tconst stream = tr.body.pipeThrough(new DecompressionStream('gzip'));
\t\t\t\tconst decompressed = new Response(stream, { headers: response.headers });
\t\t\t\tif (raw) {
\t\t\t\t\treturn Promise.resolve(decompressed);
\t\t\t\t}
\t\t\t\treturn decompressed.arrayBuffer();
\t\t\t}
\t\t\tif (raw) {
\t\t\t\treturn Promise.resolve(tr);
\t\t\t}
\t\t\treturn tr.arrayBuffer();
\t\t});"""
if old_fetch not in js_text:
    raise SystemExit("compress-web-export: could not patch index.js fetch handler")
js_text = js_text.replace(old_fetch, new_fetch)
js.write_text(js_text)
print(f"Compressed wasm -> index.wasm.gz ({gz_size} bytes)")
PY
