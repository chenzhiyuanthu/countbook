import SwiftUI

/// The ornament set (DESIGN.md §8.4): a mark beside a word, never a word's
/// replacement. Drawn from design/icons.json — the one file both clients read —
/// on the same 24 grid, stroke and caps as the hand-drawn set in Primitives.
/// It appears in exactly two places: the tab bar, and a section's title.
/// Colour is never set; the mark takes the ink of the word it sits beside.
enum GlyphName: String, CaseIterable, Sendable {
    case today, ledger, report, wants, settings
    case standard, wish, sync, categories, appearance, data, about
    case cashflow, regret, deviation, rate, hours, year
}

struct Glyph: View {
    let name: GlyphName
    var size: CGFloat = 16

    var body: some View {
        GlyphShape(name: name)
            .stroke(style: StrokeStyle(lineWidth: GlyphSet.shared.stroke * size / 24, lineCap: .butt, lineJoin: .miter))
            .overlay {
                // The only filled marks in the set: a dot is a square on the grid.
                GlyphDots(name: name).fill()
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The parsed file. Paths are absolute `M L H V Z` only, which is all the
/// reader below understands; a glyph that needs more is drawn by hand in
/// Primitives, not added here.
struct GlyphSet: Sendable {
    struct Circle: Sendable { let cx: CGFloat; let cy: CGFloat; let r: CGFloat }
    struct Dot: Sendable { let x: CGFloat; let y: CGFloat }
    struct Drawing: Sendable {
        var stroke: [String] = []
        var circles: [Circle] = []
        var dots: [Dot] = []
    }

    let stroke: CGFloat
    let dot: CGFloat
    let glyphs: [String: Drawing]

    static let shared: GlyphSet = load()

    private static func load() -> GlyphSet {
        let fallback = GlyphSet(stroke: 1.5, dot: 2, glyphs: [:])
        guard let url = Bundle.main.url(forResource: "icons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["glyphs"] as? [String: [String: Any]]
        else { return fallback }
        var glyphs: [String: Drawing] = [:]
        for (name, spec) in raw {
            var d = Drawing()
            d.stroke = spec["stroke"] as? [String] ?? []
            for c in spec["circles"] as? [[String: Double]] ?? [] {
                guard let cx = c["cx"], let cy = c["cy"], let r = c["r"] else { continue }
                d.circles.append(Circle(cx: cx, cy: cy, r: r))
            }
            for p in spec["dots"] as? [[String: Double]] ?? [] {
                guard let x = p["x"], let y = p["y"] else { continue }
                d.dots.append(Dot(x: x, y: y))
            }
            glyphs[name] = d
        }
        let stroke = (root["stroke"] as? Double).map { CGFloat($0) } ?? 1.5
        let dot = (root["dot"] as? Double).map { CGFloat($0) } ?? 2
        return GlyphSet(stroke: stroke, dot: dot, glyphs: glyphs)
    }

    /// Absolute `M x y`, `L x y`, `H x`, `V y`, `Z`; anything else is skipped.
    static func path(_ d: String, into path: inout Path, unit: CGFloat, origin: CGPoint) {
        // "M8 19 V5" — a command letter may be glued to its first number, as
        // SVG allows and the file writes; pad every letter so the split is clean.
        var padded = ""
        for ch in d { padded += ch.isLetter ? " \(ch) " : String(ch) }
        let tokens = padded.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        var i = 0
        var current = CGPoint.zero
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }
        while i < tokens.count {
            let cmd = tokens[i]
            switch cmd {
            case "M", "L":
                guard i + 2 < tokens.count, let x = Double(tokens[i + 1]), let y = Double(tokens[i + 2]) else { return }
                current = CGPoint(x: x, y: y)
                if cmd == "M" { path.move(to: point(current.x, current.y)) } else { path.addLine(to: point(current.x, current.y)) }
                i += 3
            case "H":
                guard i + 1 < tokens.count, let x = Double(tokens[i + 1]) else { return }
                current.x = x
                path.addLine(to: point(current.x, current.y))
                i += 2
            case "V":
                guard i + 1 < tokens.count, let y = Double(tokens[i + 1]) else { return }
                current.y = y
                path.addLine(to: point(current.x, current.y))
                i += 2
            case "Z":
                path.closeSubpath()
                i += 1
            default:
                return
            }
        }
    }
}

private struct GlyphShape: Shape {
    let name: GlyphName

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let d = GlyphSet.shared.glyphs[name.rawValue] else { return path }
        let unit = min(rect.width, rect.height) / 24
        let origin = CGPoint(x: rect.minX, y: rect.minY)
        for s in d.stroke { GlyphSet.path(s, into: &path, unit: unit, origin: origin) }
        for c in d.circles {
            path.addEllipse(in: CGRect(
                x: origin.x + (c.cx - c.r) * unit, y: origin.y + (c.cy - c.r) * unit,
                width: c.r * 2 * unit, height: c.r * 2 * unit
            ))
        }
        return path
    }
}

private struct GlyphDots: Shape {
    let name: GlyphName

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let d = GlyphSet.shared.glyphs[name.rawValue] else { return path }
        let unit = min(rect.width, rect.height) / 24
        let side = GlyphSet.shared.dot * unit
        for p in d.dots {
            path.addRect(CGRect(x: rect.minX + p.x * unit, y: rect.minY + p.y * unit, width: side, height: side))
        }
        return path
    }
}
