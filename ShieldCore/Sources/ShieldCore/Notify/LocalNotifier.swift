// LocalNotifier (SPEC §5.4, §10.1 step 4): local notifications only, following the 1 + 1
// reminder policy in ReminderPlanner. Nothing is ever sent off the device.
//
// Permission: the ONLY path that can show the system prompt is `requestPermission()`, which
// the app calls when the person taps [Yes] on the Reminders screen. `update(...)` only reads
// the current authorization and never asks.

import Foundation
@preconcurrency import UserNotifications

/// The notification system, abstracted so tests (and `-FSDemoState`) never touch
/// `UNUserNotificationCenter`.
public protocol NotificationScheduling: Sendable {
    /// Reads the current authorization. Never prompts.
    func isAuthorized() async -> Bool
    /// Shows the system permission prompt (explicit user action only).
    func requestAuthorization() async -> Bool
    func schedule(_ notification: PlannedNotification) async throws
    func cancel(identifiers: [String]) async
}

/// Does nothing and reports "not authorized" (demo states, previews, unbundled processes).
public struct DisabledNotificationScheduler: NotificationScheduling {
    public init() {}
    public func isAuthorized() async -> Bool { false }
    public func requestAuthorization() async -> Bool { false }
    public func schedule(_ notification: PlannedNotification) async throws {}
    public func cancel(identifiers: [String]) async {}
}

/// `UNUserNotificationCenter`. Outside a real `.app` bundle (for example `swift test`), every
/// call is a no-op, because the notification center cannot be used there.
public struct UserNotificationScheduler: NotificationScheduling {
    public init() {}

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    public func isAuthorized() async -> Bool {
        guard let center else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        default: return false
        }
    }

    public func requestAuthorization() async -> Bool {
        guard let center else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.notify.error("notify.request_failed")
            return false
        }
    }

    public func schedule(_ notification: PlannedNotification) async throws {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = "fs.reminders"
        // Tapping or clicking it opens this check (ForegroundNotificationPresenter.didReceive).
        content.userInfo = [ReminderPlanner.checkIDUserInfoKey: notification.checkID.rawValue]
        let trigger: UNNotificationTrigger? = notification.delay > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: notification.delay, repeats: false)
            : nil
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    public func cancel(identifiers: [String]) async {
        guard let center, !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

public actor LocalNotifier {
    public static let defaultsKey = "fs.reminders.v1"

    private let scheduler: any NotificationScheduling
    private let persistence: any LocalStatePersistence
    private let clock: Clock
    private var state: ReminderState

    public init(scheduler: any NotificationScheduling, persistence: any LocalStatePersistence, clock: Clock = .system) {
        self.scheduler = scheduler
        self.persistence = persistence
        self.clock = clock
        if let data = persistence.load(), let saved = try? JSONDecoder().decode(ReminderState.self, from: data) {
            state = saved
        } else {
            state = ReminderState()
        }
    }

    /// The app default: the real notification center, state in `UserDefaults.standard`.
    public static func standard(clock: Clock = .system) -> LocalNotifier {
        LocalNotifier(scheduler: UserNotificationScheduler(),
                      persistence: UserDefaultsPersistence(key: defaultsKey), clock: clock)
    }

    /// Shows the system prompt. Call ONLY from an explicit tap ([Yes] on the Reminders screen).
    public func requestPermission() async -> Bool {
        let granted = await scheduler.requestAuthorization()
        Log.notify.info("notify.permission granted=\(granted, privacy: .private)")
        return granted
    }

    /// Current authorization (never prompts).
    public func isAuthorized() async -> Bool {
        await scheduler.isAuthorized()
    }

    /// The bookkeeping state (for tests and About diagnostics).
    public var reminderState: ReminderState { state }

    /// Plans and schedules reminders for this snapshot.
    @discardableResult
    public func update(with snapshot: StatusSnapshot) async -> ReminderPlan {
        await update(failing: snapshot.reminderCandidates)
    }

    /// Plans and schedules reminders for these failing items. When notifications are not
    /// allowed, the plan is still recorded (so nothing old fires later) but nothing is scheduled.
    @discardableResult
    public func update(failing: [ReminderCandidate]) async -> ReminderPlan {
        let plan = ReminderPlanner.plan(previous: state, failing: failing, today: clock.today())
        state = plan.state
        save()
        await scheduler.cancel(identifiers: plan.cancel)
        guard !plan.schedule.isEmpty else { return plan }
        guard await scheduler.isAuthorized() else {
            Log.notify.info("notify.skipped_not_authorized count=\(plan.schedule.count, privacy: .private)")
            return plan
        }
        for notification in plan.schedule {
            do {
                try await scheduler.schedule(notification)
                Log.notify.info("notify.scheduled check=\(notification.checkID.rawValue, privacy: .public) kind=\(notification.kind.rawValue, privacy: .public)")
            } catch {
                Log.notify.error("notify.schedule_failed check=\(notification.checkID.rawValue, privacy: .public)")
            }
        }
        return plan
    }

    /// Cancels every pending reminder and forgets the bookkeeping.
    public func reset() async {
        let identifiers = state.entries.keys.compactMap(CheckID.init(rawValue:)).flatMap {
            [ReminderPlanner.identifier($0, .first), ReminderPlanner.identifier($0, .reminder)]
        }
        state = ReminderState()
        persistence.erase()
        await scheduler.cancel(identifiers: identifiers)
    }

    private func save() {
        do {
            try persistence.save(try JSONEncoder().encode(state))
        } catch {
            Log.notify.error("notify.save_failed")
        }
    }
}
