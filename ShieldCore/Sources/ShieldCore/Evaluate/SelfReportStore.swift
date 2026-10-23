// SelfReportStore: the person's answers, picked services, carrier and pacing milestones
// (SPEC §5.4, §6.3, §6.4). LOCAL ONLY (UserDefaults or a file). Never synced, never logged
// beyond enum raw values. No free text is ever stored (§12.3), and nothing here can hold a
// password, code or PIN (H2): the only inputs are enum answers.

import Foundation
import os

public final class SelfReportStore: Sendable {
    /// Default UserDefaults key.
    public static let defaultsKey = "fs.selfReports.v1"

    public let pacing: Pacing
    private let persistence: any LocalStatePersistence
    private let clock: Clock
    private let state: OSAllocatedUnfairLock<SelfReportState>

    /// Loads saved state from `persistence` (an unreadable blob starts fresh, never crashes).
    public init(persistence: any LocalStatePersistence, pacing: Pacing, clock: Clock = .system) {
        self.persistence = persistence
        self.pacing = pacing
        self.clock = clock
        var initial = SelfReportState()
        if let data = persistence.load() {
            do {
                initial = try JSONDecoder().decode(SelfReportState.self, from: data)
            } catch {
                Log.status.error("selfreports.decode_failed")
            }
        }
        self.state = OSAllocatedUnfairLock(initialState: initial)
    }

    /// The app default: `UserDefaults.standard`.
    public static func standard(pacing: Pacing, clock: Clock = .system) -> SelfReportStore {
        SelfReportStore(persistence: UserDefaultsPersistence(key: defaultsKey), pacing: pacing, clock: clock)
    }

    /// The current state (not advanced; call `refresh()` before evaluating).
    public var current: SelfReportState {
        state.withLock { $0 }
    }

    public func report(for key: SelfReportKey) -> SelfReport? {
        current.report(for: key)
    }

    /// Records an answer for today. Returns false (and stores nothing) when `key` is not a
    /// self-check on this platform, or the step does not apply to that service.
    @discardableResult
    public func record(_ answer: SelfAnswer, for key: SelfReportKey) -> Bool {
        guard accepts(key) else {
            Log.status.error("selfreports.rejected_key")
            return false
        }
        let today = clock.today()
        mutate { state in
            state.set(answer, for: key, on: today)
        }
        Log.status.info("selfreport answer=\(answer.rawValue, privacy: .public)")
        return true
    }

    /// Forgets one answer.
    public func clearAnswer(for key: SelfReportKey) {
        mutate { $0.clear(key) }
    }

    /// Replaces the picked services (§6.4 picker; "Change my accounts list").
    public func setSelectedServices(_ services: Set<ServiceKey>) {
        mutate {
            $0.selectedServices = services
            $0.accountsPickerDone = true
        }
    }

    /// Marks the accounts picker as seen without picking anything (it reappears with Group 3).
    public func markAccountsPickerDone() {
        mutate { $0.accountsPickerDone = true }
    }

    public func setCarrier(_ carrier: Carrier?) {
        mutate { $0.carrier = carrier }
    }

    /// "Do it all now with Ben" (About). Local only.
    public func setDoItAllNow(_ on: Bool) {
        mutate { $0.doItAllNow = on }
    }

    /// Records any pacing milestones due today and returns the state to evaluate.
    @discardableResult
    public func refresh() -> SelfReportState {
        let today = clock.today()
        return mutate { state in
            state = pacing.advance(state, today: today)
        }
    }

    /// Deletes everything (local reset).
    public func eraseAll() {
        state.withLock { $0 = SelfReportState() }
        persistence.erase()
    }

    // MARK: Private

    private func accepts(_ key: SelfReportKey) -> Bool {
        switch key {
        case .check(let id):
            guard let entry = pacing.catalog[id], let variant = entry.variant(for: pacing.platform) else { return false }
            return variant.kind == .selfCheck
        case .accountStep(let serviceKey, let step):
            guard let service = Services.service(serviceKey) else { return false }
            return service.steps.contains(step)
        }
    }

    /// Applies `change`, advances pacing, saves, and returns the new state.
    @discardableResult
    private func mutate(_ change: @Sendable (inout SelfReportState) -> Void) -> SelfReportState {
        let today = clock.today()
        let pacing = self.pacing
        let persistence = self.persistence
        return state.withLock { state in
            let before = state
            change(&state)
            state = pacing.advance(state, today: today)
            if state != before {
                do {
                    try persistence.save(try JSONEncoder().encode(state))
                } catch {
                    Log.status.error("selfreports.save_failed")
                }
            }
            return state
        }
    }
}
