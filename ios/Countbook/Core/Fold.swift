import Foundation

func emptyLedger() -> Ledger {
    Ledger(
        entries: [:],
        tombstones: [],
        corrections: [],
        voids: [],
        categories: Dictionary(uniqueKeysWithValues: DEFAULT_CATEGORIES.map { ($0.id, $0) }),
        wishes: [:],
        subs: [:],
        standards: [],
        settings: DEFAULT_SETTINGS,
        noSpendDays: []
    )
}

/// Fold the log into the ledger. Events arrive already sorted by HLC, so
/// "later event wins" is simply "applied second", and a patch that names only
/// some fields yields per-field last-writer-wins for free.
///
/// Delete wins over a concurrent edit: an entry removed on one device stays
/// removed even if another device patched it afterwards without having seen the
/// removal. Resurrecting a row the user deliberately deleted is the worse
/// failure — they would have to notice it came back to delete it again.
func fold(_ events: [Event]) -> Ledger {
    var L = emptyLedger()

    for e in events {
        switch e.payload {
        case .entryAdd(let entry):
            if !L.tombstones.contains(entry.id) { L.entries[entry.id] = entry }

        case .entryPatch(let target, let patch):
            if let cur = L.entries[target] { L.entries[target] = cur.applying(patch) }

        case .entryRemove(let target):
            L.entries[target] = nil
            L.tombstones.insert(target)

        case .entryCorrect(let target, let amount, let reason):
            L.corrections.append(
                Correction(id: e.id, targetId: target, amount: amount, reason: reason, at: decode(e.hlc).wall)
            )

        case .entryVoid(let target, let reason):
            L.voids.append(Voidance(id: e.id, targetId: target, reason: reason, at: decode(e.hlc).wall))

        case .reviewJudge(let target, let worthIt):
            if var cur = L.entries[target] {
                cur.worthIt = worthIt
                cur.reviewedAt = decode(e.hlc).wall
                L.entries[target] = cur
            }

        case .reviewDefer(let target):
            guard var cur = L.entries[target] else { break }
            let n = (cur.deferrals ?? 0) + 1
            cur.deferrals = n
            // A bounded deferral, not an escape hatch: once the limit is reached
            // the entry records itself as 不值, because refusing to look at it
            // for three weeks running is itself the answer.
            if n >= 3 {
                cur.worthIt = false
                cur.reviewedAt = decode(e.hlc).wall
            }
            L.entries[target] = cur

        case .wishAdd(let wish):
            L.wishes[wish.id] = wish

        case .wishResolve(let target, let outcome, let entryId):
            if var w = L.wishes[target] {
                w.outcome = outcome
                w.resolvedAt = decode(e.hlc).wall
                w.entryId = entryId
                L.wishes[target] = w
            }

        case .wishRemove(let target):
            L.wishes[target] = nil

        case .subUpsert(let sub):
            L.subs[sub.id] = sub.merged(over: L.subs[sub.id])

        case .subStatus(let target, let status, let day):
            if var s = L.subs[target] {
                s.status = status
                if let day { s.cancelledAt = day }
                L.subs[target] = s
            }

        case .subUse(let target, let day):
            if var s = L.subs[target] {
                s.usageDays = (s.usageDays ?? []) + [day]
                L.subs[target] = s
            }

        case .subRemove(let target):
            L.subs[target] = nil

        case .standardSet(let monthlyFen, let perCategory, let reason):
            L.standards.append(
                StandardRevision(
                    id: e.id,
                    at: decode(e.hlc).wall,
                    monthlyFen: monthlyFen,
                    perCategory: perCategory,
                    reason: (reason?.isEmpty ?? true) ? nil : reason
                )
            )

        case .categoryUpsert(let category):
            L.categories[category.id] = category

        case .categoryRemove(let target):
            // Archived, never deleted: entries filed under it must keep their label.
            if var c = L.categories[target] {
                c.archived = true
                L.categories[target] = c
            }

        case .settingsPatch(let patch):
            L.settings = L.settings.applying(patch)

        case .dayNospend(let day, let on):
            if on { L.noSpendDays.insert(day) } else { L.noSpendDays.remove(day) }
        }
    }

    // Stable so that two revisions stamped in the same millisecond keep the
    // order the log gave them, which is the order the HLC counter decided.
    L.corrections = stableSorted(L.corrections) { $0.at < $1.at }
    L.standards = stableSorted(L.standards) { $0.at < $1.at }
    return L
}

private func stableSorted<T>(_ xs: [T], by less: (T, T) -> Bool) -> [T] {
    xs.enumerated()
        .sorted { l, r in
            less(l.element, r.element) ? true : (less(r.element, l.element) ? false : l.offset < r.offset)
        }
        .map(\.element)
}

// MARK: - derived views over the audit trail

/// An entry as the totals see it. The stored `entry` is untouched — the ledger
/// prints both rows — so the forwarding subscript reads the original's fields
/// while `effective` carries what the correction or voidance made of it.
@dynamicMemberLookup
struct EffectiveEntry: Equatable, Sendable {
    var entry: Entry
    /// The amount aggregates must use: corrected, or 0 if the row was voided.
    var effective: Fen
    var correction: Correction?
    var voidance: Voidance?

    subscript<T>(dynamicMember keyPath: KeyPath<Entry, T>) -> T { entry[keyPath: keyPath] }
}

/// Resolve corrections and voidances onto the entries. The originals are never
/// changed — the ledger prints both — but every total in the app is computed
/// from `effective`.
func effective(_ L: Ledger) -> [String: EffectiveEntry] {
    var latestCorrection: [String: Correction] = [:]
    for c in L.corrections { latestCorrection[c.targetId] = c } // sorted, so last wins
    var voided: [String: Voidance] = [:]
    for v in L.voids { voided[v.targetId] = v }

    var out: [String: EffectiveEntry] = [:]
    out.reserveCapacity(L.entries.count)
    for (id, e) in L.entries {
        let c = latestCorrection[id]
        let v = voided[id]
        out[id] = EffectiveEntry(
            entry: e,
            effective: v != nil ? 0 : (c?.amount ?? e.amount),
            correction: c,
            voidance: v
        )
    }
    return out
}

/// The standard in force for a given month, i.e. the latest revision made before it ended.
func standardAt(_ L: Ledger, _ atMs: Int) -> (monthlyFen: Fen, perCategory: [String: Fen]) {
    var found: (monthlyFen: Fen, perCategory: [String: Fen]) = (0, [:])
    for s in L.standards where s.at <= atMs {
        found = (s.monthlyFen, s.perCategory)
    }
    return found
}
