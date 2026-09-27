#!/usr/bin/env bash
# Builds the browser version of the app (Hosted mode) and packages it as
# assets/webclient/webclient.zip, which the host device serves to browsers.
# Run this BEFORE `flutter build apk` / `flutter build macos`.
#
# - Offline-safe: CanvasKit is bundled (--no-web-resources-cdn), fonts are
#   bundled (RobotoWeb + a subset of Noto Color Emoji).
# - The emoji font is cut down to the emoji the code actually uses
#   (needs Python fontTools; installed into tool/.venv on first run).
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-flutter}"
command -v "$FLUTTER" >/dev/null || FLUTTER="$HOME/flutter/bin/flutter"
OUT=assets/webclient/webclient.zip
WEB=build/web

# The web build bundles every pubspec asset — make sure it doesn't contain
# the previous web client itself.
rm -f "$OUT"

"$FLUTTER" build web --release --no-web-resources-cdn --pwa-strategy=none

# ── Emoji font subset ────────────────────────────────────────────────────────
FONT="$WEB/assets/assets/fonts/NotoColorEmoji-Regular.ttf"
if ! tool/.venv/bin/python -c "import fontTools, lxml" 2>/dev/null; then
  python3 -m venv tool/.venv
  tool/.venv/bin/pip install --quiet fonttools lxml
fi
# Every non-ASCII character used in the Dart sources (emoji, symbols)
python3 - > build/web_emoji.txt <<'PY'
import pathlib
chars = set()
for p in pathlib.Path('lib').rglob('*.dart'):
    chars.update(c for c in p.read_text(encoding='utf-8') if ord(c) > 0x2000)
print(''.join(sorted(chars)))
PY
tool/.venv/bin/pyftsubset "$FONT" --text-file=build/web_emoji.txt \
  --output-file="$FONT.subset" --no-hinting --layout-features='*' \
  --glyph-names --symbol-cmap --legacy-cmap --notdef-glyph --notdef-outline
mv "$FONT.subset" "$FONT"
# Only the host's apps need the web client, not the browser version itself
rm -rf "$WEB/assets/assets/webclient"
find "$WEB" -name '*.symbols' -delete
# JS build uses CanvasKit; the skwasm renderer is only loaded by --wasm builds
rm -f "$WEB"/canvaskit/skwasm.*

# ── Package ──────────────────────────────────────────────────────────────────
(cd "$WEB" && zip -q -r -9 "../../$OUT" . -x '.*')
echo "Web client: $OUT ($(du -h "$OUT" | cut -f1))"
