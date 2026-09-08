#!/usr/bin/env bash
# Screenshot the web app with headless Chrome. Used to actually look at the
# result rather than trusting that it builds.
#
#   scripts/shot.sh <url> <out.png> [width] [height] [dark]
set -euo pipefail
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
URL="${1:?url}"
OUT="${2:?out}"
W="${3:-390}"
H="${4:-844}"
SCHEME="${5:-light}"

ARGS=(--headless=new --disable-gpu --no-sandbox --hide-scrollbars
      --force-device-scale-factor=2
      --window-size="${W},${H}"
      --virtual-time-budget=6000
      --screenshot="$OUT")
[ "$SCHEME" = "dark" ] && ARGS+=(--force-dark-mode --enable-features=WebContentsForceDark)

"$CHROME" "${ARGS[@]}" "$URL" >/dev/null 2>&1
[ -f "$OUT" ] && echo "shot: $OUT ($(stat -f%z "$OUT") bytes)" || { echo "screenshot failed"; exit 1; }
