import Foundation
import Observation
import Security
import UIKit

/// One store for the whole app. Everything the UI shows is derived from the
/// event log by `fold`, so there is no second source of truth to keep in step
/// and no possibility of the screen disagreeing with the ledger.

struct ToastAction {
    var label: String
    var run: () -> Void
}

struct ToastState: Identifiable {
    var id: Int
    var message: String
    var action: ToastAction?
}

@MainActor
@Observable
final class Store {
    private(set) var ready = false
    private(set) var ledger = emptyLedger()
    private(set) var events: [Event] = []
    private(set) var toastState: ToastState?

    /// The date only matters to the day, so it is refreshed on a timer rather
    /// than read inside a view body, which would make the view impure.
    var today: Day
    var now: Date

    var locale: Settings.Locale { ledger.settings.locale }

    /// Sync is told about local writes through a closure so the store never has
    /// to know that sync exists; with it unset the app is fully usable.
    @ObservationIgnored var onLocalWrite: (() -> Void)?

    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private let device: String
    @ObservationIgnored private let file: EventFile
    @ObservationIgnored private var writes = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var foreground: NSObjectProtocol?

    init(file: EventFile = EventFile(), defaults: UserDefaults = .standard) {
        self.file = file
        device = Store.installationID(defaults)
        clock = Clock(device: device)
        let start = Date()
        now = start
        today = toDay(start)
        S.locale = ledger.settings.locale
    }

    deinit {
        ticker?.cancel()
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
    }

    /// Idempotent: the log is read once, then the clock sources are attached.
    func start() async {
        guard !started else { return }
        started = true
        let stored = await file.read()
        adopt(sort(stored), persist: false)
        ready = true
        watchTime()
    }

    // MARK: - the log

    /// Append an event. Returns its id so a caller can undo exactly this one.
    @discardableResult
    func commit(_ payload: Payload) -> String {
        let event = Event(id: newID(), hlc: clock.next(), dev: device, payload: payload)
        adopt(sort(events + [event]))
        onLocalWrite?()
        return event.id
    }

    /// Fold in events that arrived from another device.
    func absorb(_ incoming: [Event]) {
        guard !incoming.isEmpty else { return }
        for e in incoming { clock.observe(e.hlc) }
        let next = merge(events, incoming)
        guard next.count != events.count else { return }
        adopt(next)
    }

    /// Undo removes the event outright rather than appending a compensating one.
    /// It is only ever offered for something committed seconds ago on this
    /// device, so no other device can have seen it, and a log without the
    /// mistake is cleaner than a log with a mistake and its retraction.
    func undo(eventID: String) {
        adopt(events.filter { $0.id != eventID })
    }

    func replaceAll(_ next: [Event]) {
        let sorted = sort(next)
        for e in sorted { clock.observe(e.hlc) }
        adopt(sorted)
    }

    private func adopt(_ next: [Event], persist: Bool = true) {
        events = next
        ledger = fold(next)
        S.locale = ledger.settings.locale
        if persist {
            writes += 1
            let seq = writes
            // Saving is never allowed to make an entry feel slow, so the encode
            // and the write both happen off this actor.
            Task.detached(priority: .utility) { [file] in await file.write(next, seq: seq) }
        }
    }

    // MARK: - toast

    func toast(_ message: String, action: ToastAction? = nil) {
        toastState = ToastState(id: nowMillis(), message: message, action: action)
    }

    func dismissToast() {
        toastState = nil
    }

    // MARK: - the clock

    private func watchTime() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
        foreground = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let date = Date()
        now = date
        let day = toDay(date)
        if day != today { today = day }
    }

    // MARK: - identity

    /// 128 bits of CSPRNG output in lowercase hex, matching the web client's ids.
    private func newID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// A stable per-installation identifier; the HLC's tiebreaker.
    private static func installationID(_ defaults: UserDefaults) -> String {
        let key = "countbook.device"
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let fresh = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        defaults.set(fresh, forKey: key)
        return fresh
    }
}

/// The event log on disk: one JSON file in Application Support, written whole
/// and atomically. A ledger kept for years is still small enough that rewriting
/// it costs less than maintaining an incremental format that could half-write.
actor EventFile {
    private let url: URL
    private var written = 0

    init(url: URL? = nil) {
        self.url = url ?? EventFile.defaultURL()
    }

    private static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Countbook", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }

    func read() -> [Event] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
    }

    /// Writes arrive as separate tasks, so they can be scheduled out of order;
    /// the sequence number keeps a stale snapshot from overwriting a newer one.
    func write(_ events: [Event], seq: Int) {
        guard seq > written else { return }
        written = seq
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
