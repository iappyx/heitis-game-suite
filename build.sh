#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
FLUTTER="${FLUTTER:-flutter}"
command -v "$FLUTTER" >/dev/null || FLUTTER="$HOME/flutter/bin/flutter"
export FLUTTER
# Hosted mode: package the browser version first (served by the host)
./tool/build_webclient.sh
"$FLUTTER" build apk --release
