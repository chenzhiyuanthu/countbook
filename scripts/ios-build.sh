#!/usr/bin/env bash
# Regenerate the Xcode project from project.yml and build for the simulator.
# Usage: scripts/ios-build.sh [build|test]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_UDID="${SIM_UDID:-5933A81F-F260-4AF0-9BA4-41D70B95B9A7}"   # iPhone 17 Pro, iOS 26.3
ACTION="${1:-build}"

cd "$ROOT/ios"
xcodegen generate >/dev/null
xcodebuild \
  -project Countbook.xcodeproj \
  -scheme Countbook \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIM_UDID}" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  "$ACTION" 2>&1 | tail -40
