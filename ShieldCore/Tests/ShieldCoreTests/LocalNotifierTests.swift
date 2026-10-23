import UserNotifications
import XCTest
@testable import ShieldCore

/// Records what the notifier asks the notification system to do. Never touches
/// UNUserNotificationCenter (no permission prompt on this Mac).
actor RecordingScheduler: NotificationScheduling {
    private(set) var authorized: Bool
    private(set) var scheduled: [PlannedNotification] = []
    private(set) var cancelled: [String] = []
    private(set) var requestCount = 0

    init(authorized: Bool) {
        self.authorized = authorized
    }

    func setAuthorized(_ value: Bool) { authorized = value }

    func isAuthorized() async -> Bool { authorized }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        authorized = true
        return true
    }

    func schedule(_ notification: PlannedNotification) async throws {
        scheduled.append(notification)
    }

    func cancel(identifiers: [String]) async {
        cancelled += identifiers
    }
}

final class ReminderPlannerTests: XCTestCase {
    let day0 = DateDay(year: 2026, month: 10, day: 22)!

    func candidate(_ id: CheckID, _ tier: Tier = .amber, urgent: Bool = false) -> ReminderCandidate {
        ReminderCandidate(checkID: id, tier: tier, urgent: urgent, titleKey: "check.\(id.rawValue).mac.title",
                          bodyKey: "check.\(id.rawValue).mac.fail")
    }

    func testNewFailureSchedulesExactlyOnePlusOne() {
        let plan = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.filevault)], today: day0)
        XCTAssertEqual(plan.schedule.count, 2)
        XCTAssertEqual(plan.schedule.map(\.kind), [.first, .reminder])
        XCTAssertEqual(plan.schedule[0].delay, 0)
        XCTAssertEqual(plan.schedule[1].delay, TimeInterval(ReminderPlanner.reminderDelayDays) * 86_400)
        XCTAssertEqual(plan.schedule[1].titleKey, "notify.reminder.title")
        XCTAssertEqual(plan.cancel, [])
        XCTAssertEqual(plan.state.entries[CheckID.filevault.rawValue]?.notifiedOn, day0)
    }

    func testStillFailingIsSilent() {
        var state = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.filevault)], today: day0).state
        for offset in 1...30 {
            let plan = ReminderPlanner.plan(previous: state, failing: [candidate(.filevault)], today: day0.adding(days: offset))
            XCTAssertTrue(plan.schedule.isEmpty)
            XCTAssertTrue(plan.cancel.isEmpty)
            state = plan.state
        }
    }

    func testResolvedCancelsAndRefailNotifiesAgain() {
        let first = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.filevault)], today: day0)
        let resolved = ReminderPlanner.plan(previous: first.state, failing: [], today: day0.adding(days: 1))
        XCTAssertTrue(resolved.schedule.isEmpty)
        XCTAssertEqual(Set(resolved.cancel), [ReminderPlanner.identifier(.filevault, .first), ReminderPlanner.identifier(.filevault, .reminder)])
        XCTAssertTrue(resolved.state.entries.isEmpty)
        let again = ReminderPlanner.plan(previous: resolved.state, failing: [candidate(.filevault)], today: day0.adding(days: 5))
        XCTAssertEqual(again.schedule.count, 2)
    }

    func testEscalationIsAStateChange() {
        let amber = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.osPatched)], today: day0)
        let red = ReminderPlanner.plan(previous: amber.state, failing: [candidate(.osPatched, .red, urgent: true)], today: day0.adding(days: 1))
        XCTAssertEqual(red.schedule.count, 2)
        XCTAssertEqual(red.cancel, [ReminderPlanner.identifier(.osPatched, .reminder)])
    }

    func testYellowAndInfoNeverNotify() {
        let plan = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.firewall, .yellow), candidate(.timeMachine, .info)], today: day0)
        XCTAssertTrue(plan.schedule.isEmpty)
    }

    func testEachNewFailureGetsItsOwnPair() {
        let plan = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.filevault), candidate(.gatekeeper, .red)], today: day0)
        XCTAssertEqual(plan.schedule.count, 4)
        XCTAssertEqual(Set(plan.schedule.map(\.identifier)).count, 4)
    }

    func testNotificationTextIsCompiledCopy() {
        let plan = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.filevault)], today: day0)
        XCTAssertEqual(plan.schedule[0].title, "FileVault (disk lock)")
        XCTAssertTrue(plan.schedule[0].body.hasPrefix("Turn on FileVault"))
        XCTAssertEqual(plan.schedule[1].title, "A reminder from Family Shield")
    }

    func testStateRoundTrips() throws {
        let state = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.sip, .red)], today: day0).state
        let decoded = try JSONDecoder().decode(ReminderState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}

final class LocalNotifierTests: XCTestCase {
    let day0 = DateDay(year: 2026, month: 10, day: 22)!

    func candidate(_ id: CheckID) -> ReminderCandidate {
        ReminderCandidate(checkID: id, tier: .amber, urgent: false, titleKey: "check.filevault.mac.title", bodyKey: "check.filevault.mac.fail")
    }

    func testAuthorizedSchedulesTwoAndNeverAsks() async {
        let scheduler = RecordingScheduler(authorized: true)
        let notifier = LocalNotifier(scheduler: scheduler, persistence: InMemoryPersistence(), clock: .fixed(day0.date))
        await notifier.update(failing: [candidate(.filevault)])
        await notifier.update(failing: [candidate(.filevault)])
        let scheduled = await scheduler.scheduled
        let asked = await scheduler.requestCount
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(asked, 0)
    }

    func testNotAuthorizedSchedulesNothingButRecordsState() async {
        let scheduler = RecordingScheduler(authorized: false)
        let notifier = LocalNotifier(scheduler: scheduler, persistence: InMemoryPersistence(), clock: .fixed(day0.date))
        let plan = await notifier.update(failing: [candidate(.filevault)])
        XCTAssertEqual(plan.schedule.count, 2)
        let scheduled = await scheduler.scheduled
        XCTAssertTrue(scheduled.isEmpty)
        let state = await notifier.reminderState
        XCTAssertNotNil(state.entries[CheckID.filevault.rawValue])
        // Turning notifications on later does not replay an old failure.
        await scheduler.setAuthorized(true)
        await notifier.update(failing: [candidate(.filevault)])
        let after = await scheduler.scheduled
        XCTAssertTrue(after.isEmpty)
    }

    func testPermissionOnlyThroughExplicitCall() async {
        let scheduler = RecordingScheduler(authorized: false)
        let notifier = LocalNotifier(scheduler: scheduler, persistence: InMemoryPersistence(), clock: .fixed(day0.date))
        _ = await notifier.isAuthorized()
        await notifier.update(failing: [candidate(.filevault)])
        var asked = await scheduler.requestCount
        XCTAssertEqual(asked, 0)
        let granted = await notifier.requestPermission()
        asked = await scheduler.requestCount
        XCTAssertTrue(granted)
        XCTAssertEqual(asked, 1)
    }

    func testStatePersistsAcrossInstances() async {
        let persistence = InMemoryPersistence()
        let scheduler = RecordingScheduler(authorized: true)
        let first = LocalNotifier(scheduler: scheduler, persistence: persistence, clock: .fixed(day0.date))
        await first.update(failing: [candidate(.filevault)])
        let second = LocalNotifier(scheduler: scheduler, persistence: persistence, clock: .fixed(day0.adding(days: 1).date))
        await second.update(failing: [candidate(.filevault)])
        let scheduled = await scheduler.scheduled
        XCTAssertEqual(scheduled.count, 2, "a relaunch doesn't re-notify")
    }

    func testResetCancelsPending() async {
        let scheduler = RecordingScheduler(authorized: true)
        let notifier = LocalNotifier(scheduler: scheduler, persistence: InMemoryPersistence(), clock: .fixed(day0.date))
        await notifier.update(failing: [candidate(.filevault)])
        await notifier.reset()
        let cancelled = await scheduler.cancelled
        XCTAssertEqual(Set(cancelled), [ReminderPlanner.identifier(.filevault, .first), ReminderPlanner.identifier(.filevault, .reminder)])
        let state = await notifier.reminderState
        XCTAssertTrue(state.entries.isEmpty)
    }

    func testRealSchedulerIsInertOutsideAnAppBundle() async throws {
        // `swift test` runs in an xctest bundle, so this must never reach UNUserNotificationCenter.
        guard Bundle.main.bundleURL.pathExtension != "app" else { throw XCTSkip("hosted in an app") }
        let real = UserNotificationScheduler()
        let authorized = await real.isAuthorized()
        XCTAssertFalse(authorized)
        let plan = ReminderPlanner.plan(previous: ReminderState(), failing: [candidate(.filevault)], today: day0)
        try await real.schedule(plan.schedule[0])
        await real.cancel(identifiers: ["x"])
        let disabled = DisabledNotificationScheduler()
        let disabledAuthorized = await disabled.isAuthorized()
        XCTAssertFalse(disabledAuthorized)
    }
}

/// §5.4: the first reminder is delivered right after a check, usually with the app in front, so
/// the notification-center delegate must ask for it to be shown (the system drops it otherwise).
final class ForegroundNotificationTests: XCTestCase {
    func testForegroundRemindersAreShown() async {
        XCTAssertTrue(ForegroundNotificationPresenter.foregroundOptions.contains(.banner))
        XCTAssertTrue(ForegroundNotificationPresenter.foregroundOptions.contains(.list))
        XCTAssertTrue(ForegroundNotificationPresenter.foregroundOptions.contains(.sound))
        // Outside a .app bundle (swift test) installing is a no-op and never touches the center.
        ForegroundNotificationPresenter.install()
    }

    func testBothAppsInstallTheDelegateAtLaunch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for path in ["ShieldiOS/App/AppDelegate.swift", "ShieldMac/App/MacAppDelegate.swift"] {
            guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
                throw XCTSkip("\(path) not readable")
            }
            XCTAssertTrue(text.contains("ForegroundNotificationPresenter.install()"), path)
        }
    }
}

