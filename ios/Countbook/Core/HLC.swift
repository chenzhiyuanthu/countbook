import Foundation

/// A hybrid logical clock. Events are ordered by (wall, counter, device), a
/// total order that is stable across devices and survives a device whose clock
/// is wrong: the counter advances monotonically even when wall time goes
/// backwards, so a laggy phone can never silently overwrite a newer edit made
/// on a correct clock.
///
/// Encoded as a fixed-width sortable string so ordering is plain lexicographic
/// comparison in both TypeScript and Swift, and in any store that only sorts
/// strings.
///
///     0000018f2c3a4b5d-0007-a1b2c3d4
///     |--------------|  |--| |------|
///      wall ms, hex 16   ctr  device
struct Hlc: Equatable, Sendable {
    var wall: Int
    var counter: Int
    var device: String
}

private func hex(_ n: Int, _ width: Int) -> String {
    let s = String(n, radix: 16)
    return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
}

func encode(_ h: Hlc) -> String {
    "\(hex(h.wall, 16))-\(hex(h.counter, 4))-\(h.device)"
}

func decode(_ s: String) -> Hlc {
    let f = s.split(separator: "-", omittingEmptySubsequences: false)
    return Hlc(
        wall: f.count > 0 ? Int(f[0], radix: 16) ?? 0 : 0,
        counter: f.count > 1 ? Int(f[1], radix: 16) ?? 0 : 0,
        device: f.count > 2 ? String(f[2]) : ""
    )
}

/// Lexicographic order on the encoding is the intended total order.
func compare(_ a: String, _ b: String) -> Int {
    a < b ? -1 : (a > b ? 1 : 0)
}

/// Epoch milliseconds, the unit the encoding stores.
func nowMillis() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

final class Clock {
    let device: String
    private let now: () -> Int
    private var wall = 0
    private var counter = 0

    init(device: String, now: @escaping () -> Int = nowMillis) {
        self.device = device
        self.now = now
    }

    /// Stamp a locally-created event.
    func next() -> String {
        let t = now()
        if t > wall {
            wall = t
            counter = 0
        } else {
            counter += 1
        }
        return encode(Hlc(wall: wall, counter: counter, device: device))
    }

    /// Fold in a timestamp seen from another device, so our next stamp sorts
    /// after anything we have already observed.
    func observe(_ stamp: String) {
        let r = decode(stamp)
        let t = now()
        let merged = max(wall, r.wall, t)
        if merged == wall && merged == r.wall {
            counter = max(counter, r.counter) + 1
        } else if merged == r.wall {
            counter = r.counter + 1
        } else if merged == wall {
            counter += 1
        } else {
            counter = 0
        }
        wall = merged
    }
}
