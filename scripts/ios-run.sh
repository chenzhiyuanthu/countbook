#!/usr/bin/env bash
# Build, install and launch on the simulator, then screenshot it.
#
#   scripts/ios-run.sh [out.png] [light|dark]
#
# Looking at the running app is the only way to know it works; a build that
# succeeds says nothing about what is on screen.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_UDID="${SIM_UDID:-5933A81F-F260-4AF0-9BA4-41D70B95B9A7}"
OUT="${1:-$ROOT/ios/screenshot.png}"
APPEARANCE="${2:-light}"
BUNDLE="com.czy.countbook"

"$ROOT/scripts/ios-check.sh" build >/dev/null

APP="$ROOT/ios/build/Build/Products/Debug-iphonesimulator/Countbook.app"
[ -d "$APP" ] || { echo "no app bundle at $APP"; exit 1; }

xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_UDID" >/dev/null 2>&1 || true
xcrun simctl ui "$SIM_UDID" appearance "$APPEARANCE" >/dev/null 2>&1 || true

xcrun simctl terminate "$SIM_UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$SIM_UDID" "$APP"
PID=$(xcrun simctl launch "$SIM_UDID" "$BUNDLE" | sed 's/.*: //')

# simctl returns as soon as the process exists, which is well before SwiftUI has
# drawn anything; without a settle the screenshot catches the launch screen or
# the home screen behind it.
sleep "${SETTLE:-5}"
xcrun simctl spawn "$SIM_UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE" \
  || echo "warning: $BUNDLE is not running — it may have crashed on launch"
xcrun simctl io "$SIM_UDID" screenshot --type=png "$OUT" >/dev/null
echo "shot: $OUT ($(stat -f%z "$OUT") bytes, $APPEARANCE)"
