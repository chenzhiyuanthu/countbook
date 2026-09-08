# 据实 Countbook — Data Model & Sync Protocol Specification

**Document status:** normative, v1.
**Applies to:** `web/` (Vite + React 19 + TypeScript, WebCrypto), `ios/` (SwiftUI, Foundation + CryptoKit + CommonCrypto), `server/` (Node + SQLite, stdlib only).
**Constants defined here:** `CBV1` envelope, `protocolVersion = 1`, `schemaVersion = 1`.

Every byte-level rule in this document is a contract between two independent implementations. Where a rule says MUST, a violation is a data-loss bug, not a style preference. Keywords MUST / MUST NOT / SHOULD / MAY are used per RFC 2119.

---

## 0. Design summary — the five decisions everything else follows from

| # | Decision | Rationale (long form in the cited section) |
|---|---|---|
| 1 | **Event-sourced append-only log; state is a pure fold of the event *set*.** | The product thesis is an incorruptible record (更正/冲销 instead of mutation). The storage model and the product argument are the same object. §2 |
| 2 | **Hybrid Logical Clock, not `(wallClock, id)`.** | HLC repairs skew on contact and preserves causality. `(ts,id)` lets one badly-set clock win every conflict for the whole duration of the skew, with no self-healing. §2.3 |
| 3 | **Per-field Last-Writer-Wins registers over a grow-only event set.** | Yields a join-semilattice: merge is commutative, associative and idempotent with no vector clocks and no server-side merge. §2.7, §2.10 |
| 4 | **结账 (month sealing) is derived from the event's own HLC plus immutable vault config — never from another event.** | Keeps admissibility a *local* predicate on a single event, which is exactly what makes snapshots and compaction safe. §2.6 |
| 5 | **The transport unit is an encrypted, immutable, randomly-named *segment*; the only mutable object is a single *index* guarded by compare-and-swap.** | Reduces both adapters to "immutable object store + one CAS cell". GitHub and the self-hosted server implement the same four verbs. §4, §6, §7 |

In either adapter the server never sees plaintext, never merges, never validates a domain rule and never orders events. It is a dumb, hostile-by-assumption object store. All correctness lives in the client fold.

---

## 1. Core domain types

### 1.0 Conventions

- **Money** is always an integer in **minor units (分, CNY cents)**. Never a float, never a string, never `Decimal`. Field names carrying money MUST end in `Fen`. Valid range `[-10^13, 10^13]`, well inside IEEE-754 safe-integer range so JSON round-trips exactly.
- **Ids** are 128 bits of CSPRNG output rendered as **26-character Crockford Base32, uppercase, unpadded** (alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`). Type alias `Id`. They are opaque and carry **no timestamp** — ULIDs would leak write times through object filenames (§9.4).
- **Instants** are integer **milliseconds since the Unix epoch, UTC**; field suffix `…At`.
- **Civil dates** are `"YYYY-MM-DD"` in the **user's local calendar at the moment of the event**; field suffix `…On`. Both forms are stored: travelling across time zones must not reshuffle which day a coffee belongs to. `tzOffsetMin` records the offset used, for audit only — it is never an aggregation input.
- **Enums on the wire** are small integers, never strings, and are never renumbered. Adding a variant is a minor bump; changing one is a new vault format.
- **Text** is stored **NFC-normalised** (`String.prototype.normalize("NFC")` / `String.precomposedStringWithCanonicalMapping`). Un-normalised text breaks canonical hashing across platforms.
- **Optionality**: absent and `null` mean the same thing; canonical serialisation MUST omit rather than emit `null` (§4.1).
- **No floats anywhere in the persisted model.** `scripts/lint-model.mjs` and a Swift build-phase grep both fail the build on `Double`/`Float`/`number` used for money. The single exception is `detectorEvidence.stddevDays`, which is advisory display data and is explicitly excluded from every hash and aggregate.

### 1.1 Enumerations

```ts
/** 记账印章 — the mandatory intent stamp. No default, never inferred. */
export const enum Intent { Necessary = 0, Wanted = 1, Impulse = 2 } // 必要 / 想要 / 冲动

export const enum Flow { Expense = 0, Income = 1, Transfer = 2 }

/** Sunday verdict. */
export const enum Verdict { Unjudged = 0, Worth = 1, NotWorth = 2 } // 未判 / 值 / 不值

/** How a NotWorth verdict was reached — see the 未敢面对 rule, §2.5.7. */
export const enum VerdictSource { User = 0, ExhaustedDeferrals = 1 }

export const enum AccountKind { Cash = 0, Bank = 1, EWallet = 2, Credit = 3, Prepaid = 4 }

export const enum RecurPeriod { Weekly = 0, Monthly = 1, Quarterly = 2, SemiAnnual = 3, Annual = 4 }

/** 认领 — detected subscriptions start unclaimed; the user signs for each row. */
export const enum SubClaim { Unclaimed = 0, Keep = 1, ToCancel = 2, Cancelled = 3 }

export const enum WishState { Cooling = 0, Unlocked = 1, Bought = 2, Abandoned = 3 }

export const enum Platform { Web = 0, IOS = 1 }
```

```swift
public enum Intent: Int, Codable, Sendable { case necessary = 0, wanted = 1, impulse = 2 }
public enum Flow: Int, Codable, Sendable { case expense = 0, income = 1, transfer = 2 }
public enum Verdict: Int, Codable, Sendable { case unjudged = 0, worth = 1, notWorth = 2 }
public enum VerdictSource: Int, Codable, Sendable { case user = 0, exhaustedDeferrals = 1 }
public enum AccountKind: Int, Codable, Sendable { case cash = 0, bank = 1, eWallet = 2, credit = 3, prepaid = 4 }
public enum RecurPeriod: Int, Codable, Sendable { case weekly = 0, monthly = 1, quarterly = 2, semiAnnual = 3, annual = 4 }
public enum SubClaim: Int, Codable, Sendable { case unclaimed = 0, keep = 1, toCancel = 2, cancelled = 3 }
public enum WishState: Int, Codable, Sendable { case cooling = 0, unlocked = 1, bought = 2, abandoned = 3 }
public enum Platform: Int, Codable, Sendable { case web = 0, ios = 1 }
```

Unknown enum integers decode to a `.unknown(raw)` case on both platforms (Swift: a manual `init(from:)` falling back; TS: a runtime guard) and the owning entity is **rendered but not aggregated**. A forward-compatible client must never crash and must never silently coerce an unknown variant to `0`.

### 1.2 Primitive aliases

```ts
export type Id = string;          // 26-char Crockford Base32
export type Hlc = string;         // 26-char sortable stamp, §2.3
export type Fen = number;         // integer minor units
export type CivilDate = string;   // "YYYY-MM-DD"
export type Millis = number;      // integer epoch ms, UTC
```

```swift
public typealias Id = String
public typealias Hlc = String
public typealias Fen = Int64
public typealias CivilDate = String
public typealias Millis = Int64
```

`Fen` is `Int64` in Swift and MUST encode as a JSON integer literal (`JSONEncoder` does this natively for `Int64`). TypeScript uses `number` with a `assertSafeInteger()` guard at every deserialisation boundary.

### 1.3 `Txn` — 账目

```ts
export interface Txn {
  id: Id;
  /** Always positive. Direction is carried by `flow`. */
  amountFen: Fen;
  flow: Flow;
  categoryId: Id;
  accountId: Id;
  /** Mandatory. There is no default and no inference. §2.5.1 */
  intent: Intent;
  note: string;               // ≤ 140 chars, NFC, may be ""
  /** 「这笔钱能换来什么？」 captured only for Impulse entries above the cooling
   *  threshold; quoted verbatim on the Sunday verdict card. ≤ 20 chars. */
  reason?: string;
  merchant?: string;          // ≤ 60 chars, raw; input to the recurring detector
  occurredOn: CivilDate;      // local civil date — THE aggregation key
  occurredAt: Millis;         // exact instant — for the 24-column hour scatter
  tzOffsetMin: number;        // e.g. 480 for UTC+8
  createdAt: Millis;
  createdBy: Id;              // deviceId
  verdict: Verdict;
  verdictSource?: VerdictSource;
  reviewedAt?: Millis;
  deferCount: number;         // 0..3, §2.5.7
  wishId?: Id;                // set when created via 记入账页 from the want list
  subscriptionId?: Id;        // set when generated from a Subscription schedule
  /** Soft delete. Admissible only while the period is open. §2.6 */
  deletedAt?: Millis;
  /** Derived by the fold; never serialised into an event. */
  readonly effectiveAmountFen?: Fen;
  readonly voided?: boolean;
}
```

```swift
public struct Txn: Codable, Equatable, Sendable, Identifiable {
    public var id: Id
    public var amountFen: Fen
    public var flow: Flow
    public var categoryId: Id
    public var accountId: Id
    public var intent: Intent
    public var note: String
    public var reason: String?
    public var merchant: String?
    public var occurredOn: CivilDate
    public var occurredAt: Millis
    public var tzOffsetMin: Int
    public var createdAt: Millis
    public var createdBy: Id
    public var verdict: Verdict
    public var verdictSource: VerdictSource?
    public var reviewedAt: Millis?
    public var deferCount: Int
    public var wishId: Id?
    public var subscriptionId: Id?
    public var deletedAt: Millis?

    // Derived by the fold; excluded from Codable.
    public internal(set) var effectiveAmountFen: Fen?
    public internal(set) var voided: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, amountFen, flow, categoryId, accountId, intent, note, reason,
             merchant, occurredOn, occurredAt, tzOffsetMin, createdAt, createdBy,
             verdict, verdictSource, reviewedAt, deferCount, wishId, subscriptionId, deletedAt
    }
}
```

**Invariants.** Checked at capture and re-checked in the fold. A violation quarantines the event (§2.8); it is never silently coerced.

- `amountFen > 0`.
- `intent` present. A `txn.create` payload without `intent` is malformed: `quarantine.reason = "missing-intent"`.
- `reason` SHOULD be present iff `intent == Impulse && amountFen >= config.coolingThresholdFen` at capture. Absence is not an error (thresholds change, older clients exist); it only means the Sunday card prints no quote.
- `occurredOn` MUST equal the civil date of `occurredAt` shifted by `tzOffsetMin`.

### 1.4 `Correction` / `Voidance` — 更正 / 冲销

Sealed-period edits never mutate a `Txn`. They append an immutable child record that is printed forever beneath its parent.

```ts
export interface Correction {
  id: Id;
  txnId: Id;
  fromAmountFen: Fen;   // effective amount at authoring time — display only, never authoritative
  toAmountFen: Fen;
  reason: string;       // 事由 — required, ≥ 2 chars after trimming
  createdAt: Millis;
  createdBy: Id;
}

export interface Voidance {   // 冲销
  id: Id;
  txnId: Id;
  reason: string;       // ≥ 2 chars
  createdAt: Millis;
  createdBy: Id;
}
```

```swift
public struct Correction: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var txnId: Id
    public var fromAmountFen: Fen; public var toAmountFen: Fen
    public var reason: String; public var createdAt: Millis; public var createdBy: Id
}
public struct Voidance: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var txnId: Id
    public var reason: String; public var createdAt: Millis; public var createdBy: Id
}
```

`effectiveAmountFen(txn)` = the `toAmountFen` of the correction with the **greatest HLC** among that txn's corrections, else `txn.amountFen`. `voided(txn)` = at least one `Voidance` exists. A voided txn contributes `0` to every aggregate but stays printed in 账页 with its 冲销 row. Note that `fromAmountFen` being display-only is what makes concurrent corrections safe: two devices correcting the same txn produce two rows, the later HLC wins the effective value, and both rows remain visible — which is exactly the intended semantics of a correction ledger.

### 1.5 `Category` — 类目

```ts
export interface Category {
  id: Id;
  name: string;                     // ≤ 12 chars
  nameEn?: string;
  ordinal: number;                  // display order in the 3×4 capture grid; ties broken by id
  archived: boolean;
  standardFen?: Fen;                // per-period category standard; absent = none set
  detectorMinOccurrences: number;   // default 3; 餐饮 seeds 5 to kill the weekly-lunch false positive
  builtin: boolean;
}
```

```swift
public struct Category: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var name: String; public var nameEn: String?
    public var ordinal: Int; public var archived: Bool
    public var standardFen: Fen?; public var detectorMinOccurrences: Int; public var builtin: Bool
}
```

**Seed categories.** On first run the client writes twelve `category.create` events with **fixed ids**, so two devices bootstrapping the same passphrase independently do not produce twenty-four categories. This is the one deliberate exception to the random-id rule of §1.0.

| ordinal | 名称 | id |
|---|---|---|
| 0 | 餐饮 | `CB0000000000000000000CAT01` |
| 1 | 交通 | `CB0000000000000000000CAT02` |
| 2 | 日用 | `CB0000000000000000000CAT03` |
| 3 | 服饰 | `CB0000000000000000000CAT04` |
| 4 | 数码 | `CB0000000000000000000CAT05` |
| 5 | 娱乐 | `CB0000000000000000000CAT06` |
| 6 | 医疗 | `CB0000000000000000000CAT07` |
| 7 | 人情 | `CB0000000000000000000CAT08` |
| 8 | 居住 | `CB0000000000000000000CAT09` |
| 9 | 学习 | `CB0000000000000000000CAT0A` |
| 10 | 订阅 | `CB0000000000000000000CAT0B` |
| 11 | 其他 | `CB0000000000000000000CAT0C` |

Two independent `category.create` events for the same id deduplicate by entity id; their fields then resolve by per-field LWW, which for identical seed values is a no-op.

### 1.6 `Budget` — 标准线 (UI: 月度标准 / 类目标准)

```ts
export interface Budget {
  /** Deterministic id: "BUDGET" for the total, else the categoryId. */
  id: Id | "BUDGET";
  scope: "total" | "category";
  categoryId?: Id;
  standardFen: Fen;           // per period
  proposedFen?: Fen;          // the app's trailing-90-day median at acceptance time
  effectiveFrom: CivilDate;   // period start from which it applies
  setAt: Millis;
  setBy: Id;
}

/** Every change appends one of these. The report footer prints them, dated. */
export interface BudgetRevision {
  id: Id;
  scope: "total" | "category";
  categoryId?: Id;
  fromFen?: Fen;              // absent for the first setting
  toFen: Fen;
  effectiveFrom: CivilDate;
  at: Millis;
  by: Id;
  /** Threshold changes are logged in the same ledger, so
   *  "I loosened the rule the week I kept failing" is on the record. */
  kind: "budget" | "coolingThreshold" | "leakCeiling" | "reckoning";
}
```

```swift
public struct Budget: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var scope: String; public var categoryId: Id?
    public var standardFen: Fen; public var proposedFen: Fen?
    public var effectiveFrom: CivilDate; public var setAt: Millis; public var setBy: Id
}
public struct BudgetRevision: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var scope: String; public var categoryId: Id?
    public var fromFen: Fen?; public var toFen: Fen
    public var effectiveFrom: CivilDate; public var at: Millis; public var by: Id; public var kind: String
}
```

`Budget` is a **temporal** table, not a mutable cell: the standard in force for period *P* is the revision with the greatest `effectiveFrom ≤ P.start`. Retroactive repainting is therefore impossible by construction — raising your standard in March cannot turn February green.

### 1.7 `Wish` — 待购

```ts
export interface Wish {
  id: Id;
  name: string;               // ≤ 40 chars
  priceFen: Fen;
  categoryId?: Id;
  note?: string;
  /** 「一句话，写给三天后的自己」 — optional, never blocking. ≤ 40 chars. */
  letterToSelf?: string;
  createdAt: Millis;
  createdBy: Id;
  /** Derived at creation and then STORED:
   *    cooldownDays = clamp(ceil(priceFen / 10_000), 1, 14)
   *    unlockAt     = createdAt + cooldownDays * 86_400_000 */
  cooldownDays: number;
  unlockAt: Millis;
  state: WishState;
  resolvedAt?: Millis;
  txnId?: Id;                 // set when state == Bought
}
```

```swift
public struct Wish: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var name: String; public var priceFen: Fen
    public var categoryId: Id?; public var note: String?; public var letterToSelf: String?
    public var createdAt: Millis; public var createdBy: Id
    public var cooldownDays: Int; public var unlockAt: Millis
    public var state: WishState; public var resolvedAt: Millis?; public var txnId: Id?
}
```

`unlockAt` is **stored, not recomputed**, so that a later price edit cannot silently shorten a running cooldown. On `wish.patch` with a new price the merge rule is monotone rather than LWW:

```
unlockAt' = max(unlockAt, createdAt + clamp(ceil(priceFen' / 10_000), 1, 14) * 86_400_000)
```

A price increase extends the cooldown; a price decrease never shortens it. `max` is commutative, associative and idempotent, so this is a legal grow-only register (§2.10) and needs no HLC.

### 1.8 `WishObject` — 心愿物 (the regret exchange rate)

```ts
export interface WishObject { id: Id; name: string; priceFen: Fen; ordinal: number; createdAt: Millis; }
```
```swift
public struct WishObject: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var name: String; public var priceFen: Fen
    public var ordinal: Int; public var createdAt: Millis
}
```

Report line under 本年后悔: `已经买得起它的 ${Math.floor(ytdRegretFen * 100 / wishObject.priceFen)}%`. Integer division in 分, floored, never rounded up. 1–3 objects, `ordinal` 1..3.

### 1.9 `Account` — 账户 (funding source)

Not to be confused with `ServerAccount` (§7.2), the authentication record on the self-hosted adapter.

```ts
export interface Account {
  id: Id;
  name: string;                 // 现金 / 微信 / 支付宝 / 招行信用卡
  kind: AccountKind;
  openingBalanceFen: Fen;       // balances are derived: opening + Σincome − Σexpense ± transfers
  openingOn: CivilDate;
  currency: "CNY";              // v1 is single-currency; the field exists so v2 is not a migration
  archived: boolean;
  ordinal: number;
  statementDay?: number;        // 1..28, credit accounts, feeds 固定待扣 projection
  dueDay?: number;              // 1..28
}
```

```swift
public struct Account: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var name: String; public var kind: AccountKind
    public var openingBalanceFen: Fen; public var openingOn: CivilDate
    public var currency: String; public var archived: Bool; public var ordinal: Int
    public var statementDay: Int?; public var dueDay: Int?
}
```

### 1.10 `Subscription` — 订阅

```ts
export interface Subscription {
  id: Id;
  name: string;
  amountFen: Fen;              // per period
  period: RecurPeriod;
  anchorOn: CivilDate;         // the day-of-period the charge lands
  firstChargedOn: CivilDate;   // for 已付 ¥1,140（自 2022-01）
  categoryId: Id;
  accountId?: Id;
  claim: SubClaim;             // detected rows start Unclaimed — the 认领 flip
  detected: boolean;           // produced by the local detector rather than typed by hand
  detectorEvidence?: { txnIds: Id[]; meanIntervalDays: number; stddevDays: number };
  cancelledOn?: CivilDate;
  readonly annualFen?: Fen;        // derived
  readonly paidToDateFen?: Fen;    // derived
  readonly savedSinceCancelFen?: Fen; // derived, keeps accruing forever
}

/** One tap per use; enables 每次使用 ¥37.5. */
export interface SubscriptionUsage { id: Id; subscriptionId: Id; usedOn: CivilDate; at: Millis; }
```

```swift
public struct Subscription: Codable, Equatable, Sendable, Identifiable {
    public struct DetectorEvidence: Codable, Equatable, Sendable {
        public var txnIds: [Id]; public var meanIntervalDays: Double; public var stddevDays: Double
    }
    public var id: Id; public var name: String; public var amountFen: Fen
    public var period: RecurPeriod; public var anchorOn: CivilDate; public var firstChargedOn: CivilDate
    public var categoryId: Id; public var accountId: Id?
    public var claim: SubClaim; public var detected: Bool
    public var detectorEvidence: DetectorEvidence?
    public var cancelledOn: CivilDate?
}
public struct SubscriptionUsage: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var subscriptionId: Id; public var usedOn: CivilDate; public var at: Millis
}
```

Derived figures use exact integer arithmetic:

```
periodsPerYear = [52, 12, 4, 2, 1]          // Weekly … Annual
annualFen      = amountFen * periodsPerYear[period]
perDayFen      = floor(annualFen / 365)      // remainder displayed nowhere
paidToDateFen  = amountFen * chargeCount(firstChargedOn, min(today, cancelledOn ?? today))
perUseFen      = usageCount == 0 ? nil : floor(paidToDateFen / usageCount)
savedSinceCancelFen = cancelledOn == nil ? 0
                    : amountFen * chargeCount(cancelledOn, today)
```

`chargeCount(a, b)` is a pure calendar function specified in the shared geometry/calendar module (§2.11) and covered by shared fixtures — it is a classic source of TS/Swift divergence around month-end anchors (an `anchorOn` of the 31st in February).

### 1.11 `ZeroSpendDay` — 「今天没花钱」

```ts
export interface ZeroSpendDay { on: CivilDate; at: Millis; by: Id; }
```
```swift
public struct ZeroSpendDay: Codable, Equatable, Sendable { public var on: CivilDate; public var at: Millis; public var by: Id }
```

A day with neither a `Txn` nor a `ZeroSpendDay` is **不记** (unlogged), never "compliant". Silence is never scored as discipline. The entity is keyed by `on`, so two devices marking the same day converge trivially.

### 1.12 `Settings` — mutable preferences

```ts
export interface Settings {
  // Behavioural thresholds. Changes append a BudgetRevision (§1.6).
  leakCeilingFen: Fen;          // default 3_000   (¥30)
  coolingThresholdFen: Fen;     // default 30_000  (¥300)
  reckoningWeekday: number;     // 0 = Sunday
  reckoningHour: number;        // 0..23, default 20
  reckoningCardCap: number;     // default 12
  maxDeferrals: number;         // default 3
  holdRingEnabled: boolean;     // the 3-second linear hold ring on 存入账页
  minJudgedForRates: number;    // default 30 — sample gate for 后悔率 (§2.5.8)
  // Presentation
  locale: "zh-CN" | "en";
  theme: "system" | "light" | "carbon";
  highContrast: boolean;
  reduceMotion: "system" | "always";
  dynamicTypeCap?: number;
  showProposals: boolean;
  // Sync
  syncEnabled: boolean;
  syncAdapter?: "github" | "server";
  autoSyncIntervalSec: number;  // default 900
}
```

```swift
public struct Settings: Codable, Equatable, Sendable {
    public var leakCeilingFen: Fen = 3_000
    public var coolingThresholdFen: Fen = 30_000
    public var reckoningWeekday: Int = 0
    public var reckoningHour: Int = 20
    public var reckoningCardCap: Int = 12
    public var maxDeferrals: Int = 3
    public var holdRingEnabled: Bool = true
    public var minJudgedForRates: Int = 30
    public var locale: String = "zh-CN"
    public var theme: String = "system"
    public var highContrast: Bool = false
    public var reduceMotion: String = "system"
    public var dynamicTypeCap: Double?
    public var showProposals: Bool = true
    public var syncEnabled: Bool = false
    public var syncAdapter: String?
    public var autoSyncIntervalSec: Int = 900
}
```

Every `Settings` field is an independent LWW register (§2.7): two devices changing two different settings concurrently both win.

### 1.13 `VaultConfig` — immutable, fixed at vault creation

This is the mechanism that keeps the fold local. **Nothing here may ever change for the life of a vault.** Changing any of it requires export → create new vault → import (§10.4).

```ts
export interface VaultConfig {
  vaultId: string;            // 32 lowercase hex = 16 bytes
  protocolVersion: 1;
  schemaVersion: 1;
  createdAt: Millis;
  /** Period boundary. 1 = calendar month; 15 means periods run 15th→14th.
   *  Immutable because sealing is derived from it. */
  periodAnchorDay: number;    // 1..28
  /** Hours after a period ends before it seals. Default 24. Immutable. */
  sealGraceHours: number;
  /** Cooling formula denominator, kept here so a stored Wish is always re-verifiable. */
  cooldownFenPerDay: number;  // 10_000
  cooldownMaxDays: number;    // 14
  currency: "CNY";
  timeZoneHint: string;       // IANA name at creation, advisory only
}
```

```swift
public struct VaultConfig: Codable, Equatable, Sendable {
    public let vaultId: String
    public let protocolVersion: Int
    public let schemaVersion: Int
    public let createdAt: Millis
    public let periodAnchorDay: Int
    public let sealGraceHours: Int
    public let cooldownFenPerDay: Int
    public let cooldownMaxDays: Int
    public let currency: String
    public let timeZoneHint: String
}
```

Why `coolingThresholdFen` lives in mutable `Settings` but `periodAnchorDay` and `sealGraceHours` live in immutable `VaultConfig`: the threshold only affects *future capture UI*, so mutating it cannot rewrite history. The anchor and grace affect **admissibility of past events**, so mutating them would retroactively change whether an already-merged edit counts — destroying the property proved in §2.10.

### 1.14 `Device`

```ts
export interface Device {
  id: Id;                     // 128-bit random, generated once per install
  name: string;               // "iPhone 15 Pro", user-editable
  platform: Platform;
  appVersion: string;
  registeredAt: Millis;
  lastSeenAt: Millis;         // monotone max, not LWW (§2.10)
  revokedAt?: Millis;
  readonly nodeId: string;    // first 8 id characters, lowercased — the HLC node component
}
```

```swift
public struct Device: Codable, Equatable, Sendable, Identifiable {
    public var id: Id; public var name: String; public var platform: Platform
    public var appVersion: String; public var registeredAt: Millis
    public var lastSeenAt: Millis; public var revokedAt: Millis?
    public var nodeId: String { String(id.prefix(8)).lowercased() }
}
```

`nodeId` derives from the **id string's first 8 Crockford characters, lowercased** — not from decoded bytes — so both platforms produce identical node ids without agreeing on a byte decoder. Crockford's alphabet is ASCII, so `.lowercased()` and `.toLowerCase()` are equivalent here.

### 1.15 The materialised `LedgerState`

```ts
export interface LedgerState {
  config: VaultConfig;
  settings: Settings;
  txns: Map<Id, Txn>;
  corrections: Map<Id, Correction>;
  voidances: Map<Id, Voidance>;
  categories: Map<Id, Category>;
  accounts: Map<Id, Account>;
  budgets: Map<string, Budget[]>;        // key "total" | categoryId, sorted by effectiveFrom
  budgetRevisions: BudgetRevision[];     // append-only, sorted by (at, id)
  wishes: Map<Id, Wish>;
  wishObjects: Map<Id, WishObject>;
  subscriptions: Map<Id, Subscription>;
  subscriptionUsage: Map<Id, SubscriptionUsage>;
  zeroSpendDays: Map<CivilDate, ZeroSpendDay>;
  devices: Map<Id, Device>;
  /** Per-entity, per-field write stamps — the LWW bookkeeping. §2.7 */
  stamps: Map<string, Hlc>;              // key: `${entityId} ${field}`
  /** Events the fold refused. Surfaced in 设置 › 诊断; never silently dropped. §2.8 */
  quarantine: QuarantinedEvent[];
  /** Greatest HLC observed — the sync watermark. */
  hlcHigh: Hlc;
  eventCount: number;
}
```

The Swift mirror uses `[Id: Txn]` dictionaries inside an `actor LedgerStore`; the fold itself is a `nonisolated static func` over value types so it can be property-tested against the TypeScript implementation with the shared fixtures of §2.11.

---
## 2. The event-sourced log

### 2.1 Envelope of a single event

```ts
export interface Event<T extends EventType = EventType> {
  /** 128-bit CSPRNG, 26-char Crockford Base32. Globally unique. Dedupe key. */
  id: Id;
  /** Event type discriminator, dot-namespaced. */
  t: T;
  /** Hybrid Logical Clock stamp. Total order key. §2.3 */
  hlc: Hlc;
  /** Device that authored it. Redundant with hlc's node part; kept for display. */
  dev: Id;
  /** Type-specific body. Canonical JSON object; never null; may be {}. */
  p: EventPayload[T];
}
```

```swift
public struct AnyEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: Id
    public let t: String
    public let hlc: Hlc
    public let dev: Id
    public let p: CanonicalJSON     // order-preserving, integer-exact JSON value type
}
```

An `Event` is **immutable once authored**. Two events with the same `id` MUST be byte-identical; if a client ever observes two different bodies under one id (only possible through corruption or a hostile writer), it keeps the one whose canonical bytes sort first and records a `quarantine` entry of reason `"id-collision"`. This keeps the dedupe rule deterministic under adversarial input.

The four envelope keys are deliberately one and two characters (`id`, `t`, `hlc`, `dev`, `p`): they repeat on every event and the vault blob is size-constrained (§4.4).

### 2.2 Event catalogue

Every variant, with its exact payload. `Fields<X>` means "a partial object over the mutable fields of `X`, containing at least one key". Absent key = not written. Present key = write this field with this event's HLC.

#### Ledger

| `t` | payload | notes |
|---|---|---|
| `txn.create` | `Txn` minus derived fields, all required fields present | `p.id` is the entity id |
| `txn.patch` | `{ id: Id } & Fields<Txn>` | mutable fields: `amountFen, flow, categoryId, accountId, intent, note, reason, merchant, occurredOn, occurredAt, tzOffsetMin` |
| `txn.delete` | `{ id: Id, at: Millis }` | writes `deletedAt`; open period only |
| `txn.undelete` | `{ id: Id }` | writes `deletedAt = undefined` |
| `txn.correct` | `Correction` | sealed period; `p.id` is the Correction id |
| `txn.void` | `Voidance` | sealed period |
| `txn.review` | `{ id: Id, verdict: 1 \| 2, at: Millis, source: VerdictSource }` | 周日审判 |
| `txn.deferReview` | `{ id: Id, at: Millis }` | increments `deferCount` via grow-only counter, §2.10 |

#### Reference data

| `t` | payload |
|---|---|
| `category.create` | `Category` |
| `category.patch` | `{ id: Id } & Fields<Category>` |
| `account.create` | `Account` |
| `account.patch` | `{ id: Id } & Fields<Account>` |

#### Standard (标准线)

| `t` | payload | notes |
|---|---|---|
| `budget.set` | `{ scope, categoryId?, standardFen, proposedFen?, effectiveFrom, at, by, revisionId: Id }` | appends **both** a `Budget` row and a `BudgetRevision` with id `revisionId` |
| `threshold.set` | `{ kind: "coolingThreshold" \| "leakCeiling" \| "reckoning", toFen?: Fen, weekday?: number, hour?: number, at, by, revisionId: Id }` | mutates `Settings` **and** appends a `BudgetRevision` — one event, two effects, so a threshold change can never be made without leaving a record |

#### Want list

| `t` | payload |
|---|---|
| `wish.create` | `Wish` |
| `wish.patch` | `{ id: Id } & Fields<Wish>` (`name, priceFen, categoryId, note, letterToSelf`) |
| `wish.buy` | `{ id: Id, txnId: Id, at: Millis }` |
| `wish.abandon` | `{ id: Id, at: Millis }` — 不买了 |
| `wish.reopen` | `{ id: Id, at: Millis }` |
| `wishObject.set` | `WishObject` |
| `wishObject.remove` | `{ id: Id, at: Millis }` |

#### Subscriptions

| `t` | payload |
|---|---|
| `sub.create` | `Subscription` |
| `sub.patch` | `{ id: Id } & Fields<Subscription>` |
| `sub.claim` | `{ id: Id, claim: SubClaim, at: Millis }` |
| `sub.cancel` | `{ id: Id, cancelledOn: CivilDate, at: Millis }` |
| `sub.use` | `SubscriptionUsage` |

#### Misc

| `t` | payload |
|---|---|
| `zero.mark` | `{ on: CivilDate, at: Millis, by: Id }` |
| `zero.unmark` | `{ on: CivilDate, at: Millis }` |
| `settings.patch` | `Fields<Settings>` (no id — the singleton entity id is the literal `"SETTINGS"`) |
| `device.register` | `Device` |
| `device.patch` | `{ id: Id } & Fields<Device>` (`name, appVersion, lastSeenAt`) |
| `device.revoke` | `{ id: Id, at: Millis }` |

There is deliberately **no `period.seal` event** — see §2.6.

### 2.3 Ordering: Hybrid Logical Clock

#### 2.3.1 Why HLC and not `(timestamp, id)`

Both give a total order and both are cheap. The difference is what happens under skew, which on real phones and browsers is not hypothetical (a phone restored from backup, a VM with a paused clock, a user who sets the date forward to bypass a trial).

With `(timestamp, id)`, a device whose clock is 3 days fast wins **every** conflict against every other device for three days, and there is no mechanism that ever corrects it: the skewed device keeps stamping the future forever. Worse, the anomaly is invisible — nothing in the data indicates it happened.

With HLC, the same skewed device still wins on first contact, but the moment any other device *receives* one of its events, that device advances its own logical component to match. From then on, later real-world writes on the correct device sort *after* the skewed writes. The anomaly is bounded to one exchange and then self-heals, and the divergence is measurable (`hlc.pt − wallClock`) so the UI can surface 设备时间异常.

HLC also preserves **causality**: if event *a* happened-before event *b* on the same device or *b* was authored after observing *a*, then `hlc(a) < hlc(b)`. `(timestamp, id)` gives no such guarantee. For a ledger where a `txn.correct` must never sort before the `txn.create` it corrects, this matters.

The cost is one 16-bit counter and three lines in the receive path. HLC is chosen.

#### 2.3.2 Representation

```
hlc := <12 hex : physical ms> "-" <4 hex : logical counter> "-" <8 hex : nodeId>
e.g.  0193e6f0c1a8-0003-7f3a91c2
```

- **Physical**: 48 bits of Unix epoch milliseconds, big-endian, lowercase hex, zero-padded to 12 characters. Overflows in year 10889.
- **Logical**: 16 bits, lowercase hex, zero-padded to 4.
- **Node**: the device's `nodeId` (§1.14), 8 lowercase hex characters.

The string is exactly 26 characters and **lexicographic string comparison equals the intended order** — `pt` first, then `l`, then node — because every component is fixed-width, zero-padded, lowercase hex. This means SQLite `ORDER BY hlc`, `Array.prototype.sort()` and Swift's `<` on `String` all agree without a custom comparator.

> Both platforms MUST compare with **byte/scalar comparison**, not locale collation. Swift's default `String.<` is Unicode-canonical ordering, which for this restricted ASCII alphabet coincides with byte order. TypeScript MUST use `a < b` on strings (UTF-16 code-unit order), **never** `localeCompare`.

#### 2.3.3 Algorithm

```ts
interface ClockState { pt: number; l: number; }     // persisted across launches

const MAX_DRIFT_MS = 60_000;

/** Called once per authored event. */
function sendTick(c: ClockState, wall: number, nodeId: string): Hlc {
  const ptPrev = c.pt;
  c.pt = Math.max(ptPrev, wall);
  c.l  = (c.pt === ptPrev) ? c.l + 1 : 0;
  if (c.l > 0xFFFF) { c.pt += 1; c.l = 0; }         // counter overflow borrows a millisecond
  return format(c.pt, c.l, nodeId);
}

/** Called once per received event, BEFORE it is folded. */
function recvTick(c: ClockState, msg: Hlc, wall: number): void {
  const m = parse(msg);
  const ptPrev = c.pt, lPrev = c.l;
  c.pt = Math.max(ptPrev, m.pt, wall);
  if (c.pt === ptPrev && c.pt === m.pt)      c.l = Math.max(lPrev, m.l) + 1;
  else if (c.pt === ptPrev)                  c.l = lPrev + 1;
  else if (c.pt === m.pt)                    c.l = m.l + 1;
  else                                       c.l = 0;
  if (c.l > 0xFFFF) { c.pt += 1; c.l = 0; }
}
```

```swift
public struct HLC: Sendable {
    public private(set) var pt: Int64
    public private(set) var l: Int
    public let nodeId: String
    public static let maxDriftMs: Int64 = 60_000

    public mutating func send(wall: Int64) -> String {
        let ptPrev = pt
        pt = max(ptPrev, wall)
        l = (pt == ptPrev) ? l + 1 : 0
        if l > 0xFFFF { pt += 1; l = 0 }
        return HLC.format(pt: pt, l: l, node: nodeId)
    }

    public mutating func receive(_ msg: String, wall: Int64) {
        guard let m = HLC.parse(msg) else { return }
        let ptPrev = pt, lPrev = l
        pt = max(ptPrev, m.pt, wall)
        if pt == ptPrev && pt == m.pt { l = max(lPrev, m.l) + 1 }
        else if pt == ptPrev          { l = lPrev + 1 }
        else if pt == m.pt            { l = m.l + 1 }
        else                          { l = 0 }
        if l > 0xFFFF { pt += 1; l = 0 }
    }
}
```

Rules:

1. `recvTick` MUST be called for **every** received event, including duplicates already known, and MUST be called before folding.
2. If `m.pt − wall > MAX_DRIFT_MS` the client **still accepts and folds the event** — dropping it would make the fold depend on arrival, destroying §2.10 — but raises a persistent diagnostic (`设备时间异常 · 相差 3 天 4 小时`) in 设置, and **blocks outbound push** until the user acknowledges. Accepting bad data is recoverable; diverging replicas are not.
3. `ClockState` is persisted on every authored event (a single small write) so a relaunch cannot regress the clock.

#### 2.3.4 Uniqueness

A device never emits two events with the same `(pt, l)`: `sendTick` strictly increments `l` when `pt` does not advance. Across devices, `nodeId` disambiguates. **Therefore HLC values are globally unique and the order is total and antisymmetric — there are no ties, ever, and no tiebreak rule is needed.** (A `nodeId` collision needs two devices whose 128-bit random ids share their first 40 bits; at 10 devices the probability is ~4×10⁻¹¹. The fold nonetheless falls back to comparing full `Event.id` if two events ever present identical `hlc`, purely so the comparator is total by construction.)

### 2.4 Entity addressing

Every event names exactly one **entity key**:

| event family | entity key |
|---|---|
| `txn.*` (except `correct`/`void`) | `p.id` |
| `txn.correct`, `txn.void` | `p.id` — the child record's own id; `p.txnId` links it |
| `category.*`, `account.*`, `wish.*`, `sub.*`, `device.*` | `p.id` |
| `wishObject.*` | `p.id` |
| `sub.use` | `p.id` |
| `budget.set` | `"BUDGET"` for total scope, else `p.categoryId`; the revision is a child with id `p.revisionId` |
| `settings.patch`, `threshold.set` | the literal `"SETTINGS"` |
| `zero.mark` / `zero.unmark` | `p.on` (the civil date string) |

### 2.5 Fold rules

`fold: Set<Event> → LedgerState` is a **pure, total function**. It is defined as: sort the admissible events by `hlc` ascending, then apply each in turn with the step function `⊕`. §2.10 proves that sorting is an implementation convenience, not a semantic requirement.

Pseudocode of the driver:

```ts
export function fold(events: Iterable<Event>, config: VaultConfig): LedgerState {
  const s = emptyState(config);
  const admissible: Event[] = [];
  for (const e of dedupeById(events)) {
    const v = admit(e, config);                        // §2.6 — depends ONLY on e and config
    if (v.ok) admissible.push(e); else s.quarantine.push({ event: e, reason: v.reason });
  }
  admissible.sort((a, b) => (a.hlc < b.hlc ? -1 : a.hlc > b.hlc ? 1 : (a.id < b.id ? -1 : 1)));
  for (const e of admissible) step(s, e);
  derive(s);                                            // effectiveAmount, voided, balances, aggregates
  return s;
}
```

#### 2.5.1 Creation events (`*.create`)

Materialise the entity if absent. Then, **for every field present in the payload**, apply the per-field LWW rule of §2.7 with this event's HLC. A `create` is not privileged over a `patch`: if a `patch` with a greater HLC has already been folded, the `create` restores only the fields the patch did not touch. This is what makes "create arrives after edit" (a real case when an offline device syncs) correct rather than destructive.

`intent` has **no default**. If a `txn.create` payload omits it, the event is quarantined. The stamp is mandatory in the data model, not only in the UI.

#### 2.5.2 Patch events (`*.patch`)

For each key `k` present in `p` other than `id`: LWW-write `k`. Keys absent from `p` are untouched. Writing an explicit `null` clears an optional field (this is the **only** place `null` is legal on the wire, and it means "clear"; see §4.1).

#### 2.5.3 Delete / undelete

`txn.delete` LWW-writes `deletedAt = p.at`. `txn.undelete` LWW-writes `deletedAt = null`. Deletion is therefore just another field, which is what makes delete-vs-edit deterministic (§3.2). An entity is hidden from every list and every aggregate iff `deletedAt != null` **after** the full fold.

#### 2.5.4 Corrections and voidances

`txn.correct` inserts a `Correction` into a grow-only set keyed by its own id (LWW on its own fields, which never change in practice). `txn.void` likewise. Neither touches the parent `Txn`'s stamps. In `derive()`:

```
effectiveAmountFen(t) = maxByHlc(corrections where txnId == t.id)?.toAmountFen ?? t.amountFen
voided(t)             = any(voidances where txnId == t.id)
contribution(t)       = t.deletedAt != null || voided(t) ? 0 : effectiveAmountFen(t)
```

#### 2.5.5 Reviews

`txn.review` LWW-writes `verdict`, `reviewedAt`, `verdictSource` **as one group under a single stamp key** `"<txnId> verdictGroup"`. Grouping matters: a 值 verdict from device A and a 不值 verdict from device B must not interleave into `verdict = Worth, verdictSource = ExhaustedDeferrals`. Fields that are only meaningful together share one stamp. The other grouped sets in the model are `(cancelledOn, claim)` on `Subscription` and `(state, resolvedAt, txnId)` on `Wish`.

#### 2.5.6 Deferrals

`deferCount` is a **grow-only counter over event ids**: `deferCount(txn) = |{ e : e.t == "txn.deferReview" && e.p.id == txn.id }|`. Not an LWW integer — two devices deferring the same card must count twice, and re-delivering the same event must not. Set cardinality gives both properties free.

#### 2.5.7 未敢面对 — bounded deferral

When `deferCount ≥ settings.maxDeferrals` (default 3) **and** the txn is still `Unjudged`, `derive()` sets `verdict = NotWorth`, `verdictSource = ExhaustedDeferrals` **as a derived value only** — it writes no event and no stamp. It is a pure function of the folded state, so every replica computes it identically without a coordinated write, and it cannot conflict with a later real `txn.review` (which has a stamp and therefore wins the register). The Sunday summary prints these separately as `未敢面对 · 2 笔`.

#### 2.5.8 Sample gates

`derive()` computes `judgedCount = |{t : verdict != Unjudged}|`. Every rate-shaped figure (后悔率, per-category 后悔率, the 后悔率 block chart, the mutating button label of §2.5.9) is `nil` while `judgedCount < settings.minJudgedForRates` (30). The UI then prints the honest count — `还需 18 笔判定` — rather than a thin chart. The gate is on the *rate*; the absolute cumulative 后悔金额 is never gated, because a sum of one is still a true sum.

#### 2.5.9 Derived indices the product needs

All are pure functions of the folded state; all are recomputed incrementally on write:

- **今日可用** — `floor((standardFen − monthToDateContribution − scheduledRemainingFen) / daysRemainingInclusive)` in 分, with the integer remainder pushed onto the final day so the daily figures sum exactly to the available total. May be negative; it is the only figure permitted to be.
- **小额漏水** — `{count, sumFen}` over `contribution(t) < settings.leakCeilingFen`, plus `equivalent = sumFen / median90(contribution where ≥ leakCeiling)` printed to one decimal.
- **后悔额** — `Σ contribution(t) where verdict == NotWorth`, for the current period and for the calendar year. Never reset, never softened.
- **已放弃 / 已省** — `Σ priceFen where wish.state == Abandoned` (year) and `Σ savedSinceCancelFen` over cancelled subscriptions (all time).
- **Recurring detector** — pure local logic over `Txn`: normalise `merchant` (NFKC fold, strip whitespace and digits, lowercase), group by `(normMerchant, amount within ±5%)`, emit a candidate when occurrences `≥ category.detectorMinOccurrences` and `stddev(interArrivalDays) < 4`. Candidates become `Subscription` rows with `detected = true, claim = Unclaimed` — the app never asserts a subscription exists; the user signs for each row.
- **Commit-button label** — when `judgedCount ≥ minJudgedForRates`, `regretRate(category) > 0.40`, and the pending amount exceeds that category's trailing median, the capture sheet's primary label becomes `存入账页 · 这类你 62% 判过不值`. Pure text substitution on an existing control; no new component, no colour, no dialog.

### 2.6 结账 — sealing, and why there is no seal event

**Rule.** Let `period(d)` be the period containing civil date `d`, given `config.periodAnchorDay`. Let

```
sealTime(P) = epochMillis(P.endExclusive, atLocalMidnight) + config.sealGraceHours * 3_600_000
```

An event `e` that would **mutate** an existing `Txn` (i.e. `txn.patch`, `txn.delete`, `txn.undelete`) is **admissible iff** `parse(e.hlc).pt < sealTime(period(target.occurredOn))`. Otherwise it is quarantined with reason `"sealed-period"` and the UI is expected never to have offered it. `txn.correct` and `txn.void` are admissible in both open and sealed periods; `txn.create` is always admissible (you can always record a purchase you forgot, and it appends rather than rewrites).

**Why not a `period.seal` event.** The obvious design makes sealing an event and defines shadowing as "an update is dropped if a seal event for its period exists with a smaller HLC". That rule is a function of the event *set*, so it still converges — but it destroys snapshotting. A snapshot stores only the winning value per field; if a seal event arrives later and retroactively disqualifies an update already folded into a snapshot, the pre-update value is gone and the state cannot be recovered without the full log. Compaction and late-arriving seals are then mutually exclusive.

Deriving `sealTime` from the event's own HLC and immutable config makes admissibility a **local predicate on a single event**: `admit(e, config)`. It never changes, no matter what else arrives, and no matter when. Snapshots are therefore exactly as authoritative as the events they replace. This is the single most important structural decision in the document, and it is the reason `periodAnchorDay` and `sealGraceHours` are immutable (§1.13).

**Consequence, stated honestly.** A device whose clock is set backwards by a month could author an edit that passes the seal test. This is not defended against; the vault has one writer identity and the threat model (§9) does not include the owner attacking their own ledger with a manipulated clock. The 24-hour grace and the drift diagnostic cover the accidental cases.

**UI consequence.** The client MUST compute `sealTime` before offering an edit affordance, so a user never composes an edit that the fold will refuse. In 账页 a sealed month shows the 结 block and the row's edit action becomes 更正 (two taps plus a ≥2-character 事由), never a disabled control with no explanation.

### 2.7 Per-field LWW registers

State carries `stamps: Map<"<entityKey> <fieldOrGroup>", Hlc>`.

```ts
function lww<T>(s: LedgerState, key: string, field: string, hlc: Hlc, write: () => void): void {
  const k = key + " " + field;
  const cur = s.stamps.get(k);
  if (cur === undefined || cur < hlc) { write(); s.stamps.set(k, hlc); }
}
```

Rules:

1. Comparison is on the HLC string, ascending; strictly greater wins. Equal is impossible (§2.3.4) but if it occurred, the write is skipped, making the operation idempotent under exact re-delivery.
2. Fields that are only meaningful together share one stamp key (§2.5.5). The complete list of groups is: `Txn.verdictGroup = (verdict, reviewedAt, verdictSource)`; `Wish.stateGroup = (state, resolvedAt, txnId)`; `Subscription.cancelGroup = (claim, cancelledOn)`; `Account.creditGroup = (statementDay, dueDay)`. Every other field is its own register.
3. Non-LWW fields, enumerated exhaustively so no implementer invents a third kind: `Wish.unlockAt` and `Device.lastSeenAt` are **monotone max**; `Txn.deferCount` is a **G-counter over event ids**; `Correction`, `Voidance`, `BudgetRevision`, `SubscriptionUsage`, `ZeroSpendDay` and the `Budget` history are **G-sets**.
4. Stamps for entities that no longer exist are never garbage-collected within a snapshot — a deleted entity still needs its stamps so a late `patch` does not resurrect stale values. They are ~40 bytes each; §4.4 bounds the total.

### 2.8 Quarantine

Refused events are kept, not dropped: `{ event, reason, firstSeenAt }` with `reason ∈ {"missing-intent", "sealed-period", "unknown-type", "malformed", "id-collision", "schema-too-new"}`. Quarantined events **remain in the log and are still transmitted**, because another client with a newer schema may be able to admit them, and because deleting them would let a fold-level bug silently destroy data. 设置 › 诊断 prints the count and lets the user export them. An event with an unknown `t` is quarantined as `"unknown-type"` and re-evaluated on every app upgrade.

### 2.9 Idempotency

Three independent layers, each sufficient on its own:

1. **Set semantics.** The log is a set keyed by `Event.id`; delivering an event twice is a no-op union.
2. **Register semantics.** LWW writes with `cur < hlc` are skipped on equality, so replaying an already-applied event changes nothing.
3. **Object immutability.** Segments are content-named and create-only in both adapters (§6.3, §7.5); re-uploading the same segment is a no-op or a benign `409`/`422`.

A `PUT` that times out but actually succeeded is therefore always safe to retry — the retry either creates the identical object or is rejected as already-existing, and both outcomes are correct.

### 2.10 Informal proof: merge is commutative, associative and idempotent

**Setup.** Let 𝔼 be the set of well-formed events. A replica's persistent state is a finite `E ⊆ 𝔼`. Merging two replicas is `merge(E₁, E₂) = E₁ ∪ E₂`. The observable state is `fold(E)`.

**Lemma 1 — the log is a G-set.** Set union is commutative, associative and idempotent. Events are immutable and keyed by a 128-bit random id, and §2.1 fixes a deterministic tiebreak for the pathological same-id-different-body case, so `∪` is well defined on ids. ∎

**Lemma 2 — `fold` is a pure function of the set.** `fold` reads only its argument and `VaultConfig` (immutable, §1.13). It never reads wall-clock time, arrival order, network state or device identity. The sort in §2.5 is by `hlc` with an `Event.id` fallback, both of which are intrinsic to the events, so the sorted sequence is a function of the set alone. Therefore `E₁ = E₂ ⟹ fold(E₁) = fold(E₂)`. ∎

**Corollary — convergence.** Combining 1 and 2: replicas that have delivered the same events display the same state, regardless of the order or number of times each event was delivered, and regardless of which adapter delivered it. This is strong eventual consistency.

**Lemma 3 — `fold` is incremental, so snapshots are sound.** Define the step `⊕ : State × Event → State` of §2.5. We must show `fold(E ∪ {e}) = fold(E) ⊕ e` for all `E, e`, i.e. that `⊕` is commutative and idempotent on states, so that a snapshot may replace the events it covers.

- *Admissibility.* `admit(e, config)` (§2.6) depends only on `e` and immutable config. It is therefore invariant under everything else in `E`, so an event's admissibility can never change retroactively. This is the property a seal-*event* design would break.
- *LWW registers.* Each register is `(value, hlc)` under the join `max` over a **total order** (§2.3.4). `max` on a total order is commutative, associative and idempotent, and the paired value is determined by the winning stamp. Applying `e` twice writes the same value and leaves the same stamp.
- *Grouped registers.* A group is one register whose value is a tuple; the argument above applies unchanged.
- *Monotone-max fields* (`unlockAt`, `lastSeenAt`). `max` over integers: commutative, associative, idempotent.
- *G-counters* (`deferCount`). Cardinality of a set of event ids: union again.
- *G-sets* (`Correction`, `Voidance`, `BudgetRevision`, `SubscriptionUsage`, `ZeroSpendDay`, `Budget` history). Union.
- *Derived values* (`effectiveAmountFen`, `voided`, `verdict` via §2.5.7, every aggregate). Pure functions of the above, recomputed by `derive()` after the last step. Since their inputs converge, so do they.

Every field of `LedgerState` therefore belongs to a join-semilattice and `⊕` is the componentwise join with `e`'s contribution. A componentwise join of semilattices is a semilattice, hence `⊕` is commutative and idempotent, hence `fold(E ∪ F) = fold(E) ⊕ F` for any sets `E, F`, and a snapshot of `fold(E)` may replace `E` with no loss. ∎

**What is *not* claimed.** `⊕` is not *inflationary* in the naive sense: applying an event with a smaller HLC than the current stamp changes nothing, which is intended (a late-arriving old edit must lose) but means the state is not "growing" in a user-visible way. Nor is any claim made about *intention preservation*: if two devices concurrently set `amountFen` to different values, one is silently discarded. That is a genuine limitation of LWW and §3.1 documents how the product mitigates it (by scoping the register to the field, and by 更正 rows in sealed periods, where silent loss would be most harmful).

### 2.11 Shared fixtures — how two codebases are held to this

`scripts/fixtures/` holds JSON test vectors consumed by both `web/src/core/**/*.test.ts` (Vitest) and `ios/CountbookTests/**` (XCTest). Both suites read the *same files*; neither may carry its own copy.

| fixture | asserts |
|---|---|
| `hlc.json` | `send`/`receive` transcripts: `[{clock, wall, msg?} → expected]` |
| `fold.json` | `{config, events[], expectedState}` — 40+ cases including every §3 conflict |
| `fold-permutations.json` | one event list plus 200 shuffles; all MUST fold to the identical canonical state hash |
| `canonical-json.json` | `{value, expectedBytesHex}` — §4.1 |
| `crypto-kat.json` | passphrase/salt/iterations → derived keys, and full envelope encrypt/decrypt vectors — §5.7 |
| `calendar.json` | `period()`, `sealTime()`, `chargeCount()` around month-end anchors and DST |
| `geometry.json` | chart point arrays, shared with the design system |
| `money-format.json` | the three-part ¥/元/分 split and its accessibility label |

CI fails if either implementation disagrees with a fixture. The canonical state hash is `SHA-256(canonicalJSON(state))` with `stamps` included and `quarantine` sorted by event id.

---

## 3. Conflict cases, worked

Notation: device **A** = `nodeId 7f3a91c2`, device **B** = `nodeId 0b3ed845`. Times are UTC.

### 3.1 Same txn edited on two devices

Txn `T` = `¥288.00` 餐饮, created 03-14 10:00. Both devices offline from 12:00.

- **A**, 12:30, fixes the amount: `txn.patch {id:T, amountFen: 8800}` at `hlc 0193…a1-0000-7f3a91c2` (pt = 12:30:00.000).
- **B**, 12:31, fixes the category: `txn.patch {id:T, categoryId: 日用}` at `hlc 0193…b9-0000-0b3ed845` (pt = 12:31:07.412).

Both sync at 18:00. Registers touched are **disjoint** (`amountFen` vs `categoryId`), so both writes survive: `T = ¥88.00, 日用`. Field-level LWW is what buys this; a whole-entity LWW would have thrown one edit away.

Now the harder case: **B** at 12:31 also sets `amountFen: 9900`. Now `T.amountFen` has two candidate writes. `0193…b9 > 0193…a1`, so B wins: `¥99.00`. A's `¥88.00` is discarded silently.

Product mitigation, not protocol mitigation: after a merge that discards an LWW write **authored on this device within the last 7 days**, the client appends nothing to the log but records a local-only diagnostic and shows a single hairline row in 账页 under the affected txn: `本机 12:30 的修改被 iPad 12:31 的修改覆盖`. It is informational, dismissible, never a dialog, and never syncs. Users get an explanation instead of a mystery; the data model stays a clean semilattice.

### 3.2 Delete vs edit

- **A**, 12:30: `txn.delete {id:T, at:…}` → writes `deletedAt` at `hlc_A`.
- **B**, 12:45: `txn.patch {id:T, note:"报销"}` → writes `note` at `hlc_B > hlc_A`.

Result: `deletedAt` is set (nobody cleared it) and `note = "报销"`. The txn is **hidden**, and it carries a note nobody will read. This is deterministic and it is the correct default: an edit is not evidence of an intent to undelete. If the user on B wants it back, `txn.undelete` clears `deletedAt` with a fresh, larger HLC.

Reverse order (`patch` at 12:30, `delete` at 12:45): same outcome, same reasoning. Delete-vs-edit is order-independent because deletion is not a special operation — it is a field.

**Delete vs correct in a sealed period.** `txn.delete` is inadmissible there (§2.6), so the only available operation is `txn.void`, which appends. There is no delete-vs-correct conflict in sealed periods by construction: nothing can be removed.

### 3.3 Clock skew

**B**'s clock is 3 days fast.

1. B authors `E_B` at wall 03-17, `hlc.pt = 03-17`. Real time is 03-14.
2. A authors `E_A` at real 03-14 12:00, `hlc.pt = 03-14`.
3. They sync. `E_B > E_A` for every shared register: B wins. Bad, but bounded.
4. **A's `recvTick` fires**: `A.pt ← max(A.pt, 03-17, wall) = 03-17`, `A.l ← m.l + 1`. A's clock component is now pulled forward.
5. A's next edit at real 03-14 12:05 stamps `pt = 03-17, l = 1` — **greater than `E_B`**. From here on, later-in-real-time writes win again, which is the desired semantics.
6. Both devices' `pt − wall` now exceeds `MAX_DRIFT_MS`, so both surface 设备时间异常 and A blocks push until acknowledged (§2.3.3 rule 2). The user is told which device is wrong and by how much.

Compare `(timestamp, id)`: step 4 does not exist, so B wins every conflict for three full days and nothing in the data records that it happened. This is the whole justification for §2.3.1.

**Backwards skew and sealing.** A device set back a month could author an edit that passes `admit()`. Out of scope (§2.6, §9.3).

### 3.4 An offline device syncing after a week

**A** has been offline 7 days with 61 local events, including a period rollover (the month sealed on the 1st, 03:00 with a 24 h grace, while A was offline). Meanwhile **B** pushed 143 events and published a snapshot that covers everything up to segment `S12`.

1. A comes online. Its unsent events sit in the outbound queue as unsegmented rows in the local `outbox` table (§8.4). Nothing has been lost.
2. A pulls the index. It sees `snapshot = SNAP-2` covering `[S1…S12]` — segments A never saw, several of which no longer exist because they were GC'd (§4.5).
3. A verifies `SNAP-2.hlcHigh` and loads it as its **base state**. This is sound by Lemma 3: `SNAP-2 = fold(E_covered)`, and A's own events are `E_A`, so `fold(E_covered ∪ E_A) = SNAP-2 ⊕ E_A`.
4. A downloads the segments listed after the snapshot (`S13…S19`), calls `recvTick` for each event, and folds them onto the base.
5. A folds its own 61 queued events onto the same state. **Some are now inadmissible**: 4 of them were `txn.patch` events against February txns, authored on the 3rd — after `sealTime(Feb)`. They quarantine with reason `"sealed-period"`.
6. A surfaces this once, plainly: `4 笔离线修改落在已结账月份 · 已转为待更正`. Each is offered as a pre-filled 更正 needing only a 事由. Nothing is lost, nothing is silently applied.
7. A encrypts its 61 events into one new segment, `PUT`s it (create-only, so a retry is safe), then CAS-updates the index. If the CAS fails because B pushed in the meantime, A re-reads the index, re-applies its segment reference to the *new* index, and retries — **without re-encrypting**, because the segment object is already uploaded and immutable (§6.4).

Note step 7's shape: a conflict on the index costs one small round trip, never a re-upload and never a merge.

### 3.5 Two devices bootstrapping the same passphrase simultaneously

Both write the twelve seed categories. Fixed ids (§1.5) mean twelve entities, not twenty-four. Both write `device.register` for themselves: two distinct entities, correct. Both may write an initial `budget.set` — the later HLC wins the standard, and **both** `BudgetRevision` rows survive in the footer, which is honest: the record shows the standard was set twice on day one.

### 3.6 Concurrent index writes with no segment conflict

A and B both push at the same second. Segment ids are 128-bit random, so the two objects never collide. Exactly one index CAS succeeds; the loser re-reads and retries. Because the index is a small encrypted list and the retry does not re-encrypt segments, the loser's second attempt is ~1 KB and ~200 ms. With full jitter (§6.5) livelock across two devices is not observed in practice; the loop is capped at 6 attempts and then reports 待同步 rather than spinning.

### 3.7 A rolled-back index (hostile or buggy server)

The index carries a monotone `seq` **inside the ciphertext**. A client persists `lastSeenIndexSeq`. On pull, if `index.seq < lastSeenIndexSeq`, the client **refuses to adopt it**, keeps its local state, enters `error.rollback`, and shows `同步异常 · 服务端账页版本回退`. It does not overwrite the remote either — a rollback may be a restore-from-backup rather than an attack, and destroying the newer local data is the worse failure. Resolution is manual: 强制上传本机 or 放弃本机改动. This detects rollback; §9.3 is explicit that it cannot prevent it.

---
## 4. Wire format

### 4.1 Canonical JSON

Every payload that is encrypted, hashed or compared byte-for-byte MUST be serialised with **Canonical JSON (CJSON/1)**:

1. UTF-8, no BOM, no trailing newline.
2. No insignificant whitespace: `{"a":1,"b":[2,3]}`.
3. Object keys sorted **ascending by UTF-16 code unit** (`Array.prototype.sort()` default; Swift `sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }`). **All keys in this protocol are restricted to `[A-Za-z0-9_]`**, so UTF-16, UTF-8, scalar and byte orders coincide and the choice of comparator cannot cause divergence. New keys MUST honour this restriction.
4. Numbers are **integers only**, in `[-(2^53−1), 2^53−1]`, rendered with no sign for positives, no leading zeros, no exponent, no fraction. Floats, `NaN` and `Infinity` are invalid input. (`detectorEvidence` fractions are excluded from every canonical context; see §1.0.)
5. Strings: NFC-normalised; escape only `"` `\` and U+0000–U+001F, using the two-character escapes `\" \\ \b \f \n \r \t` where they exist and `\uXXXX` lowercase-hex otherwise. Do **not** escape `/`, and do **not** escape non-ASCII — CJK is emitted raw, which also saves ~60 % of the bytes a `\u`-escaping encoder would produce.
6. `null` MUST NOT be emitted for absent optional fields; omit the key. `null` is legal only as an explicit value inside a `*.patch` payload, where it means "clear this field" (§2.5.2).
7. Booleans `true`/`false`. Arrays preserve order.

Neither `JSON.stringify` (key order = insertion order) nor `JSONEncoder` (`.sortedKeys` sorts by `String <`, which is *scalar* order) is compliant out of the box. Both platforms implement `canonicalize(value) -> Uint8Array` / `Data` in `core/canonical` and validate it against `scripts/fixtures/canonical-json.json`.

### 4.2 Object kinds

Exactly three plaintext payload kinds exist. Each is canonical JSON, then encrypted into one `CBV1` envelope (§5.4), then stored as one opaque object.

**Index** — the single mutable object.

```json
{
  "k": "index",
  "v": 1,
  "vaultId": "8f1c4a2b9d0e4f6a8b3c5d7e9f0a1b2c",
  "seq": 137,
  "updatedAt": 1757337660123,
  "updatedBy": "7F3A91C2QK4M8N2P6R0T4V8X2Z",
  "config": { "…VaultConfig…" },
  "snapshot": {
    "id": "9K2M4P6R8T0V2X4Z6B8D0F2H4J",
    "bytes": 41233,
    "eventCount": 1840,
    "hlcHigh": "0193e6f0c1a8-0003-7f3a91c2",
    "covers": ["…segment ids…"]
  },
  "segments": [
    { "id": "…", "bytes": 912, "eventCount": 12,
      "hlcLow": "…", "hlcHigh": "…", "createdBy": "…", "createdAt": 1757337660123 }
  ],
  "devices": [
    { "id": "…", "name": "iPhone 15 Pro", "platform": 1, "appVersion": "1.0.3",
      "lastSeenAt": 1757337660123, "ackSnapshot": "…" }
  ],
  "gc": [ { "id": "…", "deletedAt": 1757337660123 } ]
}
```

**Segment** — immutable, create-only, randomly named.

```json
{ "k": "segment", "v": 1,
  "vaultId": "8f1c…2c",
  "id": "4P6R8T0V2X4Z6B8D0F2H4J9K2M",
  "createdAt": 1757337660123,
  "createdBy": "7F3A91C2QK4M8N2P6R0T4V8X2Z",
  "events": [
    { "dev": "7F3A…", "hlc": "0193e6f0c1a8-0000-7f3a91c2",
      "id": "0F2H4J9K2M4P6R8T0V2X4Z6B8D", "p": { "…" }, "t": "txn.create" }
  ] }
```

**Snapshot** — immutable, create-only, randomly named.

```json
{ "k": "snapshot", "v": 1,
  "vaultId": "8f1c…2c",
  "id": "9K2M4P6R8T0V2X4Z6B8D0F2H4J",
  "createdAt": 1757337660123,
  "createdBy": "7F3A…",
  "covers": ["…segment ids…"],
  "eventCount": 1840,
  "hlcHigh": "0193e6f0c1a8-0003-7f3a91c2",
  "state": { "…serialised LedgerState, including stamps and quarantine…" },
  "stateHash": "…64 lowercase hex = SHA-256 of canonicalJSON(state)…" }
```

`vaultId` appears inside every payload as well as in the envelope header. A client MUST verify that the decrypted `vaultId` matches the header's and matches its own vault, which defeats an object-substitution attack (moving a valid ciphertext from one path to another) without putting the path in the AAD — so objects stay relocatable.

`k` MUST be checked against what the caller expected. A segment served where an index was requested is a hard error, not a parse failure.

### 4.3 Serialised state inside a snapshot

`state` is `LedgerState` with `Map`s rendered as JSON objects keyed by the entity key (already `[A-Za-z0-9_]`-safe: Crockford Base32, the literals `BUDGET`/`SETTINGS`, or `YYYY-MM-DD` — note the hyphen, which is added to the permitted key charset for `zeroSpendDays` only, and sorts before all alphanumerics in every order under discussion, consistently on both platforms). `stamps` is an object of `"<key> <field>" → hlc` — its keys contain a space (0x20), which likewise sorts consistently. Derived fields (`effectiveAmountFen`, `voided`, aggregates) are **omitted**; they are recomputed by `derive()` on load, so a `derive()` bug fix takes effect on old snapshots.

### 4.4 Size budget

| item | typical | notes |
|---|---|---|
| one event, canonical | 180–320 B | short envelope keys earn their ugliness here |
| one segment (12 events) | ~3 KB plaintext, ~3 KB ciphertext + 108 B header | GCM does not expand beyond the tag |
| index with 64 segments | ~9 KB | |
| snapshot, 3 years / ~11 000 txns | ~2.6 MB plaintext | **too big** — see sharding below |

**Hard limits.** No stored object may exceed **512 KiB** encrypted. This is well under GitHub's 1 MiB Contents-API read ceiling (§6.6) and keeps a full sync on a slow mobile connection tolerable.

**Snapshot sharding.** When a snapshot would exceed 512 KiB it is split by entity kind and, for `txns`, by period:

```
snapshot.parts = [
  { "id": "…", "kind": "meta",  "bytes": 8_144 },     // config, settings, categories, accounts, devices, budgets, stamps-for-non-txn
  { "id": "…", "kind": "txns",  "period": "2024-01", "bytes": 96_310 },
  { "id": "…", "kind": "txns",  "period": "2024-02", "bytes": 88_002 },
  …
]
```

Each part is its own encrypted object. `snapshot.stateHash` covers the union. A client loading a snapshot MUST fetch all parts before considering itself synced, but MAY render 今日 and 账页 for the current period after loading `meta` + the current period's part — which is the common case and makes cold start on a new device feel instant rather than staged.

### 4.5 Compaction and garbage collection

Compaction runs on the client that is already pushing, never as a background job on a second device.

**Trigger** (any of): `segments.length > 64`; `Σ segments.eventCount > 2000`; `Σ segments.bytes > 256 KiB`; or `now − snapshot.createdAt > 30 days` with at least one segment present.

**Procedure.**

1. Fold `snapshot ∪ segments` locally. (The device must already hold all of them; if not, pull first.)
2. Serialise the new snapshot, shard if needed, encrypt, and `PUT` every part (create-only, new random ids).
3. CAS the index to `{ snapshot: NEW, segments: [], gc: gc ++ oldSnapshotParts ++ coveredSegments (each with deletedAt = now) }`.
4. **Do not delete anything yet.** Objects listed in `gc` are deleted only when `now − deletedAt > 7 days` **and** every non-revoked device in `index.devices` has `ackSnapshot == snapshot.id` **or** `lastSeenAt < now − 30 days`. This keeps a device that was offline for a week from finding its base missing mid-pull.
5. Deletion is best-effort. A failed delete leaves an orphan; orphans are harmless (nothing references them) and are retried on the next compaction. In adapter A they also stay in git history forever, which §9.4 addresses.

`ackSnapshot` is written by each device on its next successful pull, via the same index CAS it uses for pushing, or by a standalone lightweight CAS when it has nothing to push (rate-limited to once per hour to avoid burning GitHub's content-creation budget).

**Growth bound.** Steady state is `1 snapshot + ≤64 segments ≤ 512 KiB + 256 KiB`. The snapshot itself grows linearly with the number of txns retained, and there is no eviction — a ledger is not allowed to forget. At ~11 000 txns/3 years and ~240 B per txn in the snapshot, this is ~2.6 MB across ~7 shards, of which a cold start fetches ~110 KB before first paint. That is the intended ceiling for v1; beyond ~10 years the correct answer is per-year archive vaults, not eviction, and it is out of scope here.

---

## 5. Cryptography

### 5.1 Non-negotiables

- Primitives chosen because they exist in **both** WebCrypto and Apple's system libraries with identical semantics: PBKDF2-HMAC-SHA256, HKDF-SHA256, AES-256-GCM, SHA-256.
- **CryptoKit has no PBKDF2.** Swift uses `CommonCrypto`'s `CCKeyDerivationPBKDF`, imported as `import CommonCrypto` — a system library shipped with the OS, not a third-party package, so the zero-dependency constraint holds. HKDF, AES-GCM and SHA-256 come from CryptoKit.
- No custom crypto, no home-rolled padding, no MAC-then-encrypt. AES-GCM's tag is the only integrity mechanism and it covers the header via AAD.

### 5.2 Key hierarchy

```
passphrase (NFC, UTF-8)
   │  PBKDF2-HMAC-SHA256, salt = vaultSalt (16 B), iterations = 600_000, dkLen = 32
   ▼
 MK  (32 B, master key — never stored on disk in raw form)
   │  HKDF-SHA256(ikm = MK, salt = vaultSalt, info = …, L = 32)
   ├── info "countbook/v1/data"        → K_data      (AES-256-GCM key for all objects)
   ├── info "countbook/v1/keycheck"    → keyCheck    (32 B, stored in the header)
   └── info "countbook/v1/fingerprint" → K_fp        (32 B → 验证码, §5.6)
```

`info` strings are ASCII, exact, no trailing NUL. `vaultSalt` is **per-vault, not per-object**: 16 bytes of CSPRNG generated once at vault creation and copied verbatim into the header of every object. One PBKDF2 derivation therefore unlocks the whole vault (600 000 iterations is ~250–450 ms on a modern phone and ~300–600 ms in a browser; doing it per object would be unusable).

**Iteration count: 600 000.** OWASP's current guidance for PBKDF2-HMAC-SHA256. It is stored in the header as a `uint32`, so it can be raised later without a format change; a client MUST accept any value in `[100_000, 5_000_000]` on read and MUST refuse values below `100_000` (a downgrade attack — an attacker who can write the vault could otherwise set iterations to 1 and offline-crack cheaply; the floor is what makes that pointless). Clients MUST write `600_000`.

**Key storage.** The derived `K_data` is cached in memory for the session, and at rest:

- **iOS**: raw 32 bytes in the Keychain, `kSecClass = kSecClassGenericPassword`, `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`. Never in iCloud Keychain (that would move the key to Apple's servers, defeating the point).
- **Web**: as a **non-extractable** `CryptoKey` (`importKey(..., extractable = false, ["encrypt","decrypt"])`) stored in IndexedDB by structured clone. Non-extractable means XSS can *use* the key for the lifetime of the origin but cannot exfiltrate it — a real, if partial, mitigation (§9.2). The raw bytes MUST NOT be written to `localStorage`, ever.

### 5.3 AES-256-GCM parameters

| parameter | value |
|---|---|
| key | `K_data`, 256 bits |
| nonce | 96 bits (12 bytes), CSPRNG, fresh **per encryption operation including every retry** |
| tag | 128 bits (16 bytes) |
| AAD | the 92-byte header, bytes `[0, 92)` of the object, verbatim |
| plaintext | canonical JSON (§4.1) |

**Nonce uniqueness.** Random 96-bit nonces under one key have collision probability ≈ `q²/2^97`; at `q = 2^32` encryptions that is ≈ 2⁻³³. A vault performing one write per minute for a century reaches `q ≈ 5×10^7`, giving ≈ 10⁻¹⁴. This is safe with a wide margin, and it avoids the failure mode a counter-based nonce has on this architecture: a counter would have to be synchronised across devices, and a restored-from-backup device would reuse it — which is catastrophic for GCM. Random is chosen because it is stateless. Clients MUST use `crypto.getRandomValues` / `AES.GCM.Nonce()` (which is CSPRNG-backed) and MUST NOT derive the nonce from any content. A retried upload after a network error MUST re-encrypt with a fresh nonce or, preferably, re-upload the **identical bytes it already produced** — never re-encrypt with the same nonce.

**Rekey trigger.** If a vault ever reaches 2³² objects written (it will not), or the passphrase changes, the client re-encrypts every object under a new `vaultSalt` (§5.8).

### 5.4 Envelope byte layout — `CBV1`

All multi-byte integers are **big-endian**. Total size = `108 + plaintextLength`.

```
 offset  size  field              value / notes
 ┌──────────────────────────────────────────────────────────────────────────┐
 │  0      4   magic              0x43 0x42 0x56 0x31   "CBV1"              │
 │  4      1   formatVersion      0x01                                      │ A
 │  5      1   kdfId              0x01 = PBKDF2-HMAC-SHA256                 │ A
 │  6      1   cipherId           0x01 = AES-256-GCM                        │ D
 │  7      1   flags              bit0 = deflate-raw (MUST be 0 in v1)      │
 │  8      4   kdfIterations      uint32 BE, e.g. 600000 = 0x000927C0       │ =
 │ 12     16   kdfSalt            per-vault, identical in every object      │
 │ 28     16   vaultId            16 bytes, hex-rendered elsewhere          │ A
 │ 44     12   nonce              per-object, CSPRNG                        │ A
 │ 56     32   keyCheck           HKDF(info="countbook/v1/keycheck")        │ D
 │ 88      4   plaintextLength    uint32 BE, ≤ 0x00080000 (512 KiB)         │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ 92      N   ciphertext         N = plaintextLength                       │
 │ 92+N   16   tag                GCM authentication tag                    │
 └──────────────────────────────────────────────────────────────────────────┘
      header = bytes [0, 92)  ────────────────►  used verbatim as GCM AAD
```

The header is authenticated but not encrypted. It leaks: format version, KDF parameters, salt, vault id, and plaintext length. Length leakage is discussed in §9.4.

Note that **WebCrypto returns `ciphertext || tag` concatenated** from `encrypt()` and expects the same on `decrypt()`, while **CryptoKit exposes `.ciphertext` and `.tag` separately** (its `.combined` is `nonce || ciphertext || tag`, which is *not* our layout). Both implementations MUST therefore split/join explicitly rather than using either library's convenience form.

### 5.5 Encrypt / decrypt reference

```ts
const HDR = 92, TAG = 16;

export async function seal(plaintext: Uint8Array, k: CryptoKey, hdrIn: HeaderFields): Promise<Uint8Array> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const header = writeHeader({ ...hdrIn, nonce, plaintextLength: plaintext.length }); // 92 bytes
  const ctAndTag = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: header, tagLength: 128 }, k, plaintext));
  const out = new Uint8Array(HDR + ctAndTag.length);
  out.set(header, 0); out.set(ctAndTag, HDR);
  return out;
}

export async function open(obj: Uint8Array, k: CryptoKey, keyCheck: Uint8Array): Promise<Uint8Array> {
  if (obj.length < HDR + TAG) throw new VaultError("truncated");
  const header = obj.subarray(0, HDR);
  const h = readHeader(header);
  if (h.magic !== "CBV1")       throw new VaultError("not-a-vault-object");
  if (h.formatVersion > 1)      throw new VaultError("schema-too-new");
  if (h.kdfId !== 1 || h.cipherId !== 1) throw new VaultError("unsupported-primitives");
  if (h.kdfIterations < 100_000) throw new VaultError("kdf-downgrade");
  if (!timingSafeEqual(h.keyCheck, keyCheck)) throw new VaultError("wrong-passphrase");
  if (h.plaintextLength !== obj.length - HDR - TAG) throw new VaultError("length-mismatch");
  try {
    return new Uint8Array(await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: h.nonce, additionalData: header, tagLength: 128 },
      k, obj.subarray(HDR)));
  } catch { throw new VaultError("corrupt-or-tampered"); }
}
```

```swift
enum Vault {
    static let headerSize = 92, tagSize = 16

    static func seal(_ plaintext: Data, key: SymmetricKey, header hdrIn: HeaderFields) throws -> Data {
        let nonce = AES.GCM.Nonce()                                   // 12 random bytes
        let header = writeHeader(hdrIn, nonce: nonce, length: plaintext.count)   // 92 bytes
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: header)
        return header + box.ciphertext + box.tag
    }

    static func open(_ obj: Data, key: SymmetricKey, keyCheck: Data) throws -> Data {
        guard obj.count >= headerSize + tagSize else { throw VaultError.truncated }
        let header = obj.prefix(headerSize)
        let h = try readHeader(header)
        guard h.magic == "CBV1" else { throw VaultError.notAVaultObject }
        guard h.formatVersion <= 1 else { throw VaultError.schemaTooNew }
        guard h.kdfId == 1, h.cipherId == 1 else { throw VaultError.unsupportedPrimitives }
        guard h.kdfIterations >= 100_000 else { throw VaultError.kdfDowngrade }
        guard constantTimeEquals(h.keyCheck, keyCheck) else { throw VaultError.wrongPassphrase }
        let body = obj.dropFirst(headerSize)
        guard body.count == h.plaintextLength + tagSize else { throw VaultError.lengthMismatch }
        let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: h.nonce),
                                        ciphertext: body.prefix(h.plaintextLength),
                                        tag: body.suffix(tagSize))
        do { return try AES.GCM.open(box, using: key, authenticating: header) }
        catch { throw VaultError.corruptOrTampered }
    }
}
```

**Key verification, and why `keyCheck` exists.** Without it, a wrong passphrase is indistinguishable from a corrupt or tampered file: both surface as a GCM tag failure. That would force the UI to say "either your passphrase is wrong or your data is damaged", which is unacceptable at the one moment a user is most likely to panic. `keyCheck` is an HKDF output that depends only on the passphrase and the salt, so:

- `keyCheck` mismatch → **`wrong-passphrase`**: "口令不正确" and a retry field. No data was touched.
- `keyCheck` match but tag failure → **`corrupt-or-tampered`**: "账页数据损坏或被篡改", offer to re-pull from the other adapter or restore from an export. This is a serious, loud, different message.

`keyCheck` is a public value derived from a secret. It provides an offline verifier for a passphrase guess — but so does the ciphertext itself, and both cost one PBKDF2 evaluation, so the marginal loss is zero. The comparison MUST be constant-time on both platforms out of habit, even though nothing secret is being compared.

### 5.6 验证码 — key fingerprint

```
fp = SHA256( 0x01 || K_fp )           // domain-separated
verificationCode = uppercase hex of fp[0..8), grouped in four pairs of bytes
                 → "4F2A · 91C7 · 0B3E · D845"
```

Rendered in mono on 标准与设备 next to each device. Two devices showing the same four quads are provably holding the same key, which is the entire multi-device trust story and it needs no server. 64 bits of fingerprint is not collision-resistant in the adversarial sense, but the adversary here would have to make the *user's own second device* derive a colliding key from a passphrase they typed themselves — not a realistic attack. It is a typo detector and a "did the sync actually connect the two devices" indicator, and it is labelled as such, never as an authentication mechanism.

### 5.7 Known-answer tests

`scripts/fixtures/crypto-kat.json` pins, and both suites assert:

- PBKDF2: `passphrase = "正确的马电池订书钉"` (NFC), `salt = 000102…0f`, `iterations = 600000` → `MK` hex.
- HKDF: each of the three `info` strings → 32-byte hex.
- Envelope: fixed `nonce`, fixed plaintext `{"k":"segment",…}` → full object hex, and the reverse.
- Negative vectors: flipped header byte → `corrupt-or-tampered`; wrong passphrase → `wrong-passphrase`; `kdfIterations = 1000` → `kdf-downgrade`; truncated tag → `truncated`.

Any change to the crypto path that does not also change these vectors is a bug in the change.

### 5.8 Passphrase policy and rotation

- Minimum 12 characters or 6 words. The UI shows an estimated-entropy bar computed from a local 2 048-word list plus a character-class heuristic — no network, no dictionary download. Below ~60 bits the sheet says plainly: `此口令在离线破解下大约可撑 3 天`, and requires a second confirmation. It does not block: the vault is the user's.
- **There is no recovery.** Lost passphrase = lost vault. This is stated at creation, in a sentence the user must tap through, and again in 设置. The offered mitigation is the plaintext export of §10.
- **Rotation** re-derives from a **new random `vaultSalt`** and rewrites every object: new salt → new `MK` → new `K_data` → all objects re-sealed with fresh nonces, published as a new snapshot + empty segment list under a new index. The old objects go into `gc` immediately. Rotation is an all-or-nothing operation performed by one device while the others show `待同步`; on their next pull they will fail `keyCheck` and prompt for the new passphrase — which is the correct behaviour and must be worded as `口令已在其他设备上更改`, not as a corruption error. The client distinguishes the two by comparing the header's `kdfSalt` with the one it has cached: **different salt + keyCheck mismatch = rotation**, same salt + keyCheck mismatch = wrong passphrase.

---
## 6. The adapter interface, and Adapter A — GitHub vault

### 6.0 The shared interface

Both adapters implement exactly this. Nothing above this line knows which one is in use.

```ts
export type IndexToken = string;            // opaque CAS token: git blob sha, or a version int

export interface VaultAdapter {
  readonly kind: "github" | "server";

  /** Cheap liveness + auth probe. Never throws for "offline"; returns a status. */
  probe(): Promise<{ ok: boolean; reason?: AdapterError; serverTimeMs?: number }>;

  /** Reads the index object. `etag` enables a conditional fetch. */
  getIndex(etag?: string): Promise<
    | { kind: "ok"; bytes: Uint8Array; token: IndexToken; etag?: string }
    | { kind: "not-modified" }
    | { kind: "absent" }>;

  /** Compare-and-swap the index. Rejects with AdapterError.Conflict if `expected` is stale. */
  putIndex(bytes: Uint8Array, expected: IndexToken | null): Promise<IndexToken>;

  /** Create-only. Succeeds, or resolves silently if an object with this id already exists. */
  putObject(id: Id, bytes: Uint8Array): Promise<void>;

  getObject(id: Id): Promise<Uint8Array>;              // throws AdapterError.NotFound
  getObjects(ids: Id[]): Promise<Map<Id, Uint8Array>>; // batched where the transport allows

  /** Best-effort GC. A failure is logged, never surfaced, never retried inline. */
  deleteObject(id: Id): Promise<void>;

  /** Optional fast path: ids added since a cursor. Adapter A returns null (it diffs the index). */
  changesSince?(cursor: string | null): Promise<{ ids: Id[]; cursor: string } | null>;
}

export const enum AdapterError {
  Offline, Unauthorized, Forbidden, NotFound, Conflict, RateLimited, TooLarge, Server, Malformed
}
```

```swift
public protocol VaultAdapter: Sendable {
    var kind: AdapterKind { get }
    func probe() async -> ProbeResult
    func getIndex(etag: String?) async throws -> IndexFetch
    func putIndex(_ bytes: Data, expected: String?) async throws -> String
    func putObject(id: String, bytes: Data) async throws
    func getObject(id: String) async throws -> Data
    func getObjects(ids: [String]) async throws -> [String: Data]
    func deleteObject(id: String) async throws
    func changesSince(_ cursor: String?) async throws -> ChangeBatch?
}
```

Every method takes bytes and returns bytes. **No adapter ever parses a payload, sees a key, or knows what a Txn is.** That is what makes them interchangeable, and it is also what makes the threat model tractable: the attack surface of a transport is exactly "can it lie about bytes", and §3.7 plus GCM cover that.

### 6.1 Why GitHub at all

The deployment reality is a static GitHub Pages origin with no backend. GitHub's REST Contents API gives, for free: authenticated per-user storage, CORS-enabled browser access, byte-accurate reads, and — critically — **compare-and-swap via the blob SHA**, which is the one primitive a CRDT sync loop actually needs from a server. It is not a database and is not treated as one.

### 6.2 Repository layout

A **private** repository, distinct from the Pages repository. Default branch `main`, no branch protection, no Actions, no Pages.

```
countbook-vault/                     (private)
├── README.md                        plaintext, human-facing, never read by the app
└── vault/
    ├── index.cbv                    the mutable index object   (~2–9 KB)
    ├── seg/
    │   ├── 4P6R8T0V2X4Z6B8D0F2H4J9K2M.cbv
    │   └── …                        ≤ 64 files, each ≤ 512 KiB
    └── snap/
        ├── 9K2M4P6R8T0V2X4Z6B8D0F2H4J.cbv
        └── …                        current snapshot's parts + tombstoned parts pending GC
```

Object path = `vault/seg/<id>.cbv` or `vault/snap/<id>.cbv`. The adapter tries `seg/` then `snap/` on a bare `getObject(id)`; the index records which, so this fallback is only for repair paths.

`README.md` is written once at setup:

```
这是 据实 Countbook 的加密账页仓库。
所有 .cbv 文件均为 AES-256-GCM 密文，服务端与 GitHub 均无法读取。
请勿手动修改或删除本目录下的文件；请勿将此仓库设为公开。
```

### 6.3 The exact REST calls

Common headers on every request:

```
Authorization: Bearer <fine-grained PAT>
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
User-Agent: Countbook/1.0 (+https://github.com/<owner>/countbook)
```

`api.github.com` responds with `Access-Control-Allow-Origin: *` and exposes the rate-limit headers to browsers, so the web client calls it directly from the Pages origin with `fetch`. No proxy, no CDN, no third-party JS.

#### getIndex

```
GET /repos/{owner}/{repo}/contents/vault/index.cbv?ref=main
If-None-Match: "<etag>"        (when a cached etag exists)
```

- `200` → JSON `{ content: "<base64, wrapped at 60 cols>", encoding: "base64", sha: "<blob sha>", size, path }`.
  `token = sha`. Decode base64 **after stripping `\n`** (Swift: `Data(base64Encoded:options:.ignoreUnknownCharacters)`; TS: `atob(json.content.replace(/\n/g, ""))` then to bytes).
- `304` → `{ kind: "not-modified" }`. **304 responses do not count against the primary rate limit**, which is why polling uses this path.
- `404` → `{ kind: "absent" }` (fresh vault, or wrong repo).
- `401` → `Unauthorized` (bad/expired token). `403` with `x-ratelimit-remaining: 0` → `RateLimited`; `403` otherwise → `Forbidden` (token lacks Contents:write, or repo access was removed).
- If `size > 1_000_000` the `content` field comes back empty; fall through to the blobs API:
  `GET /repos/{owner}/{repo}/git/blobs/{sha}` with `Accept: application/vnd.github.raw` returns raw bytes up to 100 MB. The 512 KiB object cap (§4.4) means this path should never fire; it is implemented anyway because a silent empty-string decode would look like corruption.

#### getObject

Identical `GET …/contents/vault/seg/<id>.cbv?ref=main`, except `Accept: application/vnd.github.raw` is used, which returns the **raw bytes** with no base64 hop and no JSON parse. The blob SHA is not needed for immutable objects.

#### getObjects (batch)

The Contents API has no batch read. The adapter issues up to **4 concurrent** `GET`s with a bounded queue. It never exceeds 4 in flight: GitHub's secondary limits punish concurrency far more aggressively than volume, and a cold start pulling 64 segments at 4-wide over ~200 ms each takes ~3 s, which is acceptable and invisible behind the snapshot-first render of §4.4.

#### putObject (create-only)

```
PUT /repos/{owner}/{repo}/contents/vault/seg/<id>.cbv
Content-Type: application/json

{ "message": "seg 4P6R…",
  "content": "<base64 of the whole CBV1 object, no newlines>",
  "branch": "main" }
```

**`sha` is deliberately omitted.** Omitting it means "create"; GitHub returns `422` if the path already exists. Since segment ids are 128-bit random, a `422` here can only mean "my own earlier attempt actually succeeded" — so the adapter treats `422` on `putObject` as **success**. This is what makes retry-after-timeout safe (§2.9).

Responses: `201` created; `422` already exists → success; `409` → transient ref contention, retry per §6.5; `413`/`422` with a size message → `TooLarge`.

#### putIndex (compare-and-swap)

```
PUT /repos/{owner}/{repo}/contents/vault/index.cbv

{ "message": "index seq 138",
  "content": "<base64>",
  "sha": "<expected blob sha>",     // omitted only when creating the very first index
  "branch": "main" }
```

- `200`/`201` → success; the response's `content.sha` is the **new token**, which the client caches so the next CAS needs no extra read.
- `409 Conflict` → someone else wrote first. This is the CAS failure and it is **expected traffic, not an error**: re-read, re-merge, retry (§6.4).
- `422` with `"sha" wasn't supplied` / `does not match` → also treated as a CAS failure.

#### deleteObject

```
DELETE /repos/{owner}/{repo}/contents/vault/seg/<id>.cbv
{ "message": "gc <id>", "sha": "<blob sha of that file>", "branch": "main" }
```

Requires the file's current SHA, so GC first reads the tree once:
`GET /repos/{owner}/{repo}/git/trees/main?recursive=1` → one request for every path+sha in the vault. This is also the repair path for a lost/corrupt index: the tree lists every object, and every object is self-describing after decryption.

#### probe

```
GET /repos/{owner}/{repo}
```
`200` → ok, and `response.headers["date"]` gives `serverTimeMs` for the clock-drift diagnostic (§2.3.3) — a free authoritative clock, which is worth one request per session.

### 6.4 The compare-and-swap loop

```
push(newEvents):
  1. segBytes ← seal(canonical(segment{events: newEvents}))      // encrypt ONCE
     segId    ← random 128-bit id
  2. putObject(segId, segBytes)                                  // create-only, idempotent
  3. attempt ← 0
     loop:
       a. (idxBytes, token) ← getIndex()                          // unconditional; must be fresh
       b. idx ← open(idxBytes)
          verify idx.vaultId, idx.seq ≥ lastSeenIndexSeq          // §3.7 rollback guard
       c. if segId ∈ idx.segments ∪ idx.snapshot.covers: DONE     // a previous attempt won
       d. idx' ← idx with:
              seq        = idx.seq + 1
              updatedAt  = now, updatedBy = deviceId
              segments   = idx.segments ++ [{id: segId, …}]
              devices    = upsert(self)
          if compactionTriggered(idx'): run §4.5 steps 1–3 inside this same idx'
       e. try putIndex(seal(canonical(idx')), token) → DONE
          catch Conflict:
              attempt += 1
              if attempt > 6: state ← "pending"; schedule retry in 60 s; STOP
              sleep(fullJitter(attempt)); continue loop
```

Two properties worth naming. **The segment is encrypted and uploaded exactly once**, no matter how many CAS rounds the index needs — encryption is the expensive part and the loop never repeats it. And **step 3c makes the whole loop idempotent**: if a `putIndex` response was lost but actually committed, the next iteration sees its own segment already listed and exits clean rather than double-listing it.

Pull is the mirror image and needs no CAS:

```
pull():
  1. r ← getIndex(cachedEtag)
     if r.not-modified: DONE (nothing changed since last poll — costs no rate-limit budget)
  2. idx ← open(r.bytes); rollback-guard; cache etag + token
  3. if idx.snapshot.id ≠ localSnapshotId:
        fetch every snapshot part; verify stateHash; adopt as base
     needed ← idx.segments \ locallyKnownSegmentIds
  4. getObjects(needed) → for each: open, verify vaultId + k=="segment",
                          recvTick(every event), append to local log
  5. re-fold (incrementally, §2.10 Lemma 3); persist; update lastSeenIndexSeq
  6. if idx.devices[self].ackSnapshot ≠ idx.snapshot.id: piggyback the ack on the next push,
     or do a standalone CAS at most once per hour
```

### 6.5 Retry, backoff, rate limits

**Backoff.** Full jitter: `sleep = random(0, min(cap, base * 2^attempt))` with `base = 250 ms`, `cap = 8 s`, max 6 attempts for CAS conflicts and 4 for 5xx. Full jitter (not equal jitter, not exponential-plus-fixed) because two phones waking on the same Wi-Fi are the exact correlated-retry scenario it exists for.

**Primary rate limit.** 5 000 requests/hour for a fine-grained PAT on a personal account. Headers `x-ratelimit-limit`, `-remaining`, `-reset`, `-used` are authoritative and are read on every response. The adapter maintains a local budget and refuses to start a sync when `remaining < 50`, showing `待同步 · 接口额度不足，{HH:mm} 后恢复`. Steady-state cost is roughly `1 conditional GET / 15 min` = 96/day, of which most are `304` and free.

**Secondary rate limits.** GitHub additionally caps content-*creating* requests (roughly 80/minute and 500/hour) and concurrency (no more than ~100 in flight, and REST request "points" per minute). The adapter enforces its own tighter ceilings: **≤ 4 concurrent requests**, **≤ 20 write requests per minute**, **≤ 200 writes per hour**. Segment batching is the reason these are comfortable: a normal day is 5–15 entries, which is 1–3 pushes.

**`403`/`429` with `retry-after`.** Obey it exactly, then add jitter. Never retry a secondary-limit rejection faster than 60 s. Never retry a `401`. Treat repeated `403 Forbidden` without a rate-limit header as a permissions problem and route to §8's `error.auth` state with a link to the token settings page.

**Write batching.** Local writes do not push immediately: a 4-second debounce coalesces a burst of entries into one segment. Push is also forced on background/foreground transition and before app termination.

### 6.6 The token

A **fine-grained personal access token**, created by the user at `github.com/settings/personal-access-tokens/new`:

| setting | value |
|---|---|
| Resource owner | the user's own account |
| Repository access | **Only select repositories** → the vault repo, nothing else |
| Permissions → **Contents** | **Read and write** |
| Permissions → Metadata | Read-only (mandatory, added automatically) |
| Everything else | no access |
| Expiration | ≤ 1 year; the app warns 14 days out using the `github-authentication-token-expiration` response header |

`Contents: write` is the entire requirement. The app MUST NOT request Administration, Actions, Workflows, or any organisation permission, and MUST NOT use a classic PAT (whose `repo` scope grants access to every repository the user can see — a categorically worse blast radius).

Setup validates by calling `GET /repos/{owner}/{repo}` and then a probe `PUT` of `vault/.probe` followed by a `DELETE`, so a token with read-only Contents fails loudly at setup rather than silently at the first push.

**Storage.** iOS: Keychain, `WhenUnlockedThisDeviceOnly`, non-synchronisable. Web: IndexedDB, and — unlike the vault key — the token is unavoidably extractable, because the `Authorization` header needs its plaintext. §9.2 states this plainly.

---

## 7. Adapter B — self-hosted server

Node ≥ 20 (`node:sqlite` or better-sqlite3-free via `node:sqlite` in 22+; the reference implementation uses `node:sqlite`), zero npm dependencies, one file-backed SQLite database, one process. It exists so a user who does not want a GitHub account, or who wants faster sync and real push, can run `node server/index.mjs` on a VPS behind Caddy.

### 7.1 What the server is and is not

It is an **object store with one CAS cell per vault, plus accounts**. It never decrypts, never merges, never validates domain rules, never orders events. Everything in §2 still runs on the client. Swapping adapter A for adapter B changes latency and push notifications; it changes no semantics.

### 7.2 SQLite schema

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;

CREATE TABLE account (                          -- an authentication record, NOT domain Account
  id            TEXT PRIMARY KEY,               -- 26-char Crockford
  email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
  pw_salt       BLOB NOT NULL,                  -- 16 B
  pw_hash       BLOB NOT NULL,                  -- 32 B scrypt output
  pw_params     TEXT NOT NULL,                  -- 'scrypt:N=32768,r=8,p=1,len=32'
  created_at    INTEGER NOT NULL,               -- epoch ms
  disabled_at   INTEGER
);

CREATE TABLE vault (
  id            TEXT PRIMARY KEY,
  account_id    TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  vault_uuid    TEXT NOT NULL,                  -- 32 hex, mirrors VaultConfig.vaultId
  index_blob    BLOB,                           -- the CBV1 index object; NULL until first push
  index_version INTEGER NOT NULL DEFAULT 0,     -- THE CAS token
  index_etag    TEXT,                           -- 'W/"<version>-<len>"'
  bytes_used    INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  UNIQUE(account_id, vault_uuid)
);

CREATE TABLE object (
  seq           INTEGER PRIMARY KEY AUTOINCREMENT,   -- the pull cursor; monotone per database
  vault_id      TEXT NOT NULL REFERENCES vault(id) ON DELETE CASCADE,
  id            TEXT NOT NULL,                       -- 26-char object id
  kind          TEXT NOT NULL CHECK (kind IN ('seg','snap')),
  bytes         BLOB NOT NULL,
  size          INTEGER NOT NULL,
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER,
  UNIQUE(vault_id, id)
);
CREATE INDEX object_pull ON object(vault_id, seq) WHERE deleted_at IS NULL;

CREATE TABLE session (
  id_hash       BLOB PRIMARY KEY,               -- SHA-256 of the raw token; the raw token is never stored
  account_id    TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  device_label  TEXT,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,
  revoked_at    INTEGER
);
CREATE INDEX session_account ON session(account_id) WHERE revoked_at IS NULL;

CREATE TABLE rate_bucket (                      -- login throttling, per email and per IP
  key           TEXT PRIMARY KEY,
  tokens        REAL NOT NULL,
  updated_at    INTEGER NOT NULL
);
```

`object.seq` being a database-wide `AUTOINCREMENT` (not per-vault) is deliberate: it is monotone, gap-tolerant, and single-writer-safe under SQLite's serialised writes, which is exactly what a cursor needs. Cursors are opaque strings to the client.

### 7.3 Auth

- **Password hashing: scrypt**, `N = 32768, r = 8, p = 1, dkLen = 32`, 16-byte random salt, via Node's built-in `crypto.scrypt` (`maxmem` must be raised to ≥ 64 MiB). Chosen over Argon2id only because Argon2 is not in the Node standard library and this server must have zero dependencies; chosen over bcrypt because scrypt is memory-hard and bcrypt caps the password at 72 bytes. Parameters are stored per row (`pw_params`) so they can be raised later and rehashed transparently on next successful login. Verification is constant-time (`crypto.timingSafeEqual`).
- **Sessions** are 256 bits of CSPRNG, base64url, sent as a cookie. The database stores only `SHA-256(token)`, so a database leak does not yield live sessions.
- **Cookie:** `Set-Cookie: __Host-cb_session=<token>; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=2592000`. The `__Host-` prefix is required, which forces `Secure`, `Path=/` and no `Domain` — meaning the cookie cannot be set by, or leak to, a sibling subdomain. 30-day sliding expiry, refreshed at most once per hour.
- **CSRF:** state-changing requests MUST carry `X-Countbook-Request: 1`. A custom header cannot be sent cross-origin without a successful preflight, and the server's CORS policy allows exactly one origin (configured `PAGES_ORIGIN`) with `Access-Control-Allow-Credentials: true`. `Origin` is additionally checked against the allowlist on every non-GET and mismatches are `403`. `SameSite=Lax` is defence in depth, not the primary control.
- **Native clients** MAY instead send `Authorization: Bearer <session token>`; the server accepts either, and Bearer-authenticated requests skip the CSRF header requirement (they are not subject to ambient credentials). iOS uses Bearer, so it never touches `HTTPCookieStorage`.
- **Login throttling:** token bucket, 10 attempts per 15 min per email **and** per IP; on exhaustion `429` with `Retry-After`. Failed logins take a constant ~200 ms floor to blunt timing oracles, and the response body for "no such user" and "wrong password" is byte-identical.
- **Registration** is gated by `SIGNUP_TOKEN` from the environment (this is a personal server; open registration is a bug, not a feature).

### 7.4 Common conventions

Base path `/v1`. All bodies JSON except object payloads, which are `application/octet-stream` raw `CBV1` bytes (no base64 — it would inflate every transfer by 33 % for no benefit here).

Error shape:

```json
{ "error": { "code": "conflict", "message": "index version mismatch", "detail": { "current": 138 } } }
```

`code ∈ {unauthorized, forbidden, not_found, conflict, too_large, rate_limited, malformed, server_error}`, mapping 1:1 onto `AdapterError`.

### 7.5 Endpoints

| method | path | body | success | notes |
|---|---|---|---|---|
| `POST` | `/v1/auth/register` | `{email, password, signupToken}` | `201` + session cookie | disabled unless `SIGNUP_TOKEN` matches |
| `POST` | `/v1/auth/login` | `{email, password, deviceLabel?}` | `200 {accountId, expiresAt}` + cookie / `{token}` for Bearer | |
| `POST` | `/v1/auth/logout` | — | `204` | revokes the current session |
| `GET` | `/v1/auth/session` | — | `200 {accountId, email, expiresAt, sessions:[…]}` | also the probe endpoint; `Date` header feeds clock drift |
| `POST` | `/v1/auth/password` | `{current, next}` | `204` | revokes all other sessions |
| `DELETE` | `/v1/auth/sessions/{id}` | — | `204` | revoke another device |
| `POST` | `/v1/vaults` | `{vaultUuid}` | `201 {vaultId}` | idempotent on `(account, vaultUuid)` |
| `GET` | `/v1/vaults` | — | `200 {vaults:[{id, vaultUuid, indexVersion, bytesUsed}]}` | |
| `GET` | `/v1/vaults/{vid}/index` | — | `200` raw bytes, `ETag: W/"138-9123"`, `X-Index-Version: 138` / `304` / `404` | `If-None-Match` honoured |
| `PUT` | `/v1/vaults/{vid}/index` | raw bytes | `200 {version}` / `412` | `If-Match: "<version>"` required; `If-Match: *` only when no index exists |
| `PUT` | `/v1/vaults/{vid}/objects/{oid}` | raw bytes | `201` / `200` if identical bytes already present / `409` if different bytes present | create-only; ≤ 512 KiB |
| `GET` | `/v1/vaults/{vid}/objects/{oid}` | — | `200` raw bytes, `Cache-Control: private, immutable, max-age=31536000` | |
| `POST` | `/v1/vaults/{vid}/objects/batch` | `{ids:[…]}` (≤ 64) | `200` multipart-free JSON `{objects:{id: base64}}` | one round trip for a cold start |
| `DELETE` | `/v1/vaults/{vid}/objects/{oid}` | — | `204` | soft delete (`deleted_at`), purged by a nightly vacuum after 7 days |
| `GET` | `/v1/vaults/{vid}/changes?since={cursor}&limit=200` | — | `200 {ids:[…], cursor, hasMore, indexVersion}` | the cursor fast path |
| `GET` | `/v1/healthz` | — | `200 {ok:true, version, timeMs}` | unauthenticated, no vault info |

**`PUT …/index` semantics.** `If-Match` is the CAS. The handler runs one SQLite transaction:

```sql
BEGIN IMMEDIATE;
UPDATE vault SET index_blob = ?, index_version = index_version + 1,
                 index_etag = ?, updated_at = ?
 WHERE id = ? AND index_version = ?;         -- ← the expected version
-- changes() == 0  →  ROLLBACK, respond 412 with the current version
COMMIT;
```

Single-statement CAS under `BEGIN IMMEDIATE` is atomic and needs no application-level locking. The `412` body carries `{current: <version>}` so the client can skip a re-read round trip.

**`GET …/changes` semantics.** Returns object ids with `seq > cursor`, ascending, non-deleted, capped at `limit`. The cursor is `String(seq)` of the last row returned. This is Adapter B's optimisation over Adapter A's index-diffing: a device can discover new objects without fetching and decrypting the index. The index is still the source of truth for *which* objects are current (a `changes` result may include objects that a subsequent compaction has since orphaned); `changes` only ever saves a round trip, never decides anything.

**Quotas.** Per account: 200 MB, 20 000 objects. `413` with `code: too_large` beyond that. Body size cap 512 KiB + 1 KiB slack for objects, 64 KiB for JSON endpoints; the server rejects on `Content-Length` before reading the stream.

**Deployment.** Behind Caddy with automatic TLS:

```
vault.example.com {
  encode zstd gzip
  reverse_proxy 127.0.0.1:8787
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
    Referrer-Policy "no-referrer"
  }
}
```

The Node process binds `127.0.0.1` only, runs as an unprivileged user, and stores `countbook.db` with mode `0600`. Backups are `sqlite3 countbook.db ".backup"` on a timer — and since every blob is ciphertext, the backup needs no additional encryption to be safe from the backup host.

---
## 8. Client sync state machine

### 8.1 States

Sync is never a spinner and never a modal. It is **one word on one hairline row** in 标准与设备, plus — in exactly one failure case — a single line on 今日. The design system permits `--fig-held` (dark brass) for pending, and nothing else; failure is carried by the word, not by colour.

| state | UI word (zh) | colour | meaning |
|---|---|---|---|
| `disabled` | 未启用 | ink-500 | sync off; local-only. The default. |
| `idle` | 已同步 · 09-08 20:41 | ink-500 + mono timestamp | outbox empty, index token fresh |
| `pending` | 待同步 · 3 笔 | `--fig-held` | outbox non-empty, waiting for a trigger or backoff |
| `syncing` | 同步中 | ink-500 | a pull/push cycle is running. **No spinner, no progress bar.** |
| `offline` | 离线 | ink-300 | no network, or `probe()` failed with `Offline` |
| `error.auth` | 需要重新授权 | ink-900 | `401`, or `403 Forbidden` without a rate-limit header |
| `error.rate` | 待同步 · 额度不足 21:14 恢复 | `--fig-held` | primary or secondary rate limit; the reset time is printed |
| `error.rollback` | 同步异常 · 版本回退 | ink-900 | §3.7; requires a user decision |
| `error.crypto` | 口令不匹配 | ink-900 | `keyCheck` failed on a remote object — rotation on another device, or wrong passphrase |
| `error.fatal` | 同步失败 · 已保留本机账页 | ink-900 | anything unrecoverable; local data is untouched and complete |

**Every error state is non-blocking.** Capture, ledger, report, want list and Sunday reckoning all work identically with sync in any state, because sync is an enhancement to a local-first store. The only state that ever appears outside 设置 is `error.auth`, `error.rollback` and `error.crypto`, as a single 11px label row beneath 今日可用's provenance line — because those three require the user to do something and will otherwise silently stop protecting their data.

### 8.2 Transition table

```
                    ┌──────────┐  enable(adapter, credentials)
                    │ disabled │ ─────────────────────────────┐
                    └──────────┘                              ▼
                                                        ┌──────────┐
    ┌─────────────────────────────────────────────────► │   idle   │ ◄────┐
    │                                                   └────┬─────┘      │
    │                                    localWrite / trigger│            │
    │                                                        ▼            │
    │                                                  ┌───────────┐      │
    │                        debounce 4 s, or trigger  │  pending  │      │ pull+push ok
    │                                                  └────┬──────┘      │ (outbox empty)
    │                                                       ▼             │
    │  network lost                                   ┌───────────┐       │
    ├────────────────────────────────────────────────►│  syncing  │───────┘
    │                                                 └────┬──────┘
    │                          ┌───────────────────────────┼────────────────────────┐
    ▼                          ▼                           ▼                        ▼
┌─────────┐            ┌──────────────┐          ┌──────────────────┐      ┌──────────────┐
│ offline │            │  error.auth  │          │   error.rate     │      │ error.crypto │
└────┬────┘            └──────┬───────┘          └────────┬─────────┘      └──────┬───────┘
     │ network back           │ user re-auths             │ reset time passes     │ passphrase
     └────────────────────────┴───────────────────────────┴───────────────────────┘  entered
                                          ▼
                                     ┌──────────┐
                                     │ pending  │   (outbox is never lost across any transition)
                                     └──────────┘

  Conflict (409/412) does NOT leave `syncing`: it is handled inside the CAS loop (§6.4).
  After 6 failed CAS attempts → `pending`, retry scheduled in 60 s.
```

Formal transitions:

| from | event | to | side effect |
|---|---|---|---|
| `disabled` | `enable` | `syncing` | validate credentials, `probe`, create vault if absent |
| `idle` | local write | `pending` | append to outbox; start 4 s debounce |
| `pending` | debounce fired / manual / foreground / network regained / 15 min timer | `syncing` | run pull-then-push |
| `syncing` | pull+push ok, outbox empty | `idle` | persist `lastSyncedAt`, `lastSeenIndexSeq`, etag |
| `syncing` | pull+push ok, outbox refilled during the cycle | `pending` | immediate re-arm (no debounce) |
| `syncing` | `Offline` | `offline` | keep outbox; register a reachability observer |
| `syncing` | `Unauthorized` / `Forbidden` | `error.auth` | keep outbox; stop all timers |
| `syncing` | `RateLimited` | `error.rate` | schedule at `x-ratelimit-reset` + jitter |
| `syncing` | `keyCheck` failure | `error.crypto` | do **not** overwrite local data; prompt for passphrase |
| `syncing` | `index.seq < lastSeenIndexSeq` | `error.rollback` | stop; require explicit user choice |
| `syncing` | 6× CAS conflict / repeated 5xx | `pending` | retry in 60 s, then 5 min, then 15 min |
| any | `disable` | `disabled` | outbox retained; nothing deleted |

### 8.3 Triggers

| trigger | web | iOS |
|---|---|---|
| app becomes active | `visibilitychange` → visible | `scenePhase == .active` |
| app backgrounds | `visibilitychange` → hidden, plus `pagehide` | `scenePhase == .background` |
| network regained | `window.online` | `NWPathMonitor` |
| periodic | `setInterval(autoSyncIntervalSec)` while visible only | `BGAppRefreshTask`, earliest begin +15 min, best-effort |
| after a local write | 4 s debounce, coalescing | same |
| manual | 立即同步 text action in 设置 | same |
| before termination | `pagehide` → `navigator.sendBeacon` is unusable (needs auth headers + CAS), so the outbox is simply persisted and pushed next launch | `applicationWillTerminate` best-effort |

The web client MUST NOT sync while hidden: background `fetch` from a hidden tab is unreliable and burns rate-limit budget for no user benefit. The Service Worker is used for **offline asset caching only** — it is not a sync engine, it holds no key, and it never touches the vault.

**Notifications.** On iOS, a want-list unlock schedules a local `UNTimeIntervalNotificationTrigger` at `unlockAt`; no server push is required and none is used. On web there is no equivalent that works reliably on an iOS home-screen PWA in mainland China, so the unlock is surfaced by a check at next open: the 待购 tab shows a count badge and unlocked items float to the top. This asymmetry is real and is named in the product risk list; the protocol does not pretend to solve it.

### 8.4 Outbox and local persistence

```sql
-- Web: SQLite-shaped IndexedDB object stores. iOS: a real SQLite file.
event(id TEXT PRIMARY KEY, t TEXT, hlc TEXT, dev TEXT, p BLOB, synced INTEGER DEFAULT 0)
CREATE INDEX event_hlc ON event(hlc);
CREATE INDEX event_outbox ON event(synced) WHERE synced = 0;

meta(k TEXT PRIMARY KEY, v BLOB)
  -- clock_pt, clock_l, deviceId, lastSyncedAt, lastSeenIndexSeq, indexToken, indexEtag,
  -- snapshotId, knownSegmentIds (JSON array), vaultSalt, keyCheck
```

- The outbox is `SELECT * FROM event WHERE synced = 0 ORDER BY hlc`. It is **the same table as the log** — there is no separate queue to fall out of sync with, and a crash mid-push loses nothing.
- `synced = 1` is set only after the index CAS commits, never after the segment `PUT`. Marking too early is the one way to lose an event permanently; marking too late merely re-uploads a segment, which is idempotent (§2.9).
- An outbox is capped at nothing. A device offline for a year holds a year of events and pushes them as ~N/500 segments on reconnect, throttled to the write ceilings of §6.5.
- Web storage is IndexedDB, not `localStorage`: `localStorage` is synchronous, 5 MB, string-only and evictable. The app requests `navigator.storage.persist()` at first write and shows a one-line warning in 设置 if it is denied, because a browser evicting the vault of a local-first app is a data-loss event the user deserves to be told about in advance.

### 8.5 What the user is shown, in words

- Success is silent. There is no toast, no checkmark, no "已保存". The timestamp changes; that is all.
- `pending` is not an error and is never phrased as one. `待同步 · 3 笔` is a statement of fact in dark brass.
- The only sentence the sync engine is permitted to editorialise with is none. Copy is: 已同步 / 待同步 / 同步中 / 离线 / 需要重新授权 / 同步异常 · 版本回退 / 口令不匹配 / 同步失败 · 已保留本机账页. A clerk does not apologise.

---

## 9. Threat model, stated honestly

### 9.1 What is actually protected

| property | held? | by what |
|---|---|---|
| Confidentiality of ledger contents against GitHub / the server host | **yes** | AES-256-GCM under a key derived only from a passphrase the server never sees |
| Integrity / tamper-evidence of every object | **yes** | GCM tag over ciphertext + header (AAD) |
| Object substitution (serving object X where Y was asked for) | **yes** | `vaultId` + `k` + `id` are inside the plaintext and are checked (§4.2) |
| Cross-vault mixing | **yes** | `vaultId` in header and plaintext |
| Wrong-passphrase distinguished from corruption | **yes** | `keyCheck` (§5.5) |
| Rollback / replay of the whole vault to an older state | **detected, not prevented** | monotone `index.seq` + `lastSeenIndexSeq` (§3.7) |
| Confidentiality of *metadata* | **no** | see §9.4 |
| Availability | **no** | GitHub can suspend an account; a VPS can die. Export (§10) is the answer. |
| Forward secrecy | **no** | one long-lived key; compromise of the passphrase decrypts all history, past and future |
| Multi-user / shared vaults | **out of scope** | one passphrase, one vault, one person |

### 9.2 Key and token exposure

- **Web XSS is the sharpest edge.** A successful XSS on the Pages origin can (a) use the non-extractable `CryptoKey` to decrypt everything for as long as the page lives, and (b) read the GitHub PAT from IndexedDB and exfiltrate it, giving the attacker persistent read/write to the vault repo. Non-extractability limits key *theft*, not key *use*. Mitigations actually implemented: a strict CSP (`default-src 'self'; script-src 'self'; connect-src 'self' https://api.github.com https://<server>; object-src 'none'; base-uri 'none'; frame-ancestors 'none'`), zero third-party scripts, zero CDN, no `eval`, no `innerHTML` with user content, and a fine-grained PAT scoped to one repository so the blast radius stops at the vault. The residual risk is real and is not hand-waved away.
- **iOS** stores both key and token in the Keychain with `WhenUnlockedThisDeviceOnly` and no iCloud sync. A jailbroken or malware-bearing device defeats this; nothing in an app can prevent it.
- **A stolen PAT alone reveals nothing.** It grants access to ciphertext. It does grant the ability to *delete* the vault, which is an availability attack — hence §10.
- **Passphrase strength is the whole game.** PBKDF2-600k costs an attacker roughly 10⁻³ s per guess on a good GPU rig; a 6-word diceware passphrase (~77 bits) is unbreakable, a memorable 10-character password (~35 bits) falls in hours. The app says so, in those terms, at creation, and refuses to pretend otherwise.

### 9.3 What a malicious or compromised transport can do

Assume full control of GitHub's API responses or the self-hosted server:

- **Cannot** read plaintext, forge a valid object, or alter one undetected.
- **Can** withhold objects (a client sees a stale but internally consistent ledger — detectable only as "sync hasn't advanced in a while", which the timestamp in 已同步 exposes).
- **Can** serve an older index (detected by `index.seq`, §3.7).
- **Can** delete everything (availability; §10 is the mitigation).
- **Can** learn write timing and volume (§9.4).
- A client with a valid key — i.e. the user's own compromised device — can write anything, including events with manipulated HLCs that defeat sealing. There is no cryptographic defence against the ledger's owner attacking their own ledger, and the product does not claim one. 结账 immutability is a defence against **self-deception**, not against an adversary.

### 9.4 Metadata leakage, enumerated

What GitHub (or the server host, or a network observer with TLS metadata) learns:

1. **That a private repo named e.g. `countbook-vault` exists**, and its size.
2. **When you write, and roughly how much.** Every push is a commit with a timestamp. A month of commits is a precise map of when the user opened the app and how many entries each session produced. This is a genuinely revealing signal about daily routine and it is **not** mitigated in v1.
3. **Object count and sizes.** A 512 KiB snapshot means "a lot of history"; a 900-byte segment means "a few entries".
4. **Object plaintext lengths**, from the header's `plaintextLength` and the file size. Since object contents are batched and variable, this is weak, but it is not zero: a lone segment of ~300 bytes is one entry.
5. **Commit history is permanent** in adapter A. `DELETE` removes a file from the tree, not from git history — an attacker who later obtains the token can `git clone` every version of every object ever written. They are all still encrypted, so this is a *volume* leak, not a content leak, but it means GC does not shrink the repository and it means a compromised passphrase exposes deleted history too. Mitigation offered in 设置: 重建仓库 — create a fresh repo from the current snapshot and delete the old one. It is a manual, explicit action with a clear explanation, not a background job.
6. **Filenames leak nothing** — object ids are random, not ULIDs, specifically so that a directory listing does not reconstruct a write-time series. (This is why §1.0 forbids timestamped ids.)

Deliberately **not** done in v1, with reasons: padding objects to fixed sizes (costs bandwidth and complicates the 512 KiB cap for a weak signal), dummy writes on a schedule (burns rate limit and battery to obscure a signal the user's own commit times already reveal at a coarser grain), and per-object salts (would force one PBKDF2 per object, ~400 ms each, making cold start unusable).

### 9.5 Denial and abuse on adapter B

Registration is token-gated; login is throttled per email and per IP; bodies are capped before reading; quotas are enforced per account; SQLite runs in WAL with a single writer, so a flood degrades to slow rather than corrupt. There is no email delivery, so there is no password reset — a lost server password is recovered by editing the database on the box you own, which is stated in the server README.

---

## 10. Export and import

### 10.1 Full backup format

One **unencrypted** JSON file. Unencrypted is deliberate: a backup you cannot open without the app is not a backup. The user is warned in one line, at the moment of export.

Filename: `countbook-YYYYMMDD-HHmm.json` (local time).

```json
{
  "kind": "countbook.export",
  "formatVersion": 1,
  "schemaVersion": 1,
  "exportedAt": 1757337660123,
  "exportedBy": { "deviceId": "7F3A…", "platform": 1, "appVersion": "1.0.3" },
  "config": { "…VaultConfig…" },
  "counts": { "events": 4213, "txns": 2871, "wishes": 44, "subscriptions": 11, "quarantine": 4 },
  "log": [ { "dev": "…", "hlc": "…", "id": "…", "p": { }, "t": "txn.create" } ],
  "state": { "…the folded LedgerState, derived fields INCLUDED for human/tool consumption…" },
  "quarantine": [ { "event": { }, "reason": "sealed-period", "firstSeenAt": 0 } ],
  "integrity": {
    "logHash": "…SHA-256 of canonicalJSON(log)…",
    "stateHash": "…SHA-256 of canonicalJSON(state without derived fields)…"
  }
}
```

- `log` is **the authoritative content**; `state` is a convenience rendering. On import, `state` is ignored and recomputed. If `fold(log) ≠ state`, the import proceeds from `log` and records a diagnostic — the log is always the truth.
- `log` is sorted by `hlc` ascending. `quarantine` is included so nothing is lost across a backup round trip.
- The file is canonical JSON except that it is pretty-printed with 2-space indentation for human readability; `integrity` hashes are computed over the **canonical** (unindented) form of the respective subtrees.

### 10.2 Import

```
import(file):
  1. Validate kind, formatVersion ≤ 1. A newer formatVersion is refused with a plain message,
     never partially applied.
  2. Verify integrity.logHash. On mismatch: warn, offer to continue, never silently proceed.
  3. If config.vaultId == local vault: MERGE — union the logs (§2.10), re-fold, push.
     Nothing is overwritten, nothing is duplicated: event ids deduplicate.
  4. If config.vaultId ≠ local vault:
       a. offer 合并 — import events into the current vault. Because ids are globally unique
          and HLCs carry foreign nodeIds, this is a well-defined union; the imported vault's
          VaultConfig is DISCARDED, and any event inadmissible under the local config
          (e.g. a patch into a period this vault considers sealed) quarantines and is reported
          by count before the user confirms.
       b. or 替换 — destroy the local vault and adopt the imported one wholesale. Requires
          typing the word 替换. Takes a pre-import export first, automatically.
  5. Recompute derive(); rebuild indices; push as a fresh snapshot.
```

Import is **always** additive at the event layer. There is no import path that silently loses an event.

### 10.3 CSV export (账页导出)

A second, lossy, spreadsheet-facing export. UTF-8 **with BOM** (Excel on Windows misreads Chinese without it), CRLF line endings, RFC 4180 quoting.

```csv
日期,时间,类目,账户,金额,印章,判定,备注,商户,更正后金额,已冲销,记录ID
2025-03-14,12:41,餐饮,微信,288.00,冲动,不值,朋友聚餐,海底捞,88.00,否,0F2H4J9K2M4P6R8T0V2X4Z6B8D
```

Money is rendered as a decimal string with exactly two places, derived by integer division of the 分 value — **never** by float formatting. `en` locale swaps the header row only; the number format does not change. A `导出本页` action on 报告 produces a print stylesheet / PNG that matches the screen; that is a presentation concern and is specified in the design system, not here.

### 10.4 Vault migration (changing immutable config)

`periodAnchorDay` and `sealGraceHours` cannot be edited (§1.13). Changing them is: export → create a new vault with the new config → import with 合并 into the new vault. The old vault's events keep their HLCs, so their admissibility is re-evaluated under the *new* config, and events that were admissible before may quarantine now. The import preview states the count before anything is written. This is deliberately inconvenient: it is a rare operation whose casual availability would undermine the whole sealing argument.

---

## 11. Appendices

### 11.1 Error code → user-facing string

| code | zh-CN | English |
|---|---|---|
| `Offline` | 离线 | Offline |
| `Unauthorized` | 需要重新授权 | Re-authorisation needed |
| `Forbidden` | 令牌权限不足 | Token lacks permission |
| `NotFound` | 未找到账页仓库 | Vault not found |
| `Conflict` | — (internal; never surfaced) | — |
| `RateLimited` | 接口额度不足 · {time} 后恢复 | Rate limited until {time} |
| `TooLarge` | 数据块过大 | Object too large |
| `wrong-passphrase` | 口令不正确 | Incorrect passphrase |
| `corrupt-or-tampered` | 账页数据损坏或被篡改 | Data corrupt or tampered |
| `schema-too-new` | 此账页由更新版本创建 | Vault written by a newer version |
| `rollback` | 同步异常 · 版本回退 | Sync anomaly: version rollback |

### 11.2 Version negotiation

`envelope.formatVersion` and payload `v` are independent. A client MUST:

- refuse to *write* if any object it read carries a `formatVersion` greater than its own (writing would risk destroying fields it does not understand), and say so: `此账页由更新版本创建 · 请升级后再记账`. Reading and displaying remain available.
- **preserve unknown fields on patch.** Every payload decoder keeps an `extra: Record<string, unknown>` / `[String: CanonicalJSON]` bag of keys it did not recognise and re-emits them verbatim in canonical order when re-serialising. Without this, an old client that folds and re-snapshots would silently strip a new client's fields — the classic mixed-version data-loss bug.
- quarantine unknown event types rather than dropping them (§2.8), and re-evaluate quarantine on every launch after an upgrade.

### 11.3 Field-merge summary table

| entity.field | merge |
|---|---|
| `Txn.{amountFen, flow, categoryId, accountId, intent, note, reason, merchant, occurredOn, occurredAt, tzOffsetMin, deletedAt}` | LWW, one register each |
| `Txn.{verdict, reviewedAt, verdictSource}` | LWW, one shared register (`verdictGroup`) |
| `Txn.deferCount` | G-counter over `txn.deferReview` event ids |
| `Txn.{effectiveAmountFen, voided}` | derived from the `Correction` / `Voidance` G-sets |
| `Category.*`, `Account.*` (except `creditGroup`), `Settings.*`, `Device.{name, appVersion, revokedAt}`, `Subscription.*` (except `cancelGroup`), `WishObject.*`, `Wish.{name, priceFen, categoryId, note, letterToSelf}` | LWW, one register each |
| `Account.{statementDay, dueDay}` | LWW, shared register (`creditGroup`) |
| `Subscription.{claim, cancelledOn}` | LWW, shared register (`cancelGroup`) |
| `Wish.{state, resolvedAt, txnId}` | LWW, shared register (`stateGroup`) |
| `Wish.unlockAt`, `Device.lastSeenAt` | monotone max |
| `Correction`, `Voidance`, `BudgetRevision`, `SubscriptionUsage`, `ZeroSpendDay`, `Budget` history | G-set, keyed by id (or by `on` for `ZeroSpendDay`) |

### 11.4 Constants, in one place

```
PROTOCOL_VERSION            1
SCHEMA_VERSION              1
ENVELOPE_MAGIC              "CBV1"
ENVELOPE_HEADER_BYTES       92
GCM_TAG_BYTES               16
GCM_NONCE_BYTES             12
PBKDF2_ITERATIONS           600_000        (accept 100_000 … 5_000_000 on read)
PBKDF2_SALT_BYTES           16
HKDF_INFO_DATA              "countbook/v1/data"
HKDF_INFO_KEYCHECK          "countbook/v1/keycheck"
HKDF_INFO_FINGERPRINT       "countbook/v1/fingerprint"
MAX_OBJECT_BYTES            524_288        (512 KiB)
COMPACT_SEGMENT_COUNT       64
COMPACT_EVENT_COUNT         2_000
COMPACT_BYTES               262_144
GC_GRACE_MS                 604_800_000    (7 days)
HLC_MAX_DRIFT_MS            60_000
SYNC_DEBOUNCE_MS            4_000
SYNC_INTERVAL_S             900
CAS_MAX_ATTEMPTS            6
CAS_BACKOFF_BASE_MS         250
CAS_BACKOFF_CAP_MS          8_000
GITHUB_MAX_CONCURRENCY      4
GITHUB_MAX_WRITES_PER_MIN   20
GITHUB_MAX_WRITES_PER_HOUR  200
COOLDOWN_FEN_PER_DAY        10_000
COOLDOWN_MAX_DAYS           14
DEFAULT_LEAK_CEILING_FEN    3_000
DEFAULT_COOLING_THRESH_FEN  30_000
DEFAULT_MIN_JUDGED_FOR_RATE 30
DEFAULT_MAX_DEFERRALS       3
DEFAULT_SEAL_GRACE_HOURS    24
```

These are generated into `web/src/core/constants.ts` and `ios/Countbook/Core/Constants.swift` from `scripts/tokens/protocol.json` by the same generator that emits the design tokens. A constant exists in exactly one file in this repository.

### 11.5 Implementation checklist

- [ ] `canonicalize()` passes `canonical-json.json` in both languages
- [ ] HLC `send`/`receive` pass `hlc.json`; the 200-shuffle permutation test folds to one hash
- [ ] `admit()` depends on nothing but `(event, VaultConfig)` — enforced by a pure-function lint and by passing `fold-permutations.json`
- [ ] `crypto-kat.json` passes, including all four negative vectors
- [ ] A TypeScript-written vault opens on iOS and vice versa (CI runs a Node encrypt → Swift decrypt round trip and the reverse)
- [ ] `putObject` treats `422 already exists` as success; `putIndex` treats `409`/`412` as a retry
- [ ] `synced = 1` is written only after the index CAS commits
- [ ] Money never touches a float, verified by the model lint
- [ ] Unknown fields survive a fold-and-resnapshot round trip through an older client
- [ ] Every sync state renders as one word, no spinner, no modal
