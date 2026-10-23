// Fixed inputs for `-FSDemoState <name>` (SPEC §13.2 screenshot matrix). They feed the real
// StatusEngine, so screenshots show real copy and real ordering. No network, no CloudKit.

import Foundation

public enum DemoState: String, CaseIterable, Sendable {
    /// First launch: everything measured passes, nothing answered yet (Group 1 to do).
    case firstRun
    /// "You're protected. Nothing to do."
    case protected
    /// Home with one red item (an actively exploited bug on this OS).
    case oneRed
    /// Group 3 open with a few services picked and partly done.
    case accounts

    /// The demo state named by `-FSDemoState`, if it is one of these.
    public init?(options: LaunchOptions) {
        guard let name = options.demoState, let state = DemoState(rawValue: name) else { return nil }
        self = state
    }

    /// Measured results for `platform` on `today`.
    public func measured(catalog: CheckCatalog, platform: Platform, today: DateDay) -> [MeasuredResult] {
        catalog.entries(for: platform).compactMap { entry -> MeasuredResult? in
            guard entry.priority == .p0, entry.variant(for: platform)?.kind == .measured else { return nil }
            if self == .oneRed, entry.id == .osPatched {
                return MeasuredResult(checkID: entry.id, status: .fail, checkedOn: today, urgent: true)
            }
            return MeasuredResult(checkID: entry.id, status: .pass, checkedOn: today)
        }
    }

    /// The self-report state for `platform` on `today`.
    public func selfReports(catalog: CheckCatalog, platform: Platform, today: DateDay) -> SelfReportState {
        var state = SelfReportState()
        guard self != .firstRun else { return state }
        let pacing = Pacing(catalog: catalog, platform: platform)
        let start = today.adding(days: -20)
        state.firstRunOn = start
        for id in pacing.selfChecks(inGroup: 1) { state.set(.didIt, for: .check(id), on: start) }
        state.groupCompletedOn[1] = start
        let group2Day = start.adding(days: Pacing.unlockDelayDays)
        for id in pacing.selfChecks(inGroup: 2) { state.set(.didIt, for: .check(id), on: group2Day) }
        state.groupCompletedOn[2] = group2Day
        state.accountsPickerDone = true

        switch self {
        case .firstRun:
            break
        case .protected, .oneRed:
            state.selectedServices = [.gmail]
            state.serviceIntroducedOn[.gmail] = today.adding(days: -10)
            for step in Services.service(.gmail)?.steps ?? [] {
                state.set(.didIt, for: .accountStep(.gmail, step), on: today.adding(days: -10))
            }
        case .accounts:
            state.doItAllNow = true
            state.selectedServices = [.gmail, .bank, .facebook]
            for step in Services.service(.gmail)?.steps ?? [] {
                state.set(.didIt, for: .accountStep(.gmail, step), on: today.adding(days: -2))
            }
            state.set(.notSure, for: .accountStep(.bank, .twoFactor), on: today.adding(days: -1))
        }
        return state
    }
}
