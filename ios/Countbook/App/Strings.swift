import Foundation

/// Chinese first, English second — the app is written for a Chinese reader and
/// the English is a fallback, not a source. Keys are dot-separated and stable;
/// the table mirrors `web/src/app/i18n.ts` key for key, so the two clients say
/// the same words.
///
/// The clerk's voice: state the fact, never editorialise. No exclamation marks,
/// no praise, no scolding. "本月后悔 ¥612" is the whole sentence.
enum StringKey: String, CaseIterable, Sendable {
    case appName = "app.name"
    case appTagline = "app.tagline"
    case tabToday = "tab.today"
    case tabLedger = "tab.ledger"
    case tabReport = "tab.report"
    case tabWants = "tab.wants"
    case tabSettings = "tab.settings"
    case tabNav = "tab.nav"
    case todayAvailable = "today.available"
    case todayProvenance = "today.provenance"
    case todayRecovery = "today.recovery"
    case todayNoStandard = "today.noStandard"
    case todaySetStandard = "today.setStandard"
    case todayStreak = "today.streak"
    case todayNospend = "today.nospend"
    case todayNospendDone = "today.nospendDone"
    case todayLeak = "today.leak"
    case todayLeakBare = "today.leakBare"
    case todayNoStandardHint = "today.noStandardHint"
    case todayDetailStandard = "today.detailStandard"
    case todayDetailSpent = "today.detailSpent"
    case todayDetailFixed = "today.detailFixed"
    case todayDetailDays = "today.detailDays"
    case todayDaysValue = "today.daysValue"
    case todayStripTitle = "today.stripTitle"
    case todayStripGate = "today.stripGate"
    case todayVerdict = "today.verdict"
    case todayEmptyToday = "today.emptyToday"
    case todayEmptyMonth = "today.emptyMonth"
    case todayStampNeed = "today.stampNeed"
    case todayStampWant = "today.stampWant"
    case todayStampImpulse = "today.stampImpulse"
    case captureTitle = "capture.title"
    case captureSpend = "capture.spend"
    case captureIncome = "capture.income"
    case captureSave = "capture.save"
    case captureSaveWarned = "capture.saveWarned"
    case captureHold = "capture.hold"
    case captureHoldHint = "capture.holdHint"
    case captureSuspend = "capture.suspend"
    case captureSuspendHint = "capture.suspendHint"
    case captureIntent = "capture.intent"
    case captureIntentNeed = "capture.intent.need"
    case captureIntentWant = "capture.intent.want"
    case captureIntentImpulse = "capture.intent.impulse"
    case captureIntentRequired = "capture.intentRequired"
    case captureNote = "capture.note"
    case captureMerchant = "capture.merchant"
    case capturePromise = "capture.promise"
    case captureCategory = "capture.category"
    case captureDate = "capture.date"
    case captureCancel = "capture.cancel"
    case captureSaved = "capture.saved"
    case captureKeepOpen = "capture.keepOpen"
    case captureMark = "capture.mark"
    case captureAmount = "capture.amount"
    case captureNeedAmount = "capture.needAmount"
    case captureNeedCategory = "capture.needCategory"
    case captureConsequence = "capture.consequence"
    case captureKeypad = "capture.keypad"
    case captureDecimal = "capture.decimal"
    case captureBackspace = "capture.backspace"
    case captureDayBefore = "capture.dayBefore"
    case capturePickDate = "capture.pickDate"
    case captureCoolingTier = "capture.coolingTier"
    case captureHoldPrimary = "capture.holdPrimary"
    case captureHoldOverride = "capture.holdOverride"
    case captureOverrideWarned = "capture.overrideWarned"
    case captureSuspended = "capture.suspended"
    case captureOptional = "capture.optional"
    case ledgerTitle = "ledger.title"
    case ledgerMonth = "ledger.month"
    case ledgerSealed = "ledger.sealed"
    case ledgerOpen = "ledger.open"
    case ledgerTotal = "ledger.total"
    case ledgerSearch = "ledger.search"
    case ledgerEmpty = "ledger.empty"
    case ledgerEmptyHint = "ledger.emptyHint"
    case ledgerCorrection = "ledger.correction"
    case ledgerVoided = "ledger.voided"
    case ledgerCorrect = "ledger.correct"
    case ledgerVoid = "ledger.void"
    case ledgerDelete = "ledger.delete"
    case ledgerEdit = "ledger.edit"
    case ledgerUndo = "ledger.undo"
    case ledgerDeleted = "ledger.deleted"
    case ledgerReasonRequired = "ledger.reasonRequired"
    case ledgerSealedNote = "ledger.sealedNote"
    case ledgerMonthTitle = "ledger.monthTitle"
    case ledgerPrevMonth = "ledger.prevMonth"
    case ledgerNextMonth = "ledger.nextMonth"
    case ledgerStandard = "ledger.standard"
    case ledgerSearchClear = "ledger.searchClear"
    case ledgerSearchSyntax = "ledger.searchSyntax"
    case ledgerFilters = "ledger.filters"
    case ledgerFilterAll = "ledger.filterAll"
    case ledgerFilterLeak = "ledger.filterLeak"
    case ledgerFilterCorrected = "ledger.filterCorrected"
    case ledgerFilterUnreviewed = "ledger.filterUnreviewed"
    case ledgerFilterNotWorth = "ledger.filterNotWorth"
    case ledgerDayHeader = "ledger.dayHeader"
    case ledgerDayOver = "ledger.dayOver"
    case ledgerGlyphNeed = "ledger.glyph.need"
    case ledgerGlyphWant = "ledger.glyph.want"
    case ledgerGlyphImpulse = "ledger.glyph.impulse"
    case ledgerEmptySearch = "ledger.emptySearch"
    case ledgerEmptySearchClear = "ledger.emptySearchClear"
    case ledgerEmptyBefore = "ledger.emptyBefore"
    case entryTitle = "entry.title"
    case entryAmountLabel = "entry.amountLabel"
    case entryStamp = "entry.stamp"
    case entryPromiseTitle = "entry.promiseTitle"
    case entryVerdict = "entry.verdict"
    case entryWorth = "entry.worth"
    case entryNotWorth = "entry.notWorth"
    case entryPending = "entry.pending"
    case entrySave = "entry.save"
    case entryDelete = "entry.delete"
    case entryCorrectAmount = "entry.correctAmount"
    case entryReasonLabel = "entry.reasonLabel"
    case entryCorrectSubmit = "entry.correctSubmit"
    case entryVoid = "entry.void"
    case entryVoidReason = "entry.voidReason"
    case entryHistory = "entry.history"
    case entryClosedDate = "entry.closedDate"
    case reportTitle = "report.title"
    case reportRegretMonth = "report.regretMonth"
    case reportRegretYear = "report.regretYear"
    case reportRegretRate = "report.regretRate"
    case reportRegretPending = "report.regretPending"
    case reportWishFraction = "report.wishFraction"
    case reportDeviation = "report.deviation"
    case reportUnder = "report.under"
    case reportOver = "report.over"
    case reportByCategory = "report.byCategory"
    case reportHours = "report.hours"
    case reportHoursNote = "report.hoursNote"
    case reportYear = "report.year"
    case reportNeedMoreData = "report.needMoreData"
    case reportMonthTitle = "report.monthTitle"
    case reportPrevMonth = "report.prevMonth"
    case reportNextMonth = "report.nextMonth"
    case reportEmpty = "report.empty"
    case reportNoStandard = "report.noStandard"
    case reportDeviationGate = "report.deviationGate"
    case reportRate = "report.rate"
    case reportTableCategory = "report.tableCategory"
    case reportTableCount = "report.tableCount"
    case reportTableMedian = "report.tableMedian"
    case reportTableMax = "report.tableMax"
    case reportTableRegret = "report.tableRegret"
    case reportTableEmpty = "report.tableEmpty"
    case reportHourGate = "report.hourGate"
    case reportHourLate = "report.hourLate"
    case chartStrip = "chart.strip"
    case chartStripDay = "chart.stripDay"
    case chartStripScrub = "chart.stripScrub"
    case chartStandardPerDay = "chart.standardPerDay"
    case chartDeviation = "chart.deviation"
    case chartYear = "chart.year"
    case chartRegretGate = "chart.regretGate"
    case chartRegretBlock = "chart.regretBlock"
    case chartAnnual = "chart.annual"
    case chartAnnualRow = "chart.annualRow"
    case chartAnnualOther = "chart.annualOther"
    case chartHour = "chart.hour"
    case chartHourPeak = "chart.hourPeak"
    case chartHourMore = "chart.hourMore"
    case chartColDay = "chart.colDay"
    case chartColHour = "chart.colHour"
    case chartColCount = "chart.colCount"
    case chartColAmount = "chart.colAmount"
    case chartEmpty = "chart.empty"
    case wantsTitle = "wants.title"
    case wantsAbstainedYear = "wants.abstainedYear"
    case wantsAdd = "wants.add"
    case wantsName = "wants.name"
    case wantsPrice = "wants.price"
    case wantsCooling = "wants.cooling"
    case wantsReady = "wants.ready"
    case wantsBuy = "wants.buy"
    case wantsAbstain = "wants.abstain"
    case wantsEmpty = "wants.empty"
    case wantsEmptyHint = "wants.emptyHint"
    case wantsBought = "wants.bought"
    case wantsAbstained = "wants.abstained"
    case wantsUnlocked = "wants.unlocked"
    case wantsHolding = "wants.holding"
    case wantsArchive = "wants.archive"
    case wantsCoolingHours = "wants.coolingHours"
    case wantsCoolingCalc = "wants.coolingCalc"
    case wantsStale = "wants.stale"
    case wantsNotifyWeb = "wants.notifyWeb"
    case wantsAddTitle = "wants.addTitle"
    case wantsRemove = "wants.remove"
    case wantsRemoved = "wants.removed"
    case wantsEntered = "wants.entered"
    case wantsAbstainedDone = "wants.abstainedDone"
    case subsTitle = "subs.title"
    case subsAnnual = "subs.annual"
    case subsRow = "subs.row"
    case subsPaid = "subs.paid"
    case subsNext = "subs.next"
    case subsPerUse = "subs.perUse"
    case subsLogUse = "subs.logUse"
    case subsUnclaimed = "subs.unclaimed"
    case subsKeep = "subs.keep"
    case subsCancel = "subs.cancel"
    case subsCancelled = "subs.cancelled"
    case subsSaved = "subs.saved"
    case subsDetected = "subs.detected"
    case subsEmpty = "subs.empty"
    case subsAnnualLabel = "subs.annualLabel"
    case subsPerDay = "subs.perDay"
    case subsAmountPer = "subs.amountPer"
    case subsPeriodWeek = "subs.period.week"
    case subsPeriodMonth = "subs.period.month"
    case subsPeriodQuarter = "subs.period.quarter"
    case subsPeriodYear = "subs.period.year"
    case subsActive = "subs.active"
    case subsEmptyActive = "subs.emptyActive"
    case subsUnclaimedCount = "subs.unclaimedCount"
    case subsUnclaimedRow = "subs.unclaimedRow"
    case subsPending = "subs.pending"
    case subsMarkEnded = "subs.markEnded"
    case subsEndedRow = "subs.endedRow"
    case reckoningTitle = "reckoning.title"
    case reckoningPrompt = "reckoning.prompt"
    case reckoningWorth = "reckoning.worth"
    case reckoningNotWorth = "reckoning.notWorth"
    case reckoningLater = "reckoning.later"
    case reckoningProgress = "reckoning.progress"
    case reckoningDaysAgo = "reckoning.daysAgo"
    case reckoningDone = "reckoning.done"
    case reckoningEmpty = "reckoning.empty"
    case reckoningLastChance = "reckoning.lastChance"
    case reckoningCardOf = "reckoning.cardOf"
    case reckoningQuote = "reckoning.quote"
    case reckoningLaterCount = "reckoning.laterCount"
    case reckoningAutoStatement = "reckoning.autoStatement"
    case reckoningNext = "reckoning.next"
    case reckoningSkip = "reckoning.skip"
    case reckoningCarryover = "reckoning.carryover"
    case reckoningError = "reckoning.error"
    case reckoningDoneSummary = "reckoning.doneSummary"
    case reckoningDoneNotWorth = "reckoning.doneNotWorth"
    case reckoningDoneNote = "reckoning.doneNote"
    case standardTitle = "standard.title"
    case standardMonthly = "standard.monthly"
    case standardPerCategory = "standard.perCategory"
    case standardPropose = "standard.propose"
    case standardAccept = "standard.accept"
    case standardRevisions = "standard.revisions"
    case standardRevised = "standard.revised"
    case standardReason = "standard.reason"
    case settingsTitle = "settings.title"
    case settingsThresholds = "settings.thresholds"
    case settingsLeakCeiling = "settings.leakCeiling"
    case settingsLeakCeilingHint = "settings.leakCeilingHint"
    case settingsCoolingFloor = "settings.coolingFloor"
    case settingsCoolingFloorHint = "settings.coolingFloorHint"
    case settingsReckoningDay = "settings.reckoningDay"
    case settingsWishObject = "settings.wishObject"
    case settingsWishObjectHint = "settings.wishObjectHint"
    case settingsAppearance = "settings.appearance"
    case settingsThemeSystem = "settings.theme.system"
    case settingsThemeLight = "settings.theme.light"
    case settingsThemeDark = "settings.theme.dark"
    case settingsLanguage = "settings.language"
    case settingsExport = "settings.export"
    case settingsImport = "settings.import"
    case settingsImported = "settings.imported"
    case settingsCategories = "settings.categories"
    case settingsAbout = "settings.about"
    case syncTitle = "sync.title"
    case syncOff = "sync.off"
    case syncOffHint = "sync.offHint"
    case syncIdle = "sync.idle"
    case syncSyncing = "sync.syncing"
    case syncPending = "sync.pending"
    case syncOffline = "sync.offline"
    case syncError = "sync.error"
    case syncRetry = "sync.retry"
    case syncNow = "sync.now"
    case syncChoose = "sync.choose"
    case syncGithub = "sync.github"
    case syncGithubHint = "sync.githubHint"
    case syncServer = "sync.server"
    case syncServerHint = "sync.serverHint"
    case syncRepo = "sync.repo"
    case syncToken = "sync.token"
    case syncTokenHelp = "sync.tokenHelp"
    case syncPassphrase = "sync.passphrase"
    case syncPassphraseHint = "sync.passphraseHint"
    case syncPassphraseAgain = "sync.passphraseAgain"
    case syncPassphraseMismatch = "sync.passphraseMismatch"
    case syncFingerprint = "sync.fingerprint"
    case syncFingerprintHint = "sync.fingerprintHint"
    case syncWrongPassphrase = "sync.wrongPassphrase"
    case syncConnect = "sync.connect"
    case syncDisconnect = "sync.disconnect"
    case syncDisconnectHint = "sync.disconnectHint"
    case syncDevices = "sync.devices"
    case syncThisDevice = "sync.thisDevice"
    case syncRevoke = "sync.revoke"
    case syncLastSeen = "sync.lastSeen"
    case syncEmail = "sync.email"
    case syncPassword = "sync.password"
    case syncCode = "sync.code"
    case syncLogin = "sync.login"
    case syncSignup = "sync.signup"
    case syncServerUrl = "sync.serverUrl"
    case syncServerKeyHint = "sync.serverKeyHint"
    case standardPerMonth = "standard.perMonth"
    case standardPerEntry = "standard.perEntry"
    case standardUnset = "standard.unset"
    case standardEmpty = "standard.empty"
    case standardSuggest = "standard.suggest"
    case standardProposeGate = "standard.proposeGate"
    case standardAlloc = "standard.alloc"
    case standardAllocOver = "standard.allocOver"
    case standardSave = "standard.save"
    case standardSaved = "standard.saved"
    case standardReasonThreshold = "standard.reasonThreshold"
    case standardRevisionsEmpty = "standard.revisionsEmpty"
    case settingsReckoningHour = "settings.reckoningHour"
    case settingsYuan = "settings.yuan"
    case settingsWishName = "settings.wishName"
    case settingsWishPrice = "settings.wishPrice"
    case settingsCategoryName = "settings.categoryName"
    case settingsCategoryAdd = "settings.categoryAdd"
    case settingsCategoryArchive = "settings.categoryArchive"
    case settingsCategoryRestore = "settings.categoryRestore"
    case settingsData = "settings.data"
    case settingsExportHint = "settings.exportHint"
    case settingsImportInvalid = "settings.importInvalid"
    case settingsImportSummary = "settings.importSummary"
    case settingsVersion = "settings.version"
    case syncSynced = "sync.synced"
    case syncOwner = "sync.owner"
    case syncBranch = "sync.branch"
    case syncConnecting = "sync.connecting"
    case syncLocked = "sync.locked"
    case syncUnlock = "sync.unlock"
    case syncOffNote = "sync.offNote"
    case syncPassphraseShort = "sync.passphraseShort"
    case syncCopied = "sync.copied"
    case syncRevokeConfirm = "sync.revokeConfirm"
    // SCREENS.md Y8 gives the sync state as one word; `sync.offline` and
    // `sync.error` carry a clause and a message, which a header word cannot.
    case syncStateOffline = "sync.state.offline"
    case syncStateError = "sync.state.error"
    case settingsExportFailed = "settings.exportFailed"
    case commonCancel = "common.cancel"
    case commonDone = "common.done"
    case commonSave = "common.save"
    case commonDelete = "common.delete"
    case commonBack = "common.back"
    case commonMore = "common.more"
    case commonToday = "common.today"
    case commonYesterday = "common.yesterday"
    case commonLoading = "common.loading"
    case commonRetry = "common.retry"
    case commonClose = "common.close"
    case commonConfirm = "common.confirm"
    case commonIncrease = "common.increase"
    case commonDecrease = "common.decrease"
}

enum S {
    /// Mirrors the folded ledger's locale. The store writes it whenever the
    /// setting changes, so every call site can stay a plain `S.t(.key)` instead
    /// of threading a locale through the whole view tree.
    @MainActor static var locale: Settings.Locale = DEFAULT_SETTINGS.locale

    @MainActor
    static func t(_ key: StringKey, _ vars: [String: any CustomStringConvertible] = [:]) -> String {
        translate(locale, key, vars)
    }

    static func translate(
        _ locale: Settings.Locale, _ key: StringKey,
        _ vars: [String: any CustomStringConvertible] = [:]
    ) -> String {
        let pair = table(key)
        var s = locale == .en ? pair.en : pair.zh
        for (name, value) in vars {
            s = s.replacingOccurrences(of: "{\(name)}", with: String(describing: value))
        }
        return s
    }

    static func weekdays(_ locale: Settings.Locale) -> [String] {
        locale == .en
            ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            : ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    }

    /// 0 = Sunday, the convention `weekdayOf` and `Rules.reckoningWeekday` use.
    @MainActor static func weekday(_ index: Int) -> String {
        let names = weekdays(locale)
        return names[((index % names.count) + names.count) % names.count]
    }

    // A switch rather than a dictionary literal: the compiler checks it is
    // exhaustive, and it costs no allocation at launch.
    private static func table(_ key: StringKey) -> (zh: String, en: String) {
        switch key {
        case .appName: return ("据实", "Countbook")
        case .appTagline: return ("记账，不评判", "A ledger that does not editorialise")
        case .tabToday: return ("今日", "Today")
        case .tabLedger: return ("账页", "Ledger")
        case .tabReport: return ("报告", "Report")
        case .tabWants: return ("待购", "Wants")
        case .tabSettings: return ("设置", "Settings")
        case .tabNav: return ("主导航", "Main navigation")
        case .todayAvailable: return ("今日可用", "Available today")
        case .todayProvenance: return ("标准 {standard} · 已花 {spent} · 待扣 {fixed} · 余 {days} 天", "Standard {standard} · spent {spent} · committed {fixed} · {days} days left")
        case .todayRecovery: return ("按现在的速度，{days} 天不花钱回到轨道", "{days} clean days returns you to the line")
        case .todayNoStandard: return ("先设一条标准线", "Set your standard first")
        case .todaySetStandard: return ("设置月度标准", "Set a monthly standard")
        case .todayStreak: return ("连续 {n} 天没超标", "{n} days under the line")
        case .todayNospend: return ("今天没花钱", "Nothing spent today")
        case .todayNospendDone: return ("已记：今天没花钱", "Recorded: nothing spent today")
        case .todayLeak: return ("本月 {count} 笔小额 · {sum} · ≈ {times} 次大额支出", "{count} small charges · {sum} · ≈ {times} large purchases")
        case .todayLeakBare: return ("本月 {count} 笔小额 · {sum}", "{count} small charges · {sum}")
        case .todayNoStandardHint: return ("月度标准在设置里设定", "The monthly standard is set in Settings")
        case .todayDetailStandard: return ("月度标准", "Monthly standard")
        case .todayDetailSpent: return ("本月已花", "Spent this month")
        case .todayDetailFixed: return ("固定待扣", "Committed this month")
        case .todayDetailDays: return ("余下天数", "Days remaining")
        case .todayDaysValue: return ("{n} 天", "{n} days")
        case .todayStripTitle: return ("{month} · 日支出", "{month} · daily spend")
        case .todayStripGate: return ("本月还需 {n} 天数据", "{n} more days of data this month")
        case .todayVerdict: return ("本周 {n} 笔待判", "{n} entries to judge this week")
        case .todayEmptyToday: return ("今天还没有记录", "Nothing recorded today")
        case .todayEmptyMonth: return ("本月还没有记录", "Nothing recorded this month")
        case .todayStampNeed: return ("必", "N")
        case .todayStampWant: return ("想", "W")
        case .todayStampImpulse: return ("冲", "I")
        case .captureTitle: return ("记一笔", "New entry")
        case .captureSpend: return ("支出", "Spend")
        case .captureIncome: return ("收入", "Income")
        case .captureSave: return ("存入账页", "Enter")
        case .captureSaveWarned: return ("存入账页 · {warning}", "Enter · {warning}")
        case .captureHold: return ("按住存入", "Hold to enter")
        case .captureHoldHint: return ("这笔不小，按住三秒", "Not a small one — hold for three seconds")
        case .captureSuspend: return ("挂起 {days} 天", "Hold {days} days")
        case .captureSuspendHint: return ("放进待购，冷静 {days} 天再决定", "To the want list; decide in {days} days")
        case .captureIntent: return ("这笔是", "This was")
        case .captureIntentNeed: return ("必要", "Needed")
        case .captureIntentWant: return ("想要", "Wanted")
        case .captureIntentImpulse: return ("冲动", "Impulse")
        case .captureIntentRequired: return ("先选一个", "Choose one first")
        case .captureNote: return ("备注", "Note")
        case .captureMerchant: return ("商家", "Payee")
        case .capturePromise: return ("一句话，写给三天后的自己", "One line, to yourself in three days")
        case .captureCategory: return ("分类", "Category")
        case .captureDate: return ("日期", "Date")
        case .captureCancel: return ("取消", "Cancel")
        case .captureSaved: return ("已存入", "Entered")
        case .captureKeepOpen: return ("继续记", "Keep going")
        case .captureMark: return ("记", "Log")
        case .captureAmount: return ("金额", "Amount")
        case .captureNeedAmount: return ("先输入金额", "Enter an amount first")
        case .captureNeedCategory: return ("先选一个分类", "Choose a category first")
        case .captureConsequence: return ("记入后 今日可用", "After this, available today")
        case .captureKeypad: return ("金额键盘", "Amount keypad")
        case .captureDecimal: return ("小数点", "Decimal point")
        case .captureBackspace: return ("退格", "Backspace")
        case .captureDayBefore: return ("前天", "Day before yesterday")
        case .capturePickDate: return ("选择日期", "Pick a date")
        case .captureCoolingTier: return ("冷静期 {days} 天", "Cooling period {days} days")
        case .captureHoldPrimary: return ("挂起 {days} 天 · 到 {date}", "Hold {days} days · until {date}")
        case .captureHoldOverride: return ("仍要立即记入", "Enter it now anyway")
        case .captureOverrideWarned: return ("仍要立即记入 · {warning}", "Enter it now anyway · {warning}")
        case .captureSuspended: return ("已挂起", "Held")
        case .captureOptional: return ("备注 · 商家", "Note · Payee")
        case .ledgerTitle: return ("账页", "Ledger")
        case .ledgerMonth: return ("{month}", "{month}")
        case .ledgerSealed: return ("结", "Closed")
        case .ledgerOpen: return ("未结", "Open")
        case .ledgerTotal: return ("合计", "Total")
        case .ledgerSearch: return ("搜索备注、商家、金额", "Search notes, payees, amounts")
        case .ledgerEmpty: return ("这个月还没有记录", "Nothing recorded this month")
        case .ledgerEmptyHint: return ("右下角开始第一笔", "Start with the button below")
        case .ledgerCorrection: return ("更正 · 原 {from} → {to} · 事由：{reason}", "Correction · was {from} → {to} · {reason}")
        case .ledgerVoided: return ("冲销 · 事由：{reason}", "Reversed · {reason}")
        case .ledgerCorrect: return ("更正", "Correct")
        case .ledgerVoid: return ("冲销", "Reverse")
        case .ledgerDelete: return ("删除", "Delete")
        case .ledgerEdit: return ("修改", "Edit")
        case .ledgerUndo: return ("撤销", "Undo")
        case .ledgerDeleted: return ("已删除", "Deleted")
        case .ledgerReasonRequired: return ("写一句事由", "Give a reason")
        case .ledgerSealedNote: return ("这个月已结账，改动会另起一行", "This month is closed; a change is printed as a new line")
        case .ledgerMonthTitle: return ("{year} 年 {month} 月", "{year}-{month}")
        case .ledgerPrevMonth: return ("上一月", "Previous month")
        case .ledgerNextMonth: return ("下一月", "Next month")
        case .ledgerStandard: return ("标准 {amount}", "Standard {amount}")
        case .ledgerSearchClear: return ("清除搜索", "Clear search")
        case .ledgerSearchSyntax: return ("可用 >100 · <30 · =68 按金额筛选", "Use >100 · <30 · =68 to filter by amount")
        case .ledgerFilters: return ("筛选", "Filters")
        case .ledgerFilterAll: return ("全部", "All")
        case .ledgerFilterLeak: return ("小额", "Small")
        case .ledgerFilterCorrected: return ("有更正", "Corrected")
        case .ledgerFilterUnreviewed: return ("未判", "Unjudged")
        case .ledgerFilterNotWorth: return ("不值", "Not worth it")
        case .ledgerDayHeader: return ("{date} · {weekday}", "{date} · {weekday}")
        case .ledgerDayOver: return ("当日高于日标准", "Over the daily standard")
        case .ledgerGlyphNeed: return ("必", "N")
        case .ledgerGlyphWant: return ("想", "W")
        case .ledgerGlyphImpulse: return ("冲", "I")
        case .ledgerEmptySearch: return ("没有匹配的条目。", "No matching entries.")
        case .ledgerEmptySearchClear: return ("清除筛选", "Clear filters")
        case .ledgerEmptyBefore: return ("{date} 之前没有记录。", "No records before {date}.")
        case .entryTitle: return ("这一笔", "Entry")
        case .entryAmountLabel: return ("金额", "Amount")
        case .entryStamp: return ("印章", "Stamp")
        case .entryPromiseTitle: return ("写给三天后的自己", "To yourself in three days")
        case .entryVerdict: return ("周日审判", "Sunday verdict")
        case .entryWorth: return ("值", "Worth it")
        case .entryNotWorth: return ("不值", "Not worth it")
        case .entryPending: return ("待判", "Not yet judged")
        case .entrySave: return ("保存修改", "Save changes")
        case .entryDelete: return ("删除这笔", "Delete this entry")
        case .entryCorrectAmount: return ("更正为", "Correct to")
        case .entryReasonLabel: return ("事由", "Reason")
        case .entryCorrectSubmit: return ("追加更正", "Append correction")
        case .entryVoid: return ("冲销这笔", "Void this entry")
        case .entryVoidReason: return ("冲销事由", "Reason for voiding")
        case .entryHistory: return ("修改历史", "Change history")
        case .entryClosedDate: return ("不能改到已结账的月份。", "Cannot move it into a closed month.")
        case .reportTitle: return ("报告", "Report")
        case .reportRegretMonth: return ("本月后悔", "Regret this month")
        case .reportRegretYear: return ("本年后悔", "Regret this year")
        case .reportRegretRate: return ("已判 {judged} · 不值 {notWorth} · {rate}", "Judged {judged} · not worth {notWorth} · {rate}")
        case .reportRegretPending: return ("还需 {n} 笔判定才有意义", "{n} more verdicts before this means anything")
        case .reportWishFraction: return ("已经买得起 {name} 的 {percent}", "Enough for {percent} of {name}")
        case .reportDeviation: return ("与标准的偏差", "Deviation from standard")
        case .reportUnder: return ("低于标准", "Under")
        case .reportOver: return ("高于标准", "Over")
        case .reportByCategory: return ("分类", "By category")
        case .reportHours: return ("记账时刻", "When you log")
        case .reportHoursNote: return ("深夜下单会在这里显形", "Late-night ordering shows up here")
        case .reportYear: return ("年账页", "Year")
        case .reportNeedMoreData: return ("数据还不够 · 还差 {n} 笔", "Not enough data yet · {n} to go")
        case .reportMonthTitle: return ("{year} 年 {month} 月", "{year}-{month}")
        case .reportPrevMonth: return ("上一月", "Previous month")
        case .reportNextMonth: return ("下一月", "Next month")
        case .reportEmpty: return ("记满 14 天，这一页才会有话可说。", "This page has nothing to say until 14 days are recorded.")
        case .reportNoStandard: return ("还没有标准可以对照。", "No standard to compare against.")
        case .reportDeviationGate: return ("本月还需 {n} 天数据。", "{n} more days of data this month.")
        case .reportRate: return ("后悔率", "Regret rate")
        case .reportTableCategory: return ("类目", "Category")
        case .reportTableCount: return ("笔数", "Entries")
        case .reportTableMedian: return ("中位数", "Median")
        case .reportTableMax: return ("最大一笔", "Largest")
        case .reportTableRegret: return ("后悔金额", "Regret")
        case .reportTableEmpty: return ("这个月还没有记录。", "Nothing recorded this month.")
        case .reportHourGate: return ("需要再记 {n} 笔。", "{n} more entries needed.")
        case .reportHourLate: return ("{hh}:00 后 {n} 笔 · {sum}", "{n} entries after {hh}:00 · {sum}")
        case .chartStrip: return ("{month} 日支出 · 日标准 {standard} · 最高 {max}", "{month} daily spend · standard {standard} a day · highest {max}")
        case .chartStripDay: return ("{date} · {amount}", "{date} · {amount}")
        case .chartStripScrub: return ("按日读取", "Read by day")
        case .chartStandardPerDay: return ("{amount}/日", "{amount}/day")
        case .chartDeviation: return ("与标准的偏差 · {n} 个类目 · 最大 {max}", "Deviation from standard · {n} categories · largest {max}")
        case .chartYear: return ("年账页 · {n} 个月 · 最大偏差 {max}", "Year ledger · {n} months · largest deviation {max}")
        case .chartRegretGate: return ("需要再判 {n} 笔才能给出后悔率。", "{n} more judged entries before a regret rate.")
        case .chartRegretBlock: return ("已判 {judged} · 不值 {notWorth} · {rate}", "{judged} judged · {notWorth} not worth it · {rate}")
        case .chartAnnual: return ("年化 {amount}", "{amount} a year")
        case .chartAnnualRow: return ("{name} · {amount}/年", "{name} · {amount}/yr")
        case .chartAnnualOther: return ("其他", "Other")
        case .chartHour: return ("记账时刻 · 共 {n} 笔", "When you log · {n} entries")
        case .chartHourPeak: return ("{hour}:00 最多 {n} 笔", "Busiest {hour}:00 · {n} entries")
        case .chartHourMore: return ("+{n}", "+{n}")
        case .chartColDay: return ("日期", "Date")
        case .chartColHour: return ("时刻", "Hour")
        case .chartColCount: return ("笔数", "Entries")
        case .chartColAmount: return ("金额", "Amount")
        case .chartEmpty: return ("没有可画的数据", "Nothing to draw yet")
        case .wantsTitle: return ("待购", "Wants")
        case .wantsAbstainedYear: return ("本年已放弃", "Given up this year")
        case .wantsAdd: return ("加一件", "Add one")
        case .wantsName: return ("想买什么", "What is it")
        case .wantsPrice: return ("多少钱", "How much")
        case .wantsCooling: return ("还有 {days} 天 {time}", "{days}d {time} left")
        case .wantsReady: return ("仍然想要吗？", "Still want it?")
        case .wantsBuy: return ("记入账页", "Buy it")
        case .wantsAbstain: return ("不买了", "Let it go")
        case .wantsEmpty: return ("没有待购的东西", "Nothing on hold")
        case .wantsEmptyHint: return ("下次想买什么，先放进来", "Put the next thing here first")
        case .wantsBought: return ("已买", "Bought")
        case .wantsAbstained: return ("已放弃", "Given up")
        case .wantsUnlocked: return ("可以决定了", "Ready to decide")
        case .wantsHolding: return ("冷静中", "Cooling")
        case .wantsArchive: return ("已放弃 {year}", "Given up in {year}")
        case .wantsCoolingHours: return ("还有 {time}", "{time} left")
        case .wantsCoolingCalc: return ("冷静期 {days} 天 · 到 {date}", "Cooling {days} days · until {date}")
        case .wantsStale: return ("已解锁 {n} 天", "Unlocked {n} days")
        case .wantsNotifyWeb: return ("网页版不发通知，下次打开时会提示", "The web version sends no notifications; it tells you on your next visit")
        case .wantsAddTitle: return ("加入待购", "Add to the want list")
        case .wantsRemove: return ("移出待购", "Take it off")
        case .wantsRemoved: return ("已移出待购", "Taken off the want list")
        case .wantsEntered: return ("已记入账页", "Entered in the ledger")
        case .wantsAbstainedDone: return ("已记：不买了", "Recorded: let go")
        case .subsTitle: return ("订阅", "Subscriptions")
        case .subsAnnual: return ("年化 {annual} · 每天 {perDay}", "{annual} a year · {perDay} a day")
        case .subsRow: return ("{period} {amount} · 年化 {annual}", "{amount}/{period} · {annual} a year")
        case .subsPaid: return ("已付 {paid}（自 {since}）", "Paid {paid} since {since}")
        case .subsNext: return ("下次 {day}", "Next {day}")
        case .subsPerUse: return ("每次使用 {amount}", "{amount} per use")
        case .subsLogUse: return ("用过一次", "Used it")
        case .subsUnclaimed: return ("待确认", "Unclaimed")
        case .subsKeep: return ("保留", "Keep")
        case .subsCancel: return ("待退订", "Cancel it")
        case .subsCancelled: return ("已终止", "Ended")
        case .subsSaved: return ("已省 {amount}", "Saved {amount}")
        case .subsDetected: return ("发现 {n} 笔可能是订阅", "Found {n} charges that keep coming back")
        case .subsEmpty: return ("没有订阅", "No subscriptions")
        case .subsAnnualLabel: return ("年化", "A year")
        case .subsPerDay: return ("每天 {amount}", "{amount} a day")
        case .subsAmountPer: return ("{period} {amount}", "{amount} {period}")
        case .subsPeriodWeek: return ("周付", "weekly")
        case .subsPeriodMonth: return ("月付", "monthly")
        case .subsPeriodQuarter: return ("季付", "quarterly")
        case .subsPeriodYear: return ("年付", "yearly")
        case .subsActive: return ("在用", "Active")
        case .subsEmptyActive: return ("还没有确认的订阅", "Nothing confirmed yet")
        case .subsUnclaimedCount: return ("待确认 {n}", "{n} unclaimed")
        case .subsUnclaimedRow: return ("{period} {amount} · 已出现 {n} 次", "{amount} {period} · seen {n} times")
        case .subsPending: return ("待退订", "Cancelling")
        case .subsMarkEnded: return ("标记已终止", "Mark ended")
        case .subsEndedRow: return ("{month} 终止 · 已省 {amount}", "Ended {month} · saved {amount}")
        case .reckoningTitle: return ("周日审判", "Sunday reckoning")
        case .reckoningPrompt: return ("这笔花得值吗？", "Was it worth it?")
        case .reckoningWorth: return ("值", "Worth it")
        case .reckoningNotWorth: return ("不值", "Not worth it")
        case .reckoningLater: return ("稍后", "Later")
        case .reckoningProgress: return ("{done} / {total}", "{done} / {total}")
        case .reckoningDaysAgo: return ("{n} 天前", "{n} days ago")
        case .reckoningDone: return ("本周判完了", "Done for this week")
        case .reckoningEmpty: return ("没有要判的", "Nothing to judge")
        case .reckoningLastChance: return ("第 {n} 次推迟，再推就记作不值", "Deferral {n} — the next one records 不值")
        case .reckoningCardOf: return ("第 {i} 张，共 {n} 张", "Card {i} of {n}")
        case .reckoningQuote: return ("你当时写：", "You wrote:")
        case .reckoningLaterCount: return ("稍后 ({n}/3)", "Later ({n}/3)")
        case .reckoningAutoStatement: return ("这笔已经推迟 3 次，记为不值。", "Deferred three times. Recorded as not worth it.")
        case .reckoningNext: return ("下一张", "Next card")
        case .reckoningSkip: return ("跳过", "Skip")
        case .reckoningCarryover: return ("含上周 {n} 笔", "Includes {n} from last week")
        case .reckoningError: return ("判决没能保存。再点一次。", "The verdict did not save. Tap again.")
        case .reckoningDoneSummary: return ("本周 {n} 笔待判", "{n} entries to judge this week")
        case .reckoningDoneNotWorth: return ("{n} 笔不值", "{n} not worth it")
        case .reckoningDoneNote: return ("已记入本年后悔。", "Written into this year's regret.")
        case .standardTitle: return ("标准线", "Standard")
        case .standardMonthly: return ("月度标准", "Monthly standard")
        case .standardPerCategory: return ("分类标准", "Per category")
        case .standardPropose: return ("近 90 天中位数 {amount}", "90-day median {amount}")
        case .standardAccept: return ("采用", "Use it")
        case .standardRevisions: return ("修订记录", "Revisions")
        case .standardRevised: return ("{date} · {amount}{reason}", "{date} · {amount}{reason}")
        case .standardReason: return ("事由（可留空）", "Reason (optional)")
        case .settingsTitle: return ("设置", "Settings")
        case .settingsThresholds: return ("阈值", "Thresholds")
        case .settingsLeakCeiling: return ("小额上限", "Small-charge ceiling")
        case .settingsLeakCeilingHint: return ("低于这个数的支出会被合并成一条“漏水”", "Charges under this are counted as a class")
        case .settingsCoolingFloor: return ("冷静期起点", "Cooling threshold")
        case .settingsCoolingFloorHint: return ("高于这个数，记一笔时会先问要不要挂起", "Above this, the app offers to hold it first")
        case .settingsReckoningDay: return ("审判日", "Reckoning day")
        case .settingsWishObject: return ("心愿物", "Wish object")
        case .settingsWishObjectHint: return ("用它来换算后悔的钱", "The exchange rate for regret")
        case .settingsAppearance: return ("外观", "Appearance")
        case .settingsThemeSystem: return ("跟随系统", "System")
        case .settingsThemeLight: return ("浅色", "Light")
        case .settingsThemeDark: return ("深色", "Dark")
        case .settingsLanguage: return ("语言", "Language")
        case .settingsExport: return ("导出全部数据", "Export everything")
        case .settingsImport: return ("导入备份", "Import a backup")
        case .settingsImported: return ("已导入 {n} 条", "Imported {n} records")
        case .settingsCategories: return ("分类", "Categories")
        case .settingsAbout: return ("关于", "About")
        case .syncTitle: return ("多端同步", "Sync")
        case .syncOff: return ("未开启", "Off")
        case .syncOffHint: return ("数据只在这台设备上", "Everything stays on this device")
        case .syncIdle: return ("已同步 · {time}", "Synced · {time}")
        case .syncSyncing: return ("同步中…", "Syncing…")
        case .syncPending: return ("{n} 条待同步", "{n} waiting")
        case .syncOffline: return ("离线 · 稍后自动重试", "Offline · will retry")
        case .syncError: return ("同步失败 · {message}", "Sync failed · {message}")
        case .syncRetry: return ("重试", "Retry")
        case .syncNow: return ("立即同步", "Sync now")
        case .syncChoose: return ("选择同步方式", "How to sync")
        case .syncGithub: return ("GitHub 私有仓库", "Private GitHub repo")
        case .syncGithubHint: return ("不需要服务器，用一个私有仓库存加密数据", "No server needed — an encrypted blob in a private repo")
        case .syncServer: return ("自建服务器", "Your own server")
        case .syncServerHint: return ("自己部署的同步服务", "A sync service you deployed")
        case .syncRepo: return ("仓库", "Repository")
        case .syncToken: return ("访问令牌", "Access token")
        case .syncTokenHelp: return ("去 GitHub 生成一个", "Generate one on GitHub")
        case .syncPassphrase: return ("加密口令", "Passphrase")
        case .syncPassphraseHint: return ("口令不会离开这台设备。忘了就打不开了。", "The passphrase never leaves this device. Lose it and the vault stays shut.")
        case .syncPassphraseAgain: return ("再输一次", "Once more")
        case .syncPassphraseMismatch: return ("两次输入不一样", "Those do not match")
        case .syncFingerprint: return ("密钥指纹", "Key fingerprint")
        case .syncFingerprintHint: return ("所有设备应显示同一串", "Every device should show the same")
        case .syncWrongPassphrase: return ("口令打不开这个仓库", "That passphrase does not open this vault")
        case .syncConnect: return ("连接", "Connect")
        case .syncDisconnect: return ("断开", "Disconnect")
        case .syncDisconnectHint: return ("本机数据保留，不再上传", "Local data stays; nothing more is uploaded")
        case .syncDevices: return ("设备", "Devices")
        case .syncThisDevice: return ("本机", "This device")
        case .syncRevoke: return ("注销", "Revoke")
        case .syncLastSeen: return ("最近 {time}", "Last seen {time}")
        case .syncEmail: return ("邮箱", "Email")
        case .syncPassword: return ("密码", "Password")
        case .syncCode: return ("注册码", "Signup code")
        case .syncLogin: return ("登录", "Log in")
        case .syncSignup: return ("注册", "Sign up")
        case .syncServerUrl: return ("服务器地址", "Server address")
        case .syncServerKeyHint: return ("同一个密码用来登录，也用来给数据加密。密码不会被保存，只在这台设备上派生出密钥。", "The one password both logs you in and encrypts your data. It is never stored; the key is derived on this device.")
        case .standardPerMonth: return ("每月", "a month")
        case .standardPerEntry: return ("每月", "a month")
        case .standardUnset: return ("未设", "Not set")
        case .standardEmpty: return ("还没有标准线。所有偏差报告都以它为基准。", "No standard yet. Every deviation is measured against it.")
        case .standardSuggest: return ("近 90 天中位数 {amount}", "90-day median {amount}")
        case .standardProposeGate: return ("还需 {n} 天数据才能给出建议", "{n} more days of data before a proposal")
        case .standardAlloc: return ("分类合计 {a} · 月度标准 {b}", "Categories {a} · standard {b}")
        case .standardAllocOver: return ("分类合计 {a}，已超出月度标准 {b}", "Categories total {a}, over the standard {b}")
        case .standardSave: return ("保存标准线", "Save the standard")
        case .standardSaved: return ("已保存，并记入修订记录", "Saved, and written to the revision record")
        case .standardReasonThreshold: return ("改动超过 20%，写一句事由", "A change over 20% needs a reason")
        case .standardRevisionsEmpty: return ("还没有修订", "No revisions yet")
        case .settingsReckoningHour: return ("时刻", "Hour")
        case .settingsYuan: return ("元", "yuan")
        case .settingsWishName: return ("名称", "Name")
        case .settingsWishPrice: return ("价格", "Price")
        case .settingsCategoryName: return ("分类名称", "Category name")
        case .settingsCategoryAdd: return ("新增分类", "Add a category")
        case .settingsCategoryArchive: return ("归档", "Archive")
        case .settingsCategoryRestore: return ("恢复", "Restore")
        case .settingsData: return ("数据", "Data")
        case .settingsExportHint: return ("{n} 条记录。导出的是完整事件日志，可以原样导回。", "{n} records. The export is the complete event log and imports back as it stands.")
        case .settingsImportInvalid: return ("这个文件不是本应用的备份", "That file is not a backup from this app")
        case .settingsImportSummary: return ("导入 {n} 条，跳过重复 {skip} 条", "Imported {n}, skipped {skip} duplicates")
        case .settingsVersion: return ("版本 {version}", "Version {version}")
        case .syncSynced: return ("已同步", "Synced")
        case .syncOwner: return ("账号", "Owner")
        case .syncBranch: return ("分支", "Branch")
        case .syncConnecting: return ("连接中…", "Connecting…")
        case .syncLocked: return ("已连接，但还没解锁。输入口令继续。", "Connected but locked. Enter the passphrase to continue.")
        case .syncUnlock: return ("解锁", "Unlock")
        case .syncOffNote: return ("数据只在这台设备上。开启同步后，其他设备可以看到同一本账。", "Everything is on this device. Turn on sync and your other devices see the same ledger.")
        case .syncPassphraseShort: return ("口令至少 8 个字符", "At least 8 characters")
        case .syncCopied: return ("已复制", "Copied")
        case .syncRevokeConfirm: return ("注销这台设备？它需要重新登录。", "Revoke this device? It will have to log in again.")
        case .syncStateOffline: return ("离线", "Offline")
        case .syncStateError: return ("同步出错", "Sync error")
        case .settingsExportFailed: return ("这次导出没能写出文件。", "The export could not be written.")
        case .commonCancel: return ("取消", "Cancel")
        case .commonDone: return ("完成", "Done")
        case .commonSave: return ("保存", "Save")
        case .commonDelete: return ("删除", "Delete")
        case .commonBack: return ("返回", "Back")
        case .commonMore: return ("更多", "More")
        case .commonToday: return ("今天", "Today")
        case .commonYesterday: return ("昨天", "Yesterday")
        case .commonLoading: return ("载入中", "Loading")
        case .commonRetry: return ("重试", "Retry")
        case .commonClose: return ("关闭", "Close")
        case .commonConfirm: return ("确定", "Confirm")
        case .commonIncrease: return ("增加", "Increase")
        case .commonDecrease: return ("减少", "Decrease")
        }
    }
}
