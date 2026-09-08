/**
 * A hybrid logical clock. Events are ordered by (wallMs, counter, deviceId), a
 * total order that is stable across devices and survives a device whose clock
 * is wrong: the counter advances monotonically even when wall time goes
 * backwards, so a laggy phone can never silently overwrite a newer edit made on
 * a correct clock more than the skew allows.
 *
 * Encoded as a fixed-width sortable string so ordering is plain lexicographic
 * comparison in both TypeScript and Swift, and in any store that only sorts
 * strings.
 *
 *   0000018f2c3a4b5d-0007-a1b2c3d4
 *   |--------------|  |--| |------|
 *    wall ms, hex 16   ctr  device
 */

export interface Hlc {
  wall: number
  counter: number
  device: string
}

const hex = (n: number, width: number) => n.toString(16).padStart(width, '0')

export function encode(h: Hlc): string {
  return `${hex(h.wall, 16)}-${hex(h.counter, 4)}-${h.device}`
}

export function decode(s: string): Hlc {
  const [w = '0', c = '0', d = ''] = s.split('-')
  return { wall: parseInt(w, 16), counter: parseInt(c, 16), device: d }
}

/** Lexicographic order on the encoding is the intended total order. */
export const compare = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0)

export class Clock {
  private wall = 0
  private counter = 0

  constructor(readonly device: string, private now: () => number = Date.now) {}

  /** Stamp a locally-created event. */
  next(): string {
    const t = this.now()
    if (t > this.wall) {
      this.wall = t
      this.counter = 0
    } else {
      this.counter++
    }
    return encode({ wall: this.wall, counter: this.counter, device: this.device })
  }

  /**
   * Fold in a timestamp seen from another device, so our next stamp sorts after
   * anything we have already observed.
   */
  observe(stamp: string): void {
    const r = decode(stamp)
    const t = this.now()
    const wall = Math.max(this.wall, r.wall, t)
    if (wall === this.wall && wall === r.wall) this.counter = Math.max(this.counter, r.counter) + 1
    else if (wall === r.wall) this.counter = r.counter + 1
    else if (wall === this.wall) this.counter = this.counter + 1
    else this.counter = 0
    this.wall = wall
  }
}
