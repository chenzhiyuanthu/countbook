#!/usr/bin/env bash
# Publish the iOS build for over-the-air install: open the printed link in
# Safari on a registered iPhone and tap 安装. No cable, no Xcode, no Mac on the
# same network — the phone fetches the package from the sync server.
#
#   ./scripts/ios-ota.sh              # archive, sign, upload, print the link
#   SKIP_BUILD=1 ./scripts/ios-ota.sh # re-publish the .ipa already in build/
#
# The build is development-signed, so it installs only on devices in the team
# profile (ios-ipa.sh). The manifest is what Safari's itms-services: handler
# reads; the server serves .plist as XML and .ipa as bytes for exactly this.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_HOST="${SSH_HOST:-43.162.121.196}"
REMOTE_DIR="${REMOTE_DIR:-/opt/countbook}"
DOMAIN="${DOMAIN:-countbook.chenzhiyuanthu.com}"
BUNDLE="com.czy.countbook"
IPA="$ROOT/build/ipa/Countbook.ipa"
OUT="$ROOT/build/ota"

[ "${SKIP_BUILD:-}" = 1 ] || "$ROOT/scripts/ios-ipa.sh" >/dev/null
[ -f "$IPA" ] || { echo "no .ipa at $IPA"; exit 1; }

# The version the phone will show, read from the package itself so the
# manifest can never disagree with what it points at.
TMP="$(mktemp -d)"
unzip -q -o "$IPA" 'Payload/Countbook.app/Info.plist' -d "$TMP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TMP/Payload/Countbook.app/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TMP/Payload/Countbook.app/Info.plist")"
rm -rf "$TMP"
STAMP="$(date '+%Y-%m-%d %H:%M')"

rm -rf "$OUT" && mkdir -p "$OUT"
cp "$IPA" "$OUT/Countbook.ipa"

cat > "$OUT/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>https://${DOMAIN}/ota/Countbook.ipa</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>${BUNDLE}</string>
        <key>bundle-version</key><string>${VERSION}</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>据实 Countbook</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

# One page, one button, in the app's own paper and ink. The link only works
# from Safari on an iPhone; anywhere else it is inert, and the page says so.
cat > "$OUT/index.html" <<HTML
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<title>据实 · 安装</title>
<style>
  :root { color-scheme: light dark; --paper: #F7F6F3; --ink: #111110; --ink5: #6E6C64; --rule: #E2DFD8; }
  @media (prefers-color-scheme: dark) { :root { --paper: #121211; --ink: #F2F0EA; --ink5: #8C897F; --rule: #2B2A27; } }
  html, body { margin: 0; background: var(--paper); color: var(--ink); font: 17px/1.5 -apple-system, "PingFang SC", system-ui, sans-serif; }
  main { max-width: 480px; margin: 0 auto; padding: max(64px, env(safe-area-inset-top)) 20px 40px; }
  h1 { font-size: 15px; font-weight: 500; letter-spacing: .04em; color: var(--ink5); margin: 0 0 8px; }
  p { margin: 0 0 24px; }
  .mono { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 15px; color: var(--ink5); }
  a.install { display: block; text-align: center; padding: 16px; border-radius: 9px; background: var(--ink); color: var(--paper); text-decoration: none; font-weight: 600; }
  hr { border: 0; border-top: 1px solid var(--rule); margin: 32px 0; }
  ol { padding-left: 20px; color: var(--ink5); margin: 0; }
</style>
</head>
<body>
<main>
  <h1>据实 · Countbook</h1>
  <p class="mono">${VERSION} (${BUILD}) · ${STAMP}</p>
  <a class="install" href="itms-services://?action=download-manifest&amp;url=https://${DOMAIN}/ota/manifest.plist">安装到这台 iPhone</a>
  <hr>
  <ol>
    <li>在 iPhone 的 Safari 里打开这一页，点上面的按钮，弹窗选「安装」。</li>
    <li>回到主屏幕看图标：装完前是灰的，装完就能打开。数据不受影响。</li>
    <li>只有已登记到开发团队的手机能装；换手机先插线在 Xcode 里跑一次。</li>
  </ol>
</main>
</body>
</html>
HTML

export COPYFILE_DISABLE=1
ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${SSH_HOST}" "mkdir -p ${REMOTE_DIR}/web/ota"
tar czf - -C "$OUT" . | ssh "${SSH_USER}@${SSH_HOST}" "tar xzf - -C ${REMOTE_DIR}/web/ota && find ${REMOTE_DIR}/web/ota -name '._*' -delete"

printf '\n\033[1;32m✓ published\033[0m  %s (%s) · %s\n' "$VERSION" "$BUILD" "$(du -h "$IPA" | cut -f1)"
printf '  在 iPhone 的 Safari 里打开:  https://%s/ota/\n\n' "$DOMAIN"
