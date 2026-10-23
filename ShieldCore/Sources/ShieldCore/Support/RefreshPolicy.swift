// When the Mac app re-runs its checks (SPEC §8.4 "on the Mac every 24 h and on wake").
// Pure, so the rules are unit-tested; ShieldMac's MacRefreshSchedule only feeds it triggers.
//
// - launch: always.
// - timer: an hourly tick; checks run once 24 h have passed since the last check. A tick that
//   was missed while the Mac slept is covered by the wake trigger.
// - wake: on every system wake, unless a check ran in the last 10 minutes (wake storms).
// - activated: the app comes to the front (for example back from System Settings after a fix),
//   unless a check ran in the last minute.

import Foundation

public enum RefreshTrigger: String, Sendable, CaseIterable {
    case launch
    case timer
    case wake
    case activated
}

public enum RefreshPolicy {
    public static let interval: TimeInterval = 24 * 60 * 60
    /// How often the Mac's timer ticks to compare against `interval`.
    public static let tick: TimeInterval = 60 * 60
    public static let wakeDebounce: TimeInterval = 10 * 60
    public static let activationDebounce: TimeInterval = 60

    /// True when `trigger` should start a new check run.
    public static func shouldRefresh(_ trigger: RefreshTrigger, lastChecked: Date?, now: Date) -> Bool {
        guard let lastChecked else { return true }
        let elapsed = now.timeIntervalSince(lastChecked)
        // A clock that moved backwards: check again rather than wait up to a day.
        if elapsed < 0 { return true }
        switch trigger {
        case .launch: return true
        case .timer: return elapsed >= interval
        case .wake: return elapsed >= wakeDebounce
        case .activated: return elapsed >= activationDebounce
        }
    }
}
