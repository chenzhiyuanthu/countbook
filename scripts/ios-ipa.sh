#!/usr/bin/env bash
# Archive and export a development-signed .ipa for a real device.
#
# Signed with the Apple Development identity of team 493WT6Z4J4 against the
# wildcard team provisioning profile, so it installs on the devices already
# registered to that team. This is not an App Store build: that needs a
# distribution certificate and an App Store Connect key, neither of which is
# on this machine.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM="${DEVELOPMENT_TEAM:-493WT6Z4J4}"
OUT="${1:-$ROOT/build}"

cd "$ROOT/ios"
xcodegen generate >/dev/null

rm -rf "$OUT/Countbook.xcarchive"
xcodebuild archive \
  -project Countbook.xcodeproj \
  -scheme Countbook \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Countbook.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates 2>&1 | tail -5

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>development</string>
  <key>teamID</key><string>${TEAM}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>compileBitcode</key><false/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$OUT/Countbook.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/ipa" \
  -allowProvisioningUpdates 2>&1 | tail -5

ls -lh "$OUT/ipa"/*.ipa
