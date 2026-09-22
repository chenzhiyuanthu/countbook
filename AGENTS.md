# AGENTS.md — working on 据实 Countbook

Read `README.md` first for what the product is. This file is the operational
side: how to verify a change, and how to ship it to the two places it runs.
Everything below has been done from a terminal on the owner's Mac; nothing
needs Xcode's window or a cable, except the very first pairing of a new phone.

## Layout

| Path | What |
| --- | --- |
| `web/` | Vite + React PWA. `web/src/core/` is the domain logic (pure, tested); `web/src/sync/` the encryption and the two transports. |
| `ios/` | SwiftUI, zero packages. `ios/project.yml` → `xcodegen` → `Countbook.xcodeproj`. Mirrors `web/src/core/` file for file. |
| `server/` | Node stdlib + SQLite sync relay, also serves the built web app and the iOS build. Deployed with `server/deploy.sh`. |
| `design/` | The single source of truth for tokens (`tokens.json`), icons (`icons.json`) and the cross-platform test vectors (`fixtures/`). |
| `docs/` | PRODUCT / DESIGN / SCREENS / IMPLEMENTATION. A behaviour change edits the spec too. |
| `scripts/` | Build, screenshot and publish scripts. Every one runs from the repo root. |

## Verify before you ship

```bash
npm run --prefix web typecheck && npm run --prefix web test   # web: types + 60-odd tests
SIM_UDID=<udid> ./scripts/ios-build.sh test                    # iOS: builds and runs ~100 tests on a simulator
```

The default `SIM_UDID` inside `scripts/ios-*.sh` goes stale on every Xcode
update; find a live one with `xcrun simctl list devices available | grep iPhone`
and pass it. Both suites read `design/fixtures/*.json`, so a money, envelope or
FX vector added on one side must pass on the other.

Look at the result, not just the build:

```bash
node scripts/shot-one.mjs http://localhost:4173 out.png <today|ledger|report|wants|settings|capture>
SIM_UDID=<udid> ./scripts/ios-run.sh out.png          # installs on the simulator and screenshots it
```

The iOS app takes DEBUG-only launch arguments for screenshots, e.g.
`xcrun simctl launch <udid> com.czy.countbook -startTab report`, `-openCapture 1`
(with `-captureKind income -captureCurrency USD -captureAmount 1200`), `-showToast 1`.
Seed a ledger by writing a JSON event array (see `scripts/seed-demo.mjs`) to
`$(xcrun simctl get_app_container <udid> com.czy.countbook data)/Library/Application Support/Countbook/events.json`.

## Ship the web app and the server

```bash
./server/deploy.sh
```

One command: builds `web/` with `COUNTBOOK_BASE=/`, uploads it and `server/`
to `/opt/countbook` on the box (`ubuntu@43.162.121.196`, key auth), rebuilds
the container, keeps the existing edge Caddy attached, waits for `/healthz`.
The app is live at `https://countbook.chenzhiyuanthu.com`. The upload clears
`/opt/countbook/web` **except `web/ota`**, which holds the published iOS build.

A web-only change still goes through `deploy.sh`; it is a minute. The PWA's
service worker is versioned by build content, so a browser picks a deploy up
on its second load after it (the first load installs the new worker).

`chenzhiyuanthu.github.io/countbook/` is a mirror that deploys from a push to
`main` (`.github/workflows/pages.yml`); it lags until something is pushed.

## Ship the iOS app — over the air

This is how the owner's phone gets a build. No cable, no Xcode window, no Mac
on the same network: the phone fetches the package from the sync server.

```bash
./scripts/ios-ota.sh              # archive, sign, upload, print the link
SKIP_BUILD=1 ./scripts/ios-ota.sh # re-publish the .ipa already in build/ipa/
```

What it does:

1. `scripts/ios-ipa.sh` — `xcodegen generate`, `xcodebuild archive` for a
   real device, `xcodebuild -exportArchive` with the *development* method,
   signed by team `493WT6Z4J4`'s wildcard profile. Output: `build/ipa/Countbook.ipa`.
2. Reads the version out of the package, writes `manifest.plist` (the
   `itms-services` manifest pointing at `https://countbook.chenzhiyuanthu.com/ota/Countbook.ipa`)
   and a one-button `index.html`.
3. Uploads all three to `/opt/countbook/web/ota/` on the server, which the
   app container serves with the two MIME types Safari needs
   (`.plist` → `text/xml`, `.ipa` → `application/octet-stream`; `server.js`).

Then, **on the iPhone, in Safari**: open `https://countbook.chenzhiyuanthu.com/ota/`,
tap 安装到这台 iPhone, confirm 安装. The icon greys out and comes back in
about ten seconds; it replaces the installed app in place and keeps its data.
The page shows the build's version and timestamp so the owner can tell whether
they are looking at the build you just published.

Constraints, because it is a development-signed build:

- It installs only on devices registered to the team. The owner's iPhone is.
  A **new** phone must be plugged in once and run from Xcode (or
  `xcrun devicectl device install app --device <udid> build/ipa/Countbook.ipa`
  after `ios-ipa.sh` with `-allowProvisioningUpdates` registering it).
- The embedded profile expires a year after the archive; re-run `ios-ota.sh`
  before then and the owner reinstalls from the same link.
- The phone needs 开发者模式 on (设置 → 隐私与安全性), which it already has.
- There is no App Store or TestFlight path here: that needs a distribution
  certificate and an App Store Connect key, neither of which is on the machine.

Cable fallback, when the phone is plugged in and unlocked:

```bash
./scripts/ios-ipa.sh
xcrun devicectl device install app --device 00008150-001E192C11A1401C build/ipa/Countbook.ipa
xcrun devicectl device process launch --device 00008150-001E192C11A1401C com.czy.countbook
```

`devicectl list devices` shows the phone as `unavailable` when it is not
plugged in; wireless discovery through Xcode is unreliable on this network
(a TUN-mode proxy on the Mac eats Bonjour), which is why OTA is the default.

## Things that bit us

- **The Xcode license.** After an Xcode update, every Xcode-routed command
  (`xcodebuild`, `git`, `python3`, `devicectl`) exits 69 until someone runs
  `sudo xcodebuild -license accept` in a real terminal or clicks Agree in
  Xcode. Scripts that must not depend on it use bash + jq, or
  `/Library/Developer/CommandLineTools/usr/bin/python3`.
- **The service worker must never touch `/api/`.** The app and its API share
  an origin now; a cached `/api/pull` response silently froze sync once.
  `scripts/gen-sw.mjs` bypasses `/api/` and only caches what the build shipped.
- **The sync cursor advances only over rows actually pulled** — never from a
  push reply's head — or a row another device inserted meanwhile is skipped
  for good. `web/src/sync/server.test.ts` guards this; `ServerStore.swift` mirrors it.
- **A sheet must not size itself from its own content.** The capture sheet
  reads its room from `SheetContainer` via the environment (`sheetRoom`);
  measuring the content's global frame looped the layout at 100% CPU.
- **Money is integer 分; rates are integer millionths.** Conversion rounds half
  away from zero in BigInt (web) / Int64 (Swift) and is pinned by `design/fixtures/fx.json`.
- The server is in the US (Tencent, Santa Clara). It answers from mainland
  networks in practice, but if the phone ever cannot sync away from home, that
  is the first thing to suspect. Caddy access logs for the site are on
  (`sudo docker logs capital-race-caddy`), so "did the request arrive" is answerable.
