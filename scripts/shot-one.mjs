#!/usr/bin/env node
/**
 * Screenshot one tab of the built web app, with a realistic demo ledger seeded.
 *
 *   node scripts/shot-one.mjs <baseUrl> <out.png> <tab> [light|dark] [width] [height]
 *
 * tab is one of: today ledger report wants settings capture
 *
 * Looking at the running app is the only way to know a layout works. A build
 * that succeeds says nothing about what is on screen.
 */
import { execFileSync } from 'node:child_process'
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const [base, out, tab = 'today', scheme = 'light', width = '402', height = '874'] = process.argv.slice(2)
if (!base || !out) {
  console.error('usage: shot-one.mjs <baseUrl> <out.png> <tab> [light|dark] [w] [h]')
  process.exit(1)
}

// Playwright is a verification tool, not a dependency of the product, so it
// lives outside the repository and is installed on first use.
const HOME = join(tmpdir(), 'countbook-verify')
mkdirSync(HOME, { recursive: true })
const require_ = createRequire(join(HOME, 'noop.js'))
let chromium
try {
  ;({ chromium } = require_('playwright'))
} catch {
  console.error('installing playwright (once)…')
  execFileSync('npm', ['i', '--no-audit', '--no-fund', '--prefix', HOME, 'playwright'], { stdio: 'inherit' })
  ;({ chromium } = require_('playwright'))
}

const demo = JSON.parse(execFileSync('node', [join(root, 'scripts/seed-demo.mjs')], { maxBuffer: 64 << 20 }).toString())

const TABS = ['today', 'ledger', 'report', 'wants', 'settings']
const browser = await chromium.launch({ channel: 'chrome' })
const ctx = await browser.newContext({
  viewport: { width: Number(width), height: Number(height) },
  deviceScaleFactor: 2,
  colorScheme: scheme,
  locale: 'zh-CN',
  timezoneId: 'Asia/Shanghai',
  isMobile: true,
  hasTouch: true,
})
await ctx.addInitScript((rows) => {
  localStorage.setItem('countbook.events', JSON.stringify(rows))
  const open = indexedDB.open('countbook', 1)
  open.onupgradeneeded = () => open.result.createObjectStore('kv')
  open.onsuccess = () => {
    const tx = open.result.transaction('kv', 'readwrite')
    tx.objectStore('kv').put(rows, 'countbook.events')
  }
}, demo)

const errors = []
const page = await ctx.newPage()
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message))

await page.goto(base, { waitUntil: 'networkidle' })
await page.waitForTimeout(900)

const wanted = tab === 'capture' ? 'today' : tab
const index = TABS.indexOf(wanted)
if (index >= 0) {
  const btn = page.locator('.tabbar button').nth(index)
  if (await btn.count()) {
    await btn.click()
    await page.waitForTimeout(700)
  }
}

if (tab === 'capture') {
  const fab = page.locator('button[class*="capture"]').first()
  if (await fab.count()) {
    await fab.click()
    await page.waitForTimeout(900)
  } else {
    console.error('capture button not found on this tab')
  }
}

mkdirSync(dirname(resolve(out)), { recursive: true })
await page.screenshot({ path: out })
await browser.close()

writeFileSync(join(HOME, 'last-errors.txt'), errors.join('\n'))
console.log(`${out}  ${tab}/${scheme}  ${width}x${height}`)
console.log(errors.length ? 'CONSOLE ERRORS:\n' + errors.join('\n') : 'no console errors')
