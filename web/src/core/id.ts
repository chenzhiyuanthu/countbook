/**
 * Identifiers are 128 bits of CSPRNG output in lowercase hex. Not UUIDv4 —
 * crypto.randomUUID is unavailable on non-secure origins, which would break the
 * app when opened over plain HTTP on a LAN address.
 */
export function newId(): string {
  const b = new Uint8Array(16)
  crypto.getRandomValues(b)
  return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('')
}

/** A stable per-installation identifier; the HLC's tiebreaker. */
export function deviceId(storage: Storage = localStorage): string {
  const KEY = 'countbook.device'
  let v = storage.getItem(KEY)
  if (!v) {
    v = newId().slice(0, 8)
    storage.setItem(KEY, v)
  }
  return v
}
