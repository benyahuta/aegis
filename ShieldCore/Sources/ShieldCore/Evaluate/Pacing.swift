// Pacing of self-checks (SPEC §5.4; DECISIONS §9): Group 1 at first run, Group 2 three days
// after Group 1 is answered, Group 3 (online accounts) three days after Group 2, introducing at
// most one service per day. "Do it all now with Ben" unlocks everything at once (local toggle).

import Foundation

public struct Pacing: Sendable {
    /// Days between a group being answered and the next one unlocking.
    public static let unlockDelayDays = 3
    /// The pace groups, in order.
    public static let groups = [1, 2, 3]

    public let catalog: CheckCatalog
    public let platform: Platform
    /// Only checks with these priorities take part (P1/P2 self-checks stay hidden until enabled).
    public let includedPriorities: Set<Priority>

    public init(catalog: CheckCatalog, platform: Platform, includedPriorities: Set<Priority> = [.p0]) {
        self.catalog = catalog
        self.platform = platform
        self.includedPriorities = includedPriorities
    }

    /// The self-checks on this platform in `group`, in catalog order.
    public func selfChecks(inGroup group: Int) -> [CheckID] {
        catalog.entries(for: platform).compactMap { entry in
            guard includedPriorities.contains(entry.priority),
                  let variant = entry.variant(for: platform),
                  variant.kind == .selfCheck, variant.paceGroup == group
            else { return nil }
            return entry.id
        }
    }

    /// The day `group` unlocks (or unlocked), if known. Group 1: first run.
    public func unlockDay(of group: Int, in state: SelfReportState) -> DateDay? {
        if group <= 1 { return state.firstRunOn }
        return state.groupCompletedOn[group - 1]?.adding(days: Pacing.unlockDelayDays)
    }

    public func isUnlocked(_ group: Int, state: SelfReportState, today: DateDay) -> Bool {
        if state.doItAllNow || group <= 1 { return true }
        // Picking accounts is an explicit request: their steps show up right away.
        if group == 3, !state.selectedServices.isEmpty { return true }
        guard let day = unlockDay(of: group, in: state) else { return false }
        return today >= day
    }

    /// Unlocked pace groups.
    public func unlockedGroups(state: SelfReportState, today: DateDay) -> Set<Int> {
        Set(Pacing.groups.filter { isUnlocked($0, state: state, today: today) })
    }

    /// The next day something new unlocks (a group or a service), if one is scheduled.
    public func nextUnlockDay(state: SelfReportState, today: DateDay) -> DateDay? {
        Pacing.groups.compactMap { group -> DateDay? in
            guard !isUnlocked(group, state: state, today: today), let day = unlockDay(of: group, in: state) else { return nil }
            return day
        }.min()
    }

    /// Picked services, in display order.
    public func pickedServices(_ state: SelfReportState) -> [OnlineService] {
        Services.all.filter { state.selectedServices.contains($0.key) }
    }

    /// Picked services that are on screen now (Group 3 unlocked and the service introduced).
    public func introducedServices(state: SelfReportState, today: DateDay) -> [OnlineService] {
        guard isUnlocked(3, state: state, today: today) else { return [] }
        return pickedServices(state).filter { state.serviceIntroducedOn[$0.key] != nil }
    }

    /// True when every step and linked check of `service` has a current answer.
    public func isFullyAnswered(_ service: OnlineService, state: SelfReportState, today: DateDay) -> Bool {
        let steps = service.steps.allSatisfy { state.currentAnswer(for: .accountStep(service.key, $0), on: today) != nil }
        let linked = service.linkedChecks.allSatisfy { state.currentAnswer(for: .check($0), on: today) != nil }
        return steps && linked
    }

    /// Records pacing milestones that are due on `today`. Pure: returns the new state.
    /// - first run day
    /// - the day each group was first fully answered (never moved afterwards)
    /// - Group 3 service introductions: every picked service, the day it is picked.
    public func advance(_ state: SelfReportState, today: DateDay) -> SelfReportState {
        var next = state
        if next.firstRunOn == nil { next.firstRunOn = today }

        for group in [1, 2] where next.groupCompletedOn[group] == nil && isUnlocked(group, state: next, today: today) {
            let items = selfChecks(inGroup: group)
            let reports = items.map { next.report(for: .check($0)) }
            let answered = zip(items, reports).allSatisfy { id, report in
                report != nil && next.currentAnswer(for: .check(id), on: today) != nil
            }
            guard answered else { continue }
            let lastAnswer = reports.compactMap { $0?.answeredOn }.max()
            let floor = unlockDay(of: group, in: next) ?? today
            next.groupCompletedOn[group] = min(max(lastAnswer ?? floor, floor), today)
        }

        if isUnlocked(3, state: next, today: today) {
            let picked = pickedServices(next)
            // Every picked service shows up the day it's picked. Home still offers one
            // Next step at a time, so the list never lands all at once.
            for service in picked where next.serviceIntroducedOn[service.key] == nil {
                next.serviceIntroducedOn[service.key] = today
            }
        }
        return next
    }
}
