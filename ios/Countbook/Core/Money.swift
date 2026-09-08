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
          let frac = Int((fracPart + "00").prefix(2)),
          case let (scaled, overflowed) = whole.multipliedReportingOverflow(by: 100), !overflowed,
          case let (total, carried) = scaled.addingReportingOverflow(frac), !carried
    else { return nil }
    return negative ? -total : total
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
