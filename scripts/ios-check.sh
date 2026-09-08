#!/usr/bin/env bash
# Regenerate the Xcode project and build for the simulator, under a mutex.
#
# Several agents may write Swift files at once, and `xcodegen generate` rewrites
# the whole .xcodeproj while `xcodebuild` reads it — running the two
# concurrently produces spurious failures. A mkdir mutex is enough here: it is
# atomic on every filesystem and needs no tooling macOS does not ship.
#
#   scripts/ios-check.sh          build
#   scripts/ios-check.sh test     build and run the unit tests
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/ios/.buildlock"
SIM_UDID="${SIM_UDID:-5933A81F-F260-4AF0-9BA4-41D70B95B9A7}"
ACTION="${1:-build}"

for i in $(seq 1 240); do
  if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
    break
  fi
  # A crashed holder would block everyone; treat a stale lock as free.
  if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null
  fi
  sleep 2
done
[ -d "$LOCK" ] || { echo "could not take the build lock"; exit 1; }

cd "$ROOT/ios"
xcodegen generate >/dev/null 2>&1 || { echo "xcodegen failed"; exit 1; }

OUT=$(xcodebuild \
  -project Countbook.xcodeproj \
  -scheme Countbook \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIM_UDID}" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  "$ACTION" 2>&1)
STATUS=$?

if [ $STATUS -eq 0 ]; then
  echo "$OUT" | tail -3
else
  # Only the diagnostics matter; the transcript around them is noise.
  echo "$OUT" | grep -E "error:|warning:.*(unused|never used)|FAILED|Testing failed" | head -60
  echo "--- (build failed, status $STATUS) ---"
fi
exit $STATUS
