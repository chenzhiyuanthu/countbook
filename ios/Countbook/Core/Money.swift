import Foundation

/// An integer count of 分 (1/100 CNY). No `Double` ever touches an amount:
/// `0.1 + 0.2` is the one bug an accounting app may not have.
typealias Fen = Int

/// U+2212 MINUS SIGN — the hyphen is too short to read as a number's sign.
let minus = "−"

/// Formatting is split into parts rather than returned as a string because the
/// design sets the fractional digits smaller and lighter than the integer part,
/// and that treatment must exist in exactly one place per platform.
struct MoneyParts: Equatable, Sendable {
    /// `""` or `minus`. Never `"+"`.
    let sign: String
    let symbol: String
    /// Grouped integer part, e.g. `"1,238"`.
    let int: String
    /// Always two digits, e.g. `"40"`.
    let frac: String
}

private let currencySymbols: [String: String] = [
    "CNY": "¥", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "HKD": "HK$",
]

func symbolFor(_ currency: String) -> String {
    currencySymbols[currency] ?? currency + " "
}

// Grouped by hand rather than through a locale-aware formatter: a device set to
// a different region would otherwise produce a different string, and the web
// client and this one must agree byte for byte (design/fixtures/money.json).
private func group(_ digits: String) -> String {
    let n = digits.count
    var out = ""
    out.reserveCapacity(n + n / 3)
    for (i, ch) in digits.enumerated() {
        if i > 0 && (n - i) % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return out
}

func parts(_ fen: Fen, currency: String = "CNY") -> MoneyParts {
    // `magnitude` rather than `abs`, which traps on Int.min.
    let mag = fen.magnitude
    let frac = mag % 100
    return MoneyParts(
        sign: fen < 0 ? minus : "",
        symbol: symbolFor(currency),
        int: group(String(mag / 100)),
        frac: frac < 10 ? "0\(frac)" : "\(frac)"
    )
}

/// The full string, for accessibility labels, exports and tests.
func format(_ fen: Fen, currency: String = "CNY") -> String {
    let p = parts(fen, currency: currency)
    return "\(p.sign)\(p.symbol)\(p.int).\(p.frac)"
}

/// Rounded to whole 元, for dense chart labels where 分 would be noise.
func formatYuan(_ fen: Fen, currency: String = "CNY") -> String {
    let p = parts(fen / 100 * 100, currency: currency)
    return "\(p.sign)\(p.symbol)\(p.int)"
}

/// Parse what a person typed into 分. Accepts `12`, `12.3`, `12.34`, `¥12.34`,
/// `1,234.5`. Rejects anything else — including more than two decimals, which
/// is a typo rather than a precision the currency has.
func parse(_ input: String) -> Fen? {
    var s = ""
    s.reserveCapacity(input.count)
    for ch in input where !(ch == "¥" || ch == "$" || ch == "€" || ch == "£" || ch == "," || ch.isWhitespace) {
        s.append(ch)
    }
    if s.hasPrefix(minus) { s = "-" + s.dropFirst() }
    if s.isEmpty || s == "-" || s == "." { return nil }

    var rest = Substring(s)
    let negative = rest.hasPrefix("-")
    if negative { rest = rest.dropFirst() }

    var intPart = ""
    while let c = rest.first, c.isASCIIDigit { intPart.append(c); rest = rest.dropFirst() }

    var fracPart = ""
    if rest.first == "." {
        rest = rest.dropFirst()
        while let c = rest.first, c.isASCIIDigit { fracPart.append(c); rest = rest.dropFirst() }
    }
    guard rest.isEmpty, fracPart.count <= 2 else { return nil }

    guard let whole = intPart.isEmpty ? 0 : Int(intPart),
          let frac = Int((fracPart + "00").prefix(2))
    else { return nil }
    let scaled = whole.multipliedReportingOverflow(by: 100)
    guard !scaled.overflow else { return nil }
    let total = scaled.partialValue.addingReportingOverflow(frac)
    guard !total.overflow else { return nil }
    return negative ? -total.partialValue : total.partialValue
}

/// Split a total across `n` buckets so the parts sum exactly to the total; the
/// remainder lands in the last bucket. Used by 今日可用, which divides what is
/// left by the days remaining and may not lose a 分 in the process.
func divideRemainderLast(_ total: Fen, _ n: Int) -> (per: Fen, last: Fen) {
    guard n > 0 else { return (per: 0, last: total) }
    let per = total / n
    return (per: per, last: total - per * (n - 1))
}

private extension Character {
    // JavaScript's `\d` is ASCII-only; `isNumber` would also accept ٤ and ４.
    var isASCIIDigit: Bool { isASCII && isNumber }
}

// MARK: - foreign currency

/// A rate is carried as millionths: 7.1234 → 7_123_400.
let rateScale = 1_000_000

/// Convert minor units of one currency into minor units of another at a rate
/// in millionths, rounding half away from zero. Int is 64-bit on every device
/// this runs on, and ¥999,999.99 at a four-figure rate stays well inside it;
/// the web client does the same in BigInt and lands on the same 分 for the
/// same inputs (design/fixtures/fx.json).
func convert(_ amountMinor: Fen, rateMicro: Int) -> Fen {
    let q = amountMinor * rateMicro
    let half = rateScale / 2
    return q >= 0 ? (q + half) / rateScale : -((-q + half) / rateScale)
}

/// "7.1234" — four decimals, trailing zeros trimmed down to two.
func formatRate(_ rateMicro: Int) -> String {
    let int = rateMicro / rateScale
    var frac = String(rateMicro % rateScale)
    frac = String(repeating: "0", count: max(0, 6 - frac.count)) + frac
    frac = String(frac.prefix(4))
    while frac.count > 2, frac.hasSuffix("0") { frac.removeLast() }
    return "\(int).\(frac)"
}

/// Parse a typed rate ("7.12", "0.0431") into millionths; nil if it is not one.
func parseRate(_ input: String) -> Int? {
    let s = input.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return nil }
    let pieces = s.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count <= 2 else { return nil }
    let intPart = String(pieces[0])
    let fracPart = pieces.count == 2 ? String(pieces[1]) : ""
    guard !intPart.isEmpty, intPart.allSatisfy(\.isASCIIDigit), fracPart.count <= 6, fracPart.allSatisfy(\.isASCIIDigit),
          let int = Int(intPart)
    else { return nil }
    let frac = Int(fracPart + String(repeating: "0", count: 6 - fracPart.count)) ?? 0
    let micro = int * rateScale + frac
    return micro > 0 ? micro : nil
}
