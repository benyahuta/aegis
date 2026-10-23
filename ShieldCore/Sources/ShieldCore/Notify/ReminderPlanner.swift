// Reminder policy (SPEC §5.4): one local notification per newly failing red or amber item,
// plus one reminder 3 days later, then silence until the state changes. Green sends nothing.
// News alone never notifies: only measured results for THIS device are candidates.
//
// Pure planning, so the "1 + 1" rule is unit-tested without UserNotifications.

import Foundation

/// A failing measured item that may notify (from `StatusSnapshot.reminderCandidates`).
public struct ReminderCandidate: Sendable, Hashable {
    public let checkID: CheckID
    public let tier: Tier
    public let urgent: Bool
    public let titleKey: String
    public let bodyKey: String

    public init(checkID: CheckID, tier: Tier, urgent: Bool, titleKey: String, bodyKey: String) {
        self.checkID = checkID
        self.tier = tier
        self.urgent = urgent
        self.titleKey = titleKey
        self.bodyKey = bodyKey
    }

    /// The "state" that must change before this item may notify again.
    var signature: String { "\(tier.rawValue)|\(urgent ? 1 : 0)" }
}

/// One notification to schedule. Text is compiled copy only (H6).
public struct PlannedNotification: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case first
        case reminder
    }

    public let identifier: String
    public let checkID: CheckID
    public let kind: Kind
    public let titleKey: String
    public let bodyKey: String
    /// Seconds from now (0 = deliver now).
    public let delay: TimeInterval

    /// Rendered title (Markdown stripped).
    public var title: String { ShieldStrings.plain(titleKey) }
    /// Rendered body (Markdown stripped).
    public var body: String { ShieldStrings.plain(bodyKey) }
}

/// What the notifier remembers between runs (local only).
public struct ReminderState: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public var signature: String
        public var notifiedOn: DateDay
    }

    /// Keyed by CheckID raw value.
    public var entries: [String: Entry] = [:]

    public init() {}
}

/// The result of one planning pass.
public struct ReminderPlan: Sendable, Hashable {
    public var schedule: [PlannedNotification]
    /// Pending notification identifiers to remove (item resolved or changed).
    public var cancel: [String]
    public var state: ReminderState
}

public enum ReminderPlanner {
    /// The single follow-up comes this many days after the first notification.
    public static let reminderDelayDays = 3

    public static func identifier(_ id: CheckID, _ kind: PlannedNotification.Kind) -> String {
        "fs.reminder.\(id.rawValue).\(kind.rawValue)"
    }

    /// The `userInfo` key that carries the check a reminder is about (a wire ID, never content).
    public static let checkIDUserInfoKey = "fs.checkID"

    /// The check a delivered reminder is about: from `userInfo`, else parsed from `identifier`.
    public static func checkID(userInfo: [AnyHashable: Any], identifier: String) -> CheckID? {
        if let raw = userInfo[checkIDUserInfoKey] as? String, let id = CheckID(rawValue: raw) { return id }
        let prefix = "fs.reminder."
        guard identifier.hasPrefix(prefix) else { return nil }
        var rest = identifier.dropFirst(prefix.count)
        for kind in [PlannedNotification.Kind.first, .reminder] where rest.hasSuffix("." + kind.rawValue) {
            rest = rest.dropLast(kind.rawValue.count + 1)
            return CheckID(rawValue: String(rest))
        }
        return nil
    }

    /// Plans notifications for the currently failing red/amber items.
    /// - A new failure (or a changed tier) schedules exactly two: now, and +3 days.
    /// - An item still failing in the same state schedules nothing (silence).
    /// - A resolved item cancels its pending reminder and is forgotten, so a later failure
    ///   notifies again.
    public static func plan(previous: ReminderState, failing: [ReminderCandidate], today: DateDay) -> ReminderPlan {
        var state = previous
        var schedule: [PlannedNotification] = []
        var cancel: [String] = []

        var current: [CheckID: ReminderCandidate] = [:]
        for candidate in failing where candidate.tier == .red || candidate.tier == .amber {
            current[candidate.checkID] = candidate
        }

        for key in previous.entries.keys.sorted() {
            guard let id = CheckID(rawValue: key) else {
                state.entries[key] = nil
                continue
            }
            if current[id] == nil {
                state.entries[key] = nil
                cancel.append(identifier(id, .first))
                cancel.append(identifier(id, .reminder))
            }
        }

        for id in current.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let candidate = current[id] else { continue }
            if let entry = state.entries[id.rawValue], entry.signature == candidate.signature { continue }
            if state.entries[id.rawValue] != nil {
                cancel.append(identifier(id, .reminder))
            }
            state.entries[id.rawValue] = ReminderState.Entry(signature: candidate.signature, notifiedOn: today)
            schedule.append(PlannedNotification(
                identifier: identifier(id, .first), checkID: id, kind: .first,
                titleKey: candidate.titleKey, bodyKey: candidate.bodyKey, delay: 0))
            schedule.append(PlannedNotification(
                identifier: identifier(id, .reminder), checkID: id, kind: .reminder,
                titleKey: "notify.reminder.title", bodyKey: candidate.bodyKey,
                delay: TimeInterval(reminderDelayDays) * 86_400))
        }
        return ReminderPlan(schedule: schedule, cancel: cancel, state: state)
    }
}
