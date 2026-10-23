// StatusEngine (SPEC §5.4): merges measured results with self-reports, applies the 90-day
// re-ask, pacing and the §6.4 account rollups, and computes the Home state and the Next step.
//
// Local evaluation is the only truth on the device (§8.4); the engine never reads anything back
// from a ResultSink. It is pure: same inputs and day, same snapshot.
//
// Rules the engine applies:
// - H7 no false green: a missing, expired or "Not sure" answer is `unknown`, never `pass`.
// - "Not sure" is written as `unknown` but shown amber ("To do"), with "That's okay. Ben can
//   help next visit." (§5.1, §6.3).
// - §6.3 "Not now" is `fail` (the person says it isn't done). A §6.4 step answered "Not now"
//   makes its rollup `fail` only after 14 days.
// - Home is "You're protected. Nothing to do." when nothing red or amber needs action in the
//   unlocked pace groups. Yellow and info items never count (firewall is advisory).
// - Before the first measurement of this launch (`measured: nil`), Home never says "protected":
//   with nothing else to do it is "Checking now", because the measured checks are not known yet
//   (H7: missing data is unknown, never pass).
// - Ben-only items are never shown to the relative; optional items never fail or sync.

import Foundation

/// One measured result from the platform checks (iOSChecks, MacChecks, VersionEvaluator).
public struct MeasuredResult: Sendable, Hashable, Codable {
    public var checkID: CheckID
    public var status: Status
    public var checkedOn: DateDay
    /// The context escalates the tier to the entry's `urgentTier` (red): an actively exploited
    /// bug with the fix out (`os_patched`), or port 5900 open with the CVE unpatched
    /// (`remote_access_off`). Ignored unless `status == .fail`.
    public var urgent: Bool

    public init(checkID: CheckID, status: Status, checkedOn: DateDay, urgent: Bool = false) {
        self.checkID = checkID
        self.status = status
        self.checkedOn = checkedOn
        self.urgent = urgent
    }
}

/// Identifies a row on Home: a check, or (pace group 3) one online-account service.
public enum StatusItemID: Hashable, Sendable {
    case check(CheckID)
    case service(ServiceKey)
}

/// One row the UI can show: status, tier and the copy keys to render it.
public struct StatusItem: Sendable, Hashable, Identifiable {
    public let id: StatusItemID
    /// The check, or for a service row the category rollup it feeds.
    public let checkID: CheckID
    public let service: ServiceKey?
    public let kind: CheckKind
    public let audience: Audience
    public let source: Source
    /// Local truth, as it would be written to the wire.
    public let status: Status
    /// The current (unexpired) self-report answer, if any.
    public let answer: SelfAnswer?
    /// The previous answer expired (90 days): ask again.
    public let needsReask: Bool
    /// The failing context is escalated (red copy).
    public let urgent: Bool
    /// The tier this item has when it is not done.
    public let tier: Tier
    /// Counts toward "N things to do" (red or amber, not done).
    public let needsAction: Bool
    /// The person chose "Not now"; sorted after other items of the same tier.
    public let deferred: Bool
    public let paceGroup: Int?
    /// The day of the measurement or answer.
    public let checkedOn: DateDay?

    public let titleKey: String
    public let whyKey: String
    /// The status line under the title (pass, fail, urgent, unknown, re-ask or "Not sure" copy).
    public let messageKey: String
    /// Steps for this OS major (one per screen).
    public let stepKeys: [String]
    public let noteKeys: [String]
    public let deepLink: DeepLink?
    public let supportURL: URL?
    /// H9: the main action is **Call Ben**.
    public let callBen: Bool
    public let answerStyle: AnswerStyle

    let sortKey: SortKey

    /// The status to pass to `StatusAppearance(status:tier:)`: anything that needs action is
    /// drawn as "To do" / "Today" (so "Not sure" shows amber, §6.3), everything else as is.
    public var appearanceStatus: Status { needsAction ? .fail : status }

    struct SortKey: Hashable, Comparable {
        var urgency: Int
        var rank: Int
        var paceGroup: Int
        var order: Int

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.urgency != rhs.urgency { return lhs.urgency > rhs.urgency }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.paceGroup != rhs.paceGroup { return lhs.paceGroup < rhs.paceGroup }
            return lhs.order < rhs.order
        }
    }
}

/// The Home screen state (§5.4, §10.1).
public enum HomeState: Sendable, Hashable {
    /// "You're protected. Nothing to do."
    case protected
    /// The measured checks have not run yet this launch and nothing else needs doing: "Checking
    /// this device now." Never green (H7).
    case checking
    /// "N thing(s) to do": one Next-step card, the rest collapsed as "N more for later".
    case toDo(next: StatusItem, later: [StatusItem])

    public var count: Int {
        switch self {
        case .protected, .checking: 0
        case .toDo(_, let later): 1 + later.count
        }
    }

    public var nextStep: StatusItem? {
        if case .toDo(let next, _) = self { return next }
        return nil
    }

    public var later: [StatusItem] {
        if case .toDo(_, let later) = self { return later }
        return []
    }

    /// The Next step is red ("Today").
    public var isToday: Bool { nextStep?.tier == .red }

    /// "You're protected. Nothing to do." / "1 thing to do" / "1 thing to do today."
    public var headline: String {
        switch self {
        case .protected: ShieldStrings.text("home.protected")
        case .checking: ShieldStrings.text("home.checking")
        case .toDo: ShieldStrings.plural(isToday ? "home.toDoToday" : "home.toDo", count: count)
        }
    }

    /// "2 more for later", or nil when there is nothing else.
    public var laterText: String? {
        later.isEmpty ? nil : ShieldStrings.plural("home.moreForLater", count: later.count)
    }

    /// The measured checks haven't finished yet (nothing may be called protected).
    public var isChecking: Bool { self == .checking }

    /// The Mac menu-bar word (§10.2): "Protected", "Checking", "1 to do" or "Today". Never "N of M".
    public var menuBarWord: String {
        switch self {
        case .protected: ShieldStrings.text("menubar.protected")
        case .checking: ShieldStrings.text("menubar.checking")
        case .toDo: isToday ? ShieldStrings.text("menubar.today") : ShieldStrings.plural("menubar.toDo", count: count)
        }
    }
}

/// One step of one service, for the service checklist screen.
public struct AccountStepProgress: Sendable, Hashable {
    public let step: AccountStep
    public let copyKey: String
    /// The one-sentence reason shown under the step.
    public let whyKey: String
    public let answer: SelfAnswer?
    public let needsReask: Bool
}

/// One picked service.
public struct ServiceProgress: Sendable, Hashable, Identifiable {
    public let service: OnlineService
    /// On screen now (Group 3 unlocked and introduced; §5.4 one per day).
    public let introduced: Bool
    /// Local status of this service (same rules as the rollup).
    public let status: Status
    public let steps: [AccountStepProgress]
    /// Linked §6.3 checks and their current answers.
    public let linkedAnswers: [CheckID: SelfAnswer]

    public var id: ServiceKey { service.key }
}

/// One §6.4 category and its synced rollup.
public struct AccountCategorySummary: Sendable, Hashable, Identifiable {
    public let category: AccountCategory
    /// nil for `credit` (no rollup).
    public let rollup: CheckID?
    public let status: Status
    public let services: [ServiceProgress]

    public var id: AccountCategory { category }
}

/// What this device would write for one check.
public struct SyncedStatus: Sendable, Hashable {
    public let checkID: CheckID
    public let status: Status
    public let source: Source
    public let checkedOn: DateDay
}

/// Everything the UI and sync need, computed for one day.
public struct StatusSnapshot: Sendable {
    public let today: DateDay
    public let platform: Platform
    public let catalogVersion: Int
    public let home: HomeState
    /// Red/amber items needing action, most urgent first (`home` is built from this).
    public let toDo: [StatusItem]
    /// Every family-visible item in an unlocked group, in catalog order.
    public let familyItems: [StatusItem]
    /// Failing yellow / info items (advisory, never counted).
    public let suggestions: [StatusItem]
    /// Ben-only measured items (`app_build_fresh`, `beta_catalog`, ...). Never shown to the relative.
    public let benOnly: [StatusItem]
    /// "Check yourself" links (`lockdown`, `adp`, ...). Never fail.
    public let optionalLinks: [StatusItem]
    /// §6.4 categories with their picked services.
    public let accounts: [AccountCategorySummary]
    /// The day-60 TestFlight banner (§6.1 `app_build_fresh` failing).
    public let showBuildAgeBanner: Bool
    public let unlockedGroups: Set<Int>
    /// When the next pace group unlocks, if scheduled.
    public let nextUnlockDay: DateDay?
    /// The self-report state with today's pacing milestones applied. Persist it
    /// (`SelfReportStore.refresh()` does) so introductions stay one per day.
    public let selfReports: SelfReportState
    /// What would sync, in catalog order (§8.2 payload source). Optional items are excluded.
    public let synced: [SyncedStatus]
    /// Evaluated before this launch's first measurement (`evaluate(measured: nil, …)`): the
    /// measured checks are missing from every list, so nothing may be reported, reminded or
    /// called protected from this snapshot.
    public let measurementPending: Bool

    /// The `CheckResult`s for this device (§8.2). Only pass/fail/unknown per allowlisted ID.
    public func results(deviceID: UUID) -> [CheckResult] {
        synced.map {
            CheckResult(deviceID: deviceID, checkID: $0.checkID, status: $0.status, source: $0.source,
                        checkedOn: $0.checkedOn, catalogVersion: catalogVersion)
        }
    }

    /// Measured family items that are failing red or amber: the only things that may notify
    /// (§5.4 "an alert fires only when this device is affected").
    public var reminderCandidates: [ReminderCandidate] {
        familyItems.compactMap { item in
            guard item.source == .measured, item.status == .fail, item.tier == .red || item.tier == .amber,
                  case .check(let id) = item.id
            else { return nil }
            return ReminderCandidate(checkID: id, tier: item.tier, urgent: item.urgent,
                                     titleKey: item.titleKey, bodyKey: item.messageKey)
        }
    }
}

public struct StatusEngine: Sendable {
    /// §6.4: a step answered "Not now" fails its rollup after this many days.
    public static let notNowFailDays = 14

    public let catalog: CheckCatalog
    public let platform: Platform
    public let osMajor: Int
    /// Picks the Face ID or Touch ID wording of a step (iOS). `.unknown` shows the copy that
    /// names both.
    public let biometry: Biometry
    public let pacing: Pacing
    private let clock: Clock

    public var includedPriorities: Set<Priority> { pacing.includedPriorities }

    public init(
        catalog: CheckCatalog,
        platform: Platform = .current,
        osMajor: Int = Platform.currentOSMajor,
        includedPriorities: Set<Priority> = [.p0],
        biometry: Biometry = .unknown,
        clock: Clock = .system
    ) {
        self.catalog = catalog
        self.platform = platform
        self.osMajor = osMajor
        self.biometry = biometry
        self.pacing = Pacing(catalog: catalog, platform: platform, includedPriorities: includedPriorities)
        self.clock = clock
    }

    /// Computes today's snapshot. `selfReports` is advanced for today's pacing first.
    /// `measured: nil` means the measured checks have not run yet (cold launch): Home is then
    /// `.checking` instead of `.protected`, and `measurementPending` is set.
    public func evaluate(measured: [MeasuredResult]?, selfReports: SelfReportState) -> StatusSnapshot {
        let pending = measured == nil
        let measured = measured ?? []
        let today = clock.today()
        let state = pacing.advance(selfReports, today: today)
        let unlocked = pacing.unlockedGroups(state: state, today: today)

        var latest: [CheckID: MeasuredResult] = [:]
        for result in measured {
            if let existing = latest[result.checkID], existing.checkedOn > result.checkedOn { continue }
            latest[result.checkID] = result
        }

        var family: [StatusItem] = []
        var benOnly: [StatusItem] = []
        var optional: [StatusItem] = []
        var synced: [SyncedStatus] = []
        var buildBanner = false

        let accounts = accountSummaries(state: state, today: today)
        let rollupStatus = Dictionary(uniqueKeysWithValues: accounts.compactMap { summary in
            summary.rollup.map { ($0, summary.status) }
        })

        for entry in catalog.entries(for: platform) {
            guard let variant = entry.variant(for: platform) else { continue }
            switch variant.kind {
            case .optional:
                guard includedPriorities.contains(entry.priority) else { continue }
                optional.append(optionalItem(entry, variant))

            case .measured:
                guard let result = latest[entry.id] else { continue }
                let item = measuredItem(entry, variant, result)
                synced.append(SyncedStatus(checkID: entry.id, status: item.status, source: .measured, checkedOn: result.checkedOn))
                if entry.id == .appBuildFresh, item.status == .fail { buildBanner = true }
                if entry.audience == .ben { benOnly.append(item) } else { family.append(item) }

            case .selfCheck:
                guard includedPriorities.contains(entry.priority) else { continue }
                let item = selfCheckItem(entry, variant, state: state, today: today)
                synced.append(SyncedStatus(checkID: entry.id, status: item.status, source: .selfReported,
                                           checkedOn: item.checkedOn ?? today))
                let visible = variant.paceGroup.map(unlocked.contains) ?? true
                guard visible else { continue }
                if entry.audience == .ben { benOnly.append(item) } else { family.append(item) }

            case .accountRollup:
                synced.append(SyncedStatus(checkID: entry.id, status: rollupStatus[entry.id] ?? .unknown,
                                           source: .selfReported, checkedOn: today))
            }
        }

        // Group 3 service rows (one per introduced picked service that isn't done).
        for summary in accounts {
            for progress in summary.services where progress.introduced {
                family.append(serviceItem(progress, rollup: summary.rollup, state: state, today: today))
            }
        }

        // `adp` and `advanced_data_protection` are one feature: show it once.
        let optionalIDs = Set(optional.map(\.checkID))
        optional.removeAll { item in
            catalog[item.checkID]?.sameAs.map(optionalIDs.contains) ?? false
        }

        let toDo = family.filter(\.needsAction).sorted { $0.sortKey < $1.sortKey }
        let suggestions = family
            .filter { !$0.needsAction && $0.status == .fail }
            .sorted { $0.sortKey < $1.sortKey }
        let home: HomeState = toDo.first.map { .toDo(next: $0, later: Array(toDo.dropFirst())) }
            ?? (pending ? .checking : .protected)

        return StatusSnapshot(
            today: today, platform: platform, catalogVersion: catalog.version, home: home, toDo: toDo,
            familyItems: family, suggestions: suggestions, benOnly: benOnly, optionalLinks: optional,
            accounts: accounts, showBuildAgeBanner: buildBanner, unlockedGroups: unlocked,
            nextUnlockDay: pacing.nextUnlockDay(state: state, today: today), selfReports: state, synced: synced,
            measurementPending: pending
        )
    }

    // MARK: Items

    private func measuredItem(_ entry: CatalogEntry, _ variant: CheckVariant, _ result: MeasuredResult) -> StatusItem {
        var status = result.status
        if CheckID.neverFails.contains(entry.id), status == .fail { status = .unknown }
        let urgent = result.urgent && status == .fail
        let tier = entry.effectiveTier(urgent: urgent)
        let message: String
        switch status {
        case .pass: message = variant.passKey
        case .fail: message = urgent ? (variant.failUrgentKey ?? variant.failKey) : variant.failKey
        case .unknown: message = variant.unknownKey ?? "status.unknown.generic"
        }
        let needsAction = status == .fail && (tier == .red || tier == .amber)
        return StatusItem(
            id: .check(entry.id), checkID: entry.id, service: nil, kind: .measured, audience: entry.audience,
            source: .measured, status: status, answer: nil, needsReask: false, urgent: urgent, tier: tier,
            needsAction: needsAction, deferred: false, paceGroup: variant.paceGroup, checkedOn: result.checkedOn,
            titleKey: variant.titleKey, whyKey: variant.whyKey, messageKey: message,
            stepKeys: variant.steps(forOSMajor: osMajor).map(biometry.stepKey), noteKeys: variant.noteKeys, deepLink: variant.deepLink,
            supportURL: variant.supportURL, callBen: variant.callBen, answerStyle: variant.answerStyle,
            sortKey: .init(urgency: tier.urgency, rank: status == .fail ? 0 : 1, paceGroup: 0, order: entry.order)
        )
    }

    private func selfCheckItem(_ entry: CatalogEntry, _ variant: CheckVariant, state: SelfReportState, today: DateDay) -> StatusItem {
        let key = SelfReportKey.check(entry.id)
        let report = state.report(for: key)
        let answer = state.currentAnswer(for: key, on: today)
        let reask = report != nil && answer == nil
        let status = Self.status(for: answer)
        let tier = entry.tier
        let needsAction = status != .pass && (tier == .red || tier == .amber)
        let message: String
        switch answer {
        case .didIt: message = variant.passKey
        case .notSure: message = "selfcheck.notSure.response"
        case .notNow: message = variant.failKey
        case nil: message = reask ? "selfcheck.reask" : variant.failKey
        }
        let rank: Int = switch answer {
        case .notNow: 3
        case .notSure: 2
        default: 1
        }
        return StatusItem(
            id: .check(entry.id), checkID: entry.id, service: nil, kind: .selfCheck, audience: entry.audience,
            source: .selfReported, status: status, answer: answer, needsReask: reask, urgent: false, tier: tier,
            needsAction: needsAction, deferred: answer == .notNow, paceGroup: variant.paceGroup,
            checkedOn: answer != nil ? report?.answeredOn : nil,
            titleKey: variant.titleKey, whyKey: variant.whyKey, messageKey: message,
            stepKeys: variant.steps(forOSMajor: osMajor).map(biometry.stepKey), noteKeys: variant.noteKeys, deepLink: variant.deepLink,
            supportURL: variant.supportURL, callBen: variant.callBen, answerStyle: variant.answerStyle,
            sortKey: .init(urgency: tier.urgency, rank: rank, paceGroup: variant.paceGroup ?? 0, order: entry.order)
        )
    }

    private func optionalItem(_ entry: CatalogEntry, _ variant: CheckVariant) -> StatusItem {
        StatusItem(
            id: .check(entry.id), checkID: entry.id, service: nil, kind: .optional, audience: entry.audience,
            source: variant.source, status: .unknown, answer: nil, needsReask: false, urgent: false, tier: .info,
            needsAction: false, deferred: false, paceGroup: nil, checkedOn: nil,
            titleKey: variant.titleKey, whyKey: variant.whyKey, messageKey: variant.passKey,
            stepKeys: variant.steps(forOSMajor: osMajor).map(biometry.stepKey), noteKeys: variant.noteKeys, deepLink: variant.deepLink,
            supportURL: variant.supportURL, callBen: false, answerStyle: variant.answerStyle,
            sortKey: .init(urgency: 0, rank: 9, paceGroup: 0, order: entry.order)
        )
    }

    private func serviceItem(_ progress: ServiceProgress, rollup: CheckID?, state: SelfReportState, today: DateDay) -> StatusItem {
        let service = progress.service
        // Service rows feed their category rollup; credit bureaus (no rollup) feed the freezes.
        let rollupID = rollup ?? service.linkedChecks.first ?? .accountsShopping
        let whyKey = catalog.variant(rollupID, platform: platform)?.whyKey ?? service.nameKey
        let tier = catalog[rollupID]?.tier ?? .amber
        let done = progress.status == .pass
        let anyNotNow = progress.steps.contains { $0.answer == .notNow } || progress.linkedAnswers.values.contains(.notNow)
        let anyNotSure = progress.steps.contains { $0.answer == .notSure } || progress.linkedAnswers.values.contains(.notSure)
        let anyReask = progress.steps.contains(where: \.needsReask)
        let needsAction = !done && (tier == .red || tier == .amber)
        let message: String
        if done {
            message = "accounts.service.pass"
        } else if anyReask {
            message = "selfcheck.reask"
        } else if anyNotSure {
            message = "selfcheck.notSure.response"
        } else {
            message = "accounts.service.fail"
        }
        let order = 10_000 + Services.displayIndex(service.key)
        return StatusItem(
            id: .service(service.key), checkID: rollupID, service: service.key, kind: .accountRollup,
            audience: .family, source: .selfReported, status: progress.status, answer: nil, needsReask: anyReask,
            urgent: false, tier: tier, needsAction: needsAction, deferred: anyNotNow && !anyReask, paceGroup: 3,
            checkedOn: state.serviceIntroducedOn[service.key],
            titleKey: service.nameKey, whyKey: whyKey, messageKey: message,
            stepKeys: service.steps.map(service.copyKey(for:)), noteKeys: service.whereKey.map { [$0] } ?? [],
            deepLink: nil, supportURL: service.officialURL, callBen: false, answerStyle: .standard,
            sortKey: .init(urgency: tier.urgency, rank: anyNotNow ? 3 : (anyNotSure ? 2 : 1), paceGroup: 3, order: order)
        )
    }

    // MARK: Accounts (§6.4)

    private func accountSummaries(state: SelfReportState, today: DateDay) -> [AccountCategorySummary] {
        let introduced = Set(pacing.introducedServices(state: state, today: today).map(\.key))
        return AccountCategory.allCases.map { category in
            let picked = Services.services(in: category).filter { state.selectedServices.contains($0.key) }
            let services = picked.map { service in
                progress(for: service, introduced: introduced.contains(service.key), state: state, today: today)
            }
            return AccountCategorySummary(
                category: category, rollup: category.rollup, status: Self.rollup(services.map(\.status)),
                services: services)
        }
    }

    private func progress(for service: OnlineService, introduced: Bool, state: SelfReportState, today: DateDay) -> ServiceProgress {
        var reports: [SelfReport?] = []
        var steps: [AccountStepProgress] = []
        for step in service.steps {
            let key = SelfReportKey.accountStep(service.key, step)
            let report = state.report(for: key)
            let answer = state.currentAnswer(for: key, on: today)
            reports.append(answer == nil ? nil : report)
            steps.append(AccountStepProgress(step: step, copyKey: service.copyKey(for: step),
                                             whyKey: service.whyKey(for: step), answer: answer,
                                             needsReask: report != nil && answer == nil))
        }
        var linked: [CheckID: SelfAnswer] = [:]
        for id in service.linkedChecks {
            let key = SelfReportKey.check(id)
            let answer = state.currentAnswer(for: key, on: today)
            reports.append(answer == nil ? nil : state.report(for: key))
            if let answer { linked[id] = answer }
        }
        return ServiceProgress(service: service, introduced: introduced,
                               status: Self.accountStatus(reports, today: today), steps: steps, linkedAnswers: linked)
    }

    /// §6.4 per-service rule: `fail` if any item was answered "Not now" 14+ days ago; `pass` if
    /// every item is "I did it"; otherwise (unanswered, "Not sure", expired) `unknown`.
    static func accountStatus(_ reports: [SelfReport?], today: DateDay) -> Status {
        if reports.isEmpty { return .unknown }
        let staleNotNow = reports.contains { report in
            guard let report, report.answer == .notNow else { return false }
            return today.days(since: report.answeredOn) >= notNowFailDays
        }
        if staleNotNow { return .fail }
        let allDone = reports.allSatisfy { $0?.answer == .didIt }
        return allDone ? .pass : .unknown
    }

    /// §6.4 rollup: none picked → unknown; any service failing → fail; all pass → pass;
    /// otherwise unknown.
    static func rollup(_ statuses: [Status]) -> Status {
        guard !statuses.isEmpty else { return .unknown }
        if statuses.contains(.fail) { return .fail }
        return statuses.allSatisfy { $0 == .pass } ? .pass : .unknown
    }

    /// §6.3 wire status for an answer: I did it → pass, Not now → fail, Not sure / none → unknown.
    public static func status(for answer: SelfAnswer?) -> Status {
        switch answer {
        case .didIt: .pass
        case .notNow: .fail
        case .notSure, nil: .unknown
        }
    }
}
