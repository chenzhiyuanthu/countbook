/**
 * Money is an integer count of 分 (fen, 1/100 CNY). No float ever touches an
 * amount: `0.1 + 0.2` is the one bug an accounting app may not have.
 *
 * Formatting is split into parts rather than returned as a string because the
 * design sets the fractional digits smaller and lighter than the integer part,
 * and that treatment must exist in exactly one place per platform. The Swift
 * mirror in ios/Countbook/Core/Money.swift is verified against the same
 * fixtures in design/fixtures/money.json.
 */

export type Fen = number

/** U+2212 MINUS SIGN — the hyphen is too short to read as a number's sign. */
export const MINUS = '−'

export interface MoneyParts {
  /** '' or MINUS. Never '+'. */
  sign: string
  symbol: string
  /** Grouped integer part, e.g. '1,238'. */
  int: string
  /** Always two digits, e.g. '40'. */
  frac: string
}

const SYMBOLS: Record<string, string> = { CNY: '¥', USD: '$', EUR: '€', GBP: '£', JPY: '¥', HKD: 'HK$' }

export function symbolFor(currency: string): string {
  return SYMBOLS[currency] ?? currency + ' '
}

function group(digits: string): string {
  // Manual grouping rather than toLocaleString: the output must be byte-identical
  // to the Swift implementation regardless of the device's locale settings.
  let out = ''
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ','
    out += digits[i]
  }
  return out
}

export function parts(fen: Fen, currency = 'CNY'): MoneyParts {
  const n = Math.trunc(fen)
  const neg = n < 0
  const abs = Math.abs(n)
  return {
    sign: neg ? MINUS : '',
    symbol: symbolFor(currency),
    int: group(String(Math.floor(abs / 100))),
    frac: String(abs % 100).padStart(2, '0'),
  }
}

/** The full string, for accessibility labels, exports and tests. */
export function format(fen: Fen, currency = 'CNY'): string {
  const p = parts(fen, currency)
  return `${p.sign}${p.symbol}${p.int}.${p.frac}`
}

/** Rounded to whole 元, for dense chart labels where 分 would be noise. */
export function formatYuan(fen: Fen, currency = 'CNY'): string {
  const p = parts(Math.trunc(fen / 100) * 100, currency)
  return `${p.sign}${p.symbol}${p.int}`
}

/**
 * Parse what a person typed into 分. Accepts '12', '12.3', '12.34', '¥12.34',
 * '1,234.5'. Rejects anything else — including more than two decimals, which is
 * a typo rather than a precision the currency has.
 */
export function parse(input: string): Fen | null {
  const s = input.trim().replace(/[¥$€£,\s]/g, '').replace(/^−/, '-')
  if (!/^-?\d*(\.\d{0,2})?$/.test(s) || s === '' || s === '-' || s === '.') return null
  const neg = s.startsWith('-')
  const [intPart = '0', fracPart = ''] = s.replace('-', '').split('.')
  const fen = Number(intPart || '0') * 100 + Number((fracPart + '00').slice(0, 2))
  return neg ? -fen : fen
}

/**
 * Split a total across n buckets so the parts sum exactly to the total; the
 * remainder lands in the last bucket. Used by 今日可用, which divides what is
 * left by the days remaining and may not lose a 分 in the process.
 */
export function divideRemainderLast(total: Fen, n: number): { per: Fen; last: Fen } {
  if (n <= 0) return { per: 0, last: total }
  const per = Math.trunc(total / n)
  return { per, last: total - per * (n - 1) }
}

export const sum = (xs: readonly Fen[]): Fen => xs.reduce((a, b) => a + b, 0)
