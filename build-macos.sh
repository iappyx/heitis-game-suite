#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
FLUTTER="${FLUTTER:-flutter}"
command -v "$FLUTTER" >/dev/null || FLUTTER="$HOME/flutter/bin/flutter"
export FLUTTER
# Hosted mode: package the browser version first (served by the host)
./tool/build_webclient.sh
"$FLUTTER" build macos
# The Dock and Finder show the .app file name. The build target stays
# heitis_game_suite (an apostrophe in PRODUCT_NAME breaks CocoaPods' scripts),
# so ship a copy with the real name. Renaming keeps the code signature valid.
REL=build/macos/Build/Products/Release
rm -rf "$REL/Heiti's Game Suite.app"
ditto "$REL/heitis_game_suite.app" "$REL/Heiti's Game Suite.app"
echo "Mac app: $REL/Heiti's Game Suite.app"
