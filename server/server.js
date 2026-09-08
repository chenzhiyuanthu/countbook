'use strict'
/**
 * 据实 · Countbook — optional self-hosted sync server.
 *
 * Node standard library only: node:http, node:sqlite, node:crypto. Nothing to
 * install, nothing in the supply chain, and it starts in a few milliseconds.
 *
 * The server is a dumb, ordered, append-only relay. Every event body it stores
 * is ciphertext produced on a device; the key is derived from a passphrase that
 * never leaves the client, so operating this server does not grant the ability
 * to read the ledger. That is deliberate: the same encryption applies whether
 * the transport is this server or a private GitHub repository, so the two sync
 * adapters are interchangeable and one device can use either.
 *
 * Auth is a bearer token rather than a cookie. The web app is served from
 * GitHub Pages and talks to this host cross-origin, where a third-party cookie
 * would be dropped by Safari and by iOS entirely.
 */

const http = require('node:http')
const crypto = require('node:crypto')
const fs = require('node:fs')
const path = require('node:path')
const { DatabaseSync } = require('node:sqlite')

const PORT = Number(process.env.PORT || 8080)
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data')
const SESSION_SECRET = process.env.SESSION_SECRET || ''
const SIGNUP_CODE = process.env.SIGNUP_CODE || ''
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean)

if (!SESSION_SECRET) {
  console.error('SESSION_SECRET is not set. Refusing to start with a guessable signing key.')
  process.exit(1)
}

const SESSION_TTL_MS = 90 * 24 * 3600 * 1000
const MAX_BODY = 4 * 1024 * 1024
const MAX_EVENTS_PER_PUSH = 1000
const MAX_EVENT_BYTES = 64 * 1024

/* ── storage ─────────────────────────────────────────────────────────── */

fs.mkdirSync(DATA_DIR, { recursive: true })
const db = new DatabaseSync(path.join(DATA_DIR, 'countbook.db'))
db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA foreign_keys = ON;
  PRAGMA busy_timeout = 5000;

  CREATE TABLE IF NOT EXISTS users (
    id          TEXT PRIMARY KEY,
    email       TEXT NOT NULL UNIQUE,
    pw_hash     TEXT NOT NULL,
    pw_salt     TEXT NOT NULL,
    created_at  INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS sessions (
    token_hash  TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device      TEXT NOT NULL DEFAULT '',
    label       TEXT NOT NULL DEFAULT '',
    created_at  INTEGER NOT NULL,
    seen_at     INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);

  -- seq is the pull cursor: a monotonically increasing server-side arrival
  -- order, independent of the clients' own clocks.
  CREATE TABLE IF NOT EXISTS events (
    seq         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id          TEXT NOT NULL,
    hlc         TEXT NOT NULL,
    body        TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    UNIQUE(user_id, id)
  );
  CREATE INDEX IF NOT EXISTS events_pull ON events(user_id, seq);
`)

const q = {
  userByEmail: db.prepare('SELECT * FROM users WHERE email = ?'),
  insertUser: db.prepare('INSERT INTO users (id, email, pw_hash, pw_salt, created_at) VALUES (?, ?, ?, ?, ?)'),
  countUsers: db.prepare('SELECT COUNT(*) AS n FROM users'),
  insertSession: db.prepare(
    'INSERT INTO sessions (token_hash, user_id, device, label, created_at, seen_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
  ),
  sessionByHash: db.prepare('SELECT * FROM sessions WHERE token_hash = ?'),
  touchSession: db.prepare('UPDATE sessions SET seen_at = ? WHERE token_hash = ?'),
  deleteSession: db.prepare('DELETE FROM sessions WHERE token_hash = ?'),
  sessionsOfUser: db.prepare('SELECT token_hash, device, label, created_at, seen_at FROM sessions WHERE user_id = ? ORDER BY seen_at DESC'),
  deleteSessionOfUser: db.prepare('DELETE FROM sessions WHERE user_id = ? AND token_hash = ?'),
  purgeExpired: db.prepare('DELETE FROM sessions WHERE expires_at < ?'),
  insertEvent: db.prepare(
    'INSERT INTO events (user_id, id, hlc, body, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id, id) DO NOTHING',
  ),
  pull: db.prepare('SELECT seq, id, hlc, body FROM events WHERE user_id = ? AND seq > ? ORDER BY seq LIMIT ?'),
  head: db.prepare('SELECT COALESCE(MAX(seq), 0) AS seq, COUNT(*) AS n FROM events WHERE user_id = ?'),
}

/* ── helpers ─────────────────────────────────────────────────────────── */

const now = () => Date.now()
const b64 = (buf) => Buffer.from(buf).toString('base64url')
const sha256 = (s) => crypto.createHash('sha256').update(s).digest('base64url')

function hashPassword(password, salt = crypto.randomBytes(16)) {
  // scrypt with the parameters Node documents as interactive-login grade. The
  // cost is deliberate: this endpoint is rate-limited, so 100ms is free here
  // and expensive for anyone with a stolen database.
  const hash = crypto.scryptSync(password.normalize('NFKC'), salt, 32, { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 })
  return { hash: b64(hash), salt: b64(salt) }
}

function verifyPassword(password, storedHash, storedSalt) {
  const { hash } = hashPassword(password, Buffer.from(storedSalt, 'base64url'))
  const a = Buffer.from(hash)
  const b = Buffer.from(storedHash)
  return a.length === b.length && crypto.timingSafeEqual(a, b)
}

/** The stored token is a hash, so a database leak does not yield live sessions. */
const tokenHash = (token) => crypto.createHmac('sha256', SESSION_SECRET).update(token).digest('base64url')

// Login and signup are the only endpoints worth guessing at, so they get a
// small in-memory sliding window per IP. Restarting clears it, which is fine:
// this defends against a script, not against a determined attacker with time.
const attempts = new Map()
function rateLimited(ip, limit = 10, windowMs = 10 * 60_000) {
  const t = now()
  const hits = (attempts.get(ip) || []).filter((x) => t - x < windowMs)
  hits.push(t)
  attempts.set(ip, hits)
  if (attempts.size > 5000) attempts.clear()
  return hits.length > limit
}

function send(res, status, body, extraHeaders = {}) {
  const payload = body === undefined ? '' : JSON.stringify(body)
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...extraHeaders,
  })
  res.end(payload)
}

function cors(req, res) {
  const origin = req.headers.origin
  if (!origin) return true
  // A capacitor:// or file:// origin (the iOS app in a webview) sends 'null';
  // the native app sends no Origin at all. Neither can be allow-listed by name,
  // and neither needs to be: bearer tokens are not attached automatically, so
  // there is no cross-site request forgery surface to protect.
  if (ALLOWED_ORIGINS.includes(origin) || ALLOWED_ORIGINS.includes('*')) {
    res.setHeader('access-control-allow-origin', origin)
    res.setHeader('vary', 'Origin')
    res.setHeader('access-control-allow-headers', 'authorization, content-type')
    res.setHeader('access-control-allow-methods', 'GET, POST, DELETE, OPTIONS')
    res.setHeader('access-control-max-age', '86400')
    return true
  }
  return false
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0
    const chunks = []
    req.on('data', (c) => {
      size += c.length
      if (size > MAX_BODY) {
        reject(Object.assign(new Error('body too large'), { status: 413 }))
        req.destroy()
        return
      }
      chunks.push(c)
    })
    req.on('end', () => {
      if (!chunks.length) return resolve({})
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')))
      } catch {
        reject(Object.assign(new Error('malformed JSON'), { status: 400 }))
      }
    })
    req.on('error', reject)
  })
}

function authenticate(req) {
  const header = req.headers.authorization || ''
  const m = /^Bearer\s+(.+)$/i.exec(header)
  if (!m) return null
  const hash = tokenHash(m[1])
  const session = q.sessionByHash.get(hash)
  if (!session || session.expires_at < now()) return null
  // Cheap liveness for the device list; one write per request is acceptable at
  // this scale and keeps "last seen" honest.
  q.touchSession.run(now(), hash)
  return session
}

const isEmail = (s) => typeof s === 'string' && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s) && s.length <= 254

/* ── routes ──────────────────────────────────────────────────────────── */

const routes = {
  'GET /healthz': async (req, res) => {
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' })
    res.end('ok')
  },

  'POST /api/signup': async (req, res, ctx) => {
    if (rateLimited(ctx.ip, 5)) return send(res, 429, { error: 'too_many_attempts' })
    const body = await readJson(req)
    if (!isEmail(body.email)) return send(res, 400, { error: 'bad_email' })
    if (typeof body.password !== 'string' || body.password.length < 10) {
      return send(res, 400, { error: 'weak_password', detail: 'at least 10 characters' })
    }
    // The first account is free to create so a fresh deployment is usable;
    // every one after it needs the code written into .env by deploy.sh.
    const first = q.countUsers.get().n === 0
    if (!first && SIGNUP_CODE && body.code !== SIGNUP_CODE) return send(res, 403, { error: 'bad_code' })
    if (!first && !SIGNUP_CODE) return send(res, 403, { error: 'signup_closed' })

    const email = String(body.email).trim().toLowerCase()
    if (q.userByEmail.get(email)) return send(res, 409, { error: 'email_taken' })

    const { hash, salt } = hashPassword(body.password)
    const id = crypto.randomUUID()
    q.insertUser.run(id, email, hash, salt, now())
    return send(res, 200, issueToken(id, body.device, body.label))
  },

  'POST /api/login': async (req, res, ctx) => {
    if (rateLimited(ctx.ip)) return send(res, 429, { error: 'too_many_attempts' })
    const body = await readJson(req)
    const email = String(body.email || '').trim().toLowerCase()
    const user = q.userByEmail.get(email)
    // Hash even when the user does not exist, so response time does not reveal
    // which addresses are registered.
    const ok = user
      ? verifyPassword(String(body.password || ''), user.pw_hash, user.pw_salt)
      : (hashPassword(String(body.password || '')), false)
    if (!ok) return send(res, 401, { error: 'bad_credentials' })
    return send(res, 200, issueToken(user.id, body.device, body.label))
  },

  'POST /api/logout': async (req, res, ctx) => {
    if (!ctx.session) return send(res, 401, { error: 'unauthorised' })
    q.deleteSession.run(ctx.session.token_hash)
    return send(res, 200, { ok: true })
  },

  'GET /api/me': async (req, res, ctx) => {
    if (!ctx.session) return send(res, 401, { error: 'unauthorised' })
    const head = q.head.get(ctx.session.user_id)
    return send(res, 200, { userId: ctx.session.user_id, cursor: head.seq, events: head.n })
  },

  'GET /api/pull': async (req, res, ctx) => {
    if (!ctx.session) return send(res, 401, { error: 'unauthorised' })
    const since = Math.max(0, Number(ctx.url.searchParams.get('since') || 0) || 0)
    const limit = Math.min(1000, Math.max(1, Number(ctx.url.searchParams.get('limit') || 500) || 500))
    const rows = q.pull.all(ctx.session.user_id, since, limit)
    const cursor = rows.length ? rows[rows.length - 1].seq : since
    return send(res, 200, {
      events: rows.map((r) => ({ id: r.id, hlc: r.hlc, body: r.body })),
      cursor,
      hasMore: rows.length === limit,
    })
  },

  'POST /api/push': async (req, res, ctx) => {
    if (!ctx.session) return send(res, 401, { error: 'unauthorised' })
    const body = await readJson(req)
    const events = Array.isArray(body.events) ? body.events : null
    if (!events) return send(res, 400, { error: 'events_required' })
    if (events.length > MAX_EVENTS_PER_PUSH) return send(res, 413, { error: 'too_many_events' })

    for (const e of events) {
      if (typeof e?.id !== 'string' || !e.id || e.id.length > 64) return send(res, 400, { error: 'bad_event_id' })
      if (typeof e?.hlc !== 'string' || e.hlc.length > 64) return send(res, 400, { error: 'bad_event_hlc' })
      if (typeof e?.body !== 'string' || e.body.length > MAX_EVENT_BYTES) return send(res, 400, { error: 'bad_event_body' })
    }

    // Events are immutable and identified by a client-generated id, so a retry
    // after a dropped response inserts nothing the second time.
    const t = now()
    let accepted = 0
    db.exec('BEGIN IMMEDIATE')
    try {
      for (const e of events) {
        const r = q.insertEvent.run(ctx.session.user_id, e.id, e.hlc, e.body, t)
        accepted += r.changes
      }
      db.exec('COMMIT')
    } catch (err) {
      db.exec('ROLLBACK')
      throw err
    }
    return send(res, 200, { accepted, duplicates: events.length - accepted, cursor: q.head.get(ctx.session.user_id).seq })
  },

  'GET /api/devices': async (req, res, ctx) => {
    if (!ctx.session) return send(res, 401, { error: 'unauthorised' })
    const rows = q.sessionsOfUser.all(ctx.session.user_id)
    return send(res, 200, {
      devices: rows.map((r) => ({
        // The full hash is a credential-equivalent lookup key; a prefix is
        // enough to name a row in the UI.
        ref: r.token_hash.slice(0, 12),
        device: r.device,
        label: r.label,
        createdAt: r.created_at,
        seenAt: r.seen_at,
        current: r.token_hash === ctx.session.token_hash,
      })),
    })
  },

  'POST /api/devices/revoke': async (req, res, ctx) => {
    if (!ctx.session) return send(res, 401, { error: 'unauthorised' })
    const { ref } = await readJson(req)
    if (typeof ref !== 'string' || ref.length < 8) return send(res, 400, { error: 'bad_ref' })
    const target = q.sessionsOfUser.all(ctx.session.user_id).find((r) => r.token_hash.startsWith(ref))
    if (!target) return send(res, 404, { error: 'not_found' })
    q.deleteSessionOfUser.run(ctx.session.user_id, target.token_hash)
    return send(res, 200, { ok: true })
  },
}

function issueToken(userId, device, label) {
  const token = b64(crypto.randomBytes(32))
  const t = now()
  const expiresAt = t + SESSION_TTL_MS
  q.insertSession.run(
    tokenHash(token),
    userId,
    String(device || '').slice(0, 64),
    String(label || '').slice(0, 64),
    t,
    t,
    expiresAt,
  )
  return { token, expiresAt, userId }
}

/* ── server ──────────────────────────────────────────────────────────── */

const server = http.createServer(async (req, res) => {
  const allowed = cors(req, res)
  if (req.method === 'OPTIONS') {
    res.writeHead(allowed ? 204 : 403)
    return res.end()
  }
  if (!allowed) return send(res, 403, { error: 'origin_not_allowed' })

  const url = new URL(req.url, 'http://localhost')
  const key = `${req.method} ${url.pathname}`
  const handler = routes[key]
  if (!handler) return send(res, 404, { error: 'not_found' })

  const ip = (req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress || '?'

  try {
    await handler(req, res, { url, ip, session: authenticate(req) })
  } catch (err) {
    if (res.headersSent) return
    const status = err && err.status ? err.status : 500
    if (status === 500) console.error('unhandled:', err)
    send(res, status, { error: status === 500 ? 'internal' : String(err.message) })
  }
})

setInterval(() => q.purgeExpired.run(now()), 3600_000).unref()

server.listen(PORT, () => {
  console.log(`countbook-server on :${PORT}  data=${DATA_DIR}  origins=${ALLOWED_ORIGINS.join(',') || '(none)'}`)
})

process.on('SIGTERM', () => server.close(() => { db.close(); process.exit(0) }))
