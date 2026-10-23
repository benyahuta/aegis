import XCTest
import ShieldCore
@testable import ShieldUI

/// The shared AppModel (SPEC §10, §5.4, §8.4) driven through in-memory dependencies.
@MainActor
final class AppModelTests: XCTestCase {
    private let day = DateDay(year: 2026, month: 10, day: 22)!

    private func makeModel(
        platform: Platform = .ios,
        measured: [MeasuredResult]? = nil,
        callBen: String? = nil,
        pickedNumber: String? = "+1 (415) 555 0100",
        sync: SyncServices = .inMemory(),
        ui: UIStateStore = .inMemory(),
        notifications: any NotificationScheduling = DisabledNotificationScheduler(),
        measure: (@Sendable () async -> [MeasuredResult])? = nil,
        loginItem: LoginItemControl? = nil
    ) -> AppModel {
        let clock = Clock.fixed(day.date.addingTimeInterval(9 * 3_600))
        let today = clock.today()
        let results = measured ?? [
            MeasuredResult(checkID: .osPatched, status: .pass, checkedOn: today),
            MeasuredResult(checkID: .deviceSupported, status: .pass, checkedOn: today),
            MeasuredResult(checkID: .passcodeSet, status: .pass, checkedOn: today),
            MeasuredResult(checkID: .biometricsEnrolled, status: .pass, checkedOn: today),
            MeasuredResult(checkID: .appBuildFresh, status: .pass, checkedOn: today),
        ]
        let catalog = CheckCatalog.shared
        let services = PlatformServices(measure: measure ?? { results }, canPickContact: true,
                                        pickContactNumber: { pickedNumber }, loginItem: loginItem)
        return AppModel(
            platform: platform, options: LaunchOptions(noCloud: true), clock: clock, catalog: catalog, osMajor: 26,
            selfReports: SelfReportStore(persistence: InMemoryPersistence(), pacing: Pacing(catalog: catalog, platform: platform), clock: clock),
            notifier: LocalNotifier(scheduler: notifications, persistence: InMemoryPersistence(), clock: clock),
            sync: sync, callBenStore: InMemoryCallBenStore(callBen), uiState: ui, services: services,
            build: BuildInfo(version: "1.0", build: 7, buildDay: today.adding(days: -5))
        )
    }

    // MARK: Home

    func testFirstRunShowsGroupOneAsThingsToDo() async {
        let model = makeModel()
        await model.refresh()
        XCTAssertEqual(model.snapshot.home.count, 6, "Group 1 has six self-checks (§5.4)")
        XCTAssertEqual(model.snapshot.home.nextStep?.checkID, .autoUpdates)
        XCTAssertNotNil(model.lastCheckedAt)
    }

    func testExploitedUpdateIsTodayAndOpensFixStep() async {
        let today = day
        let model = makeModel(measured: [
            MeasuredResult(checkID: .osPatched, status: .fail, checkedOn: today, urgent: true),
        ])
        await model.refresh()
        let next = try! XCTUnwrap(model.snapshot.home.nextStep)
        XCTAssertEqual(next.checkID, .osPatched)
        XCTAssertEqual(model.appearance(next), .today)
        XCTAssertEqual(model.route(for: next), .fix(.osPatched))
        XCTAssertEqual(model.snapshot.home.headline, "7 things to do today.", "the red update plus Group 1")
    }

    func testAnsweringNotSureStaysAmberWithReassurance() async {
        let model = makeModel()
        await model.refresh()
        model.answer(.notSure, for: .check(.stolenDeviceProtection))
        let item = try! XCTUnwrap(model.item(.stolenDeviceProtection))
        XCTAssertEqual(item.status, .unknown, "Not sure is written as unknown (§5.1)")
        XCTAssertEqual(model.appearance(item), .toDo, "and shown amber (§6.3)")
        XCTAssertEqual(item.messageKey, "selfcheck.notSure.response")
    }

    func testAnsweringEverythingInGroupOneGivesProtected() async {
        let model = makeModel()
        await model.refresh()
        for id in [CheckID.autoUpdates, .stolenDeviceProtection, .recoveryContact, .screenUnknown, .findMy, .familyCodeWord] {
            model.answer(.didIt, for: .check(id))
        }
        XCTAssertEqual(model.snapshot.home, .protected)
        XCTAssertEqual(model.snapshot.home.headline, "You're protected. Nothing to do.")
    }

    func testColdLaunchSaysCheckingUntilTheMeasuredChecksRan() async {
        // H7: an established user (Group 1 answered) whose phone was red yesterday must not see
        // "You're protected" / "Protected" while this launch's checks are still running.
        let red = [MeasuredResult(checkID: .osPatched, status: .fail, checkedOn: day, urgent: true)]
        let sink = InMemoryResultSink()
        let id = UUID()
        let sync = SyncServices(sink: sink, cloudSink: nil, owner: nil,
                                deviceIdentity: InMemoryDeviceIdentityStore(id), settings: .inMemory())
        let gate = MeasureGate()
        let model = makeModel(sync: sync, measure: { await gate.wait(); return red })
        XCTAssertTrue(model.snapshot.measurementPending)
        XCTAssertEqual(model.snapshot.home.count, 6, "Group 1 is still to do while checking")
        for id in [CheckID.autoUpdates, .stolenDeviceProtection, .recoveryContact, .screenUnknown, .findMy, .familyCodeWord] {
            model.answer(.didIt, for: .check(id))
        }
        XCTAssertEqual(model.snapshot.home, .checking, "nothing to do yet, but not protected either")
        XCTAssertEqual(model.snapshot.home.headline, "Checking now. One moment.")
        XCTAssertEqual(model.snapshot.home.menuBarWord, "Checking")
        XCTAssertEqual(MenuBarLabelContent.symbol(model.snapshot.home), "shield")
        XCTAssertEqual(model.homeAppearance, .cantCheck, "grey, never the green check")

        let checking = Task { await model.refresh() }
        await Task.yield()
        let early = await sink.results(for: id)
        XCTAssertTrue(early.isEmpty, "a snapshot without the measured checks is never reported")
        await gate.release()
        await checking.value
        XCTAssertFalse(model.snapshot.measurementPending)
        XCTAssertEqual(model.snapshot.home.headline, "1 thing to do today.")
        XCTAssertEqual(model.snapshot.home.menuBarWord, "Today")
        let reported = await sink.results(for: id)
        XCTAssertTrue(reported.contains { $0.checkID == .osPatched && $0.status == .fail })
    }

    func testRemindersPermissionIsReadBeforeTheSlowCheck() async {
        // About must not say "Off" (or "turned off in Settings") for the whole feed fetch.
        let ui = UIStateStore.inMemory()
        ui.remindersOptIn = true
        let notifications = FakeNotificationScheduler(grants: true)
        notifications.authorized = true
        let gate = MeasureGate()
        let model = makeModel(ui: ui, notifications: notifications, measure: { await gate.wait(); return [] })
        XCTAssertNil(model.remindersAllowed, "not read yet")
        XCTAssertFalse(model.remindersBlocked, "unknown is not \"turned off in Settings\"")
        XCTAssertTrue(model.remindersShownOn)
        let checking = Task { await model.refresh() }
        for _ in 0..<50 where model.remindersAllowed == nil { await Task.yield() }
        XCTAssertTrue(model.remindersOptIn, "known while the checks are still running")
        XCTAssertNil(model.lastCheckedAt)
        await gate.release()
        await checking.value
    }

    func testTurningRemindersOffCancelsTheQueuedReminder() async {
        let notifications = FakeNotificationScheduler(grants: true)
        let model = makeModel(measured: [MeasuredResult(checkID: .osPatched, status: .fail, checkedOn: day)],
                              notifications: notifications)
        await model.refresh()
        _ = await model.answerReminders(true)
        XCTAssertEqual(notifications.pending, [ReminderPlanner.identifier(.osPatched, .first),
                                               ReminderPlanner.identifier(.osPatched, .reminder)])
        await model.answerReminders(false)
        XCTAssertTrue(notifications.pending.isEmpty, "the +3 days reminder must not fire after Turn off")
        // Turning them back on later reminds again about what is still failing.
        _ = await model.answerReminders(true)
        XCTAssertTrue(notifications.pending.contains(ReminderPlanner.identifier(.osPatched, .reminder)))
    }

    func testTappingAReminderOpensItsStep() async {
        let model = makeModel(measured: [MeasuredResult(checkID: .osPatched, status: .fail, checkedOn: day)])
        await model.refresh()
        model.openFromNotification(checkID: .osPatched)
        XCTAssertTrue(model.homePath.isEmpty, "before setup is finished it only brings the app forward")
        model.finishOnboarding()
        model.selectedTab = .family
        model.openFromNotification(checkID: .osPatched)
        XCTAssertEqual(model.selectedTab, .home)
        XCTAssertEqual(model.homePath, [.fix(.osPatched)])
        model.openFromNotification(checkID: .passcodeSet)
        XCTAssertEqual(model.homePath, [], "fixed since: just Home")
        XCTAssertEqual(ReminderPlanner.checkID(userInfo: [:], identifier: ReminderPlanner.identifier(.osPatched, .reminder)),
                       .osPatched)
        XCTAssertEqual(ReminderPlanner.checkID(userInfo: [ReminderPlanner.checkIDUserInfoKey: "passcode_set"], identifier: "x"),
                       .passcodeSet)
        XCTAssertNil(ReminderPlanner.checkID(userInfo: [:], identifier: "fs.reminder.nope.first"))
    }

    func testRefusedLoginItemRegisterSaysBenWillSetItUp() {
        // SMAppService.register() threw and the item stayed off: not the same dead button again.
        XCTAssertEqual(LoginItemState.afterRegister(status: .off, threw: true), .unavailable)
        XCTAssertEqual(LoginItemState.afterRegister(status: .off, threw: false), .off)
        XCTAssertEqual(LoginItemState.afterRegister(status: .needsApproval, threw: true), .needsApproval)
        let control = LoginItemControl(status: { .off }, register: { .unavailable }, openSettings: {})
        let model = makeModel(platform: .mac, loginItem: control)
        XCTAssertEqual(model.loginItemState, .off)
        XCTAssertEqual(model.keepCheckingInBackground(), .unavailable)
        model.refreshLoginItemState()
        XCTAssertEqual(model.loginItemState, .unavailable, "coming back to the app doesn't bring the button back")
    }

    // MARK: Onboarding

    func testOnboardingOrderAndFinish() {
        let ui = UIStateStore.inMemory()
        let model = makeModel(ui: ui)
        XCTAssertEqual(model.onboarding, .welcome)
        model.next(after: .welcome)
        model.next(after: .join)
        model.next(after: .whoToCall)
        model.next(after: .reminders)
        XCTAssertEqual(model.onboardingPath, [.join, .whoToCall, .reminders, .accounts])
        model.next(after: .accounts)
        XCTAssertEqual(model.onboarding, .done)
        XCTAssertTrue(model.onboardingPath.isEmpty)
        XCTAssertEqual(ui.onboarding, .done, "persisted locally")
    }

    func testRemindersNoThanksNeverOptsIn() async {
        let model = makeModel()
        await model.answerReminders(false)
        XCTAssertFalse(model.remindersOptIn)
        await model.answerReminders(true)
        XCTAssertFalse(model.remindersOptIn, "a scheduler that refuses permission leaves reminders off")
    }

    func testDeniedRemindersSaySoAndTurnOnFromSettingsLater() async {
        let notifications = FakeNotificationScheduler(grants: false)
        let model = makeModel(notifications: notifications)
        let on = await model.answerReminders(true)
        XCTAssertFalse(on)
        XCTAssertTrue(model.remindersBlocked, "the Reminders screen explains how to turn them on")
        XCTAssertEqual(notifications.requests, 1)

        // The person turns notifications on in Settings; the next check picks it up.
        notifications.authorized = true
        await model.refresh()
        XCTAssertTrue(model.remindersOptIn)
        XCTAssertFalse(model.remindersBlocked)

        // [Turn off reminders] from About never asks the system.
        await model.answerReminders(false)
        XCTAssertFalse(model.remindersOptIn)
        XCTAssertFalse(model.remindersBlocked)
        await model.refresh()
        XCTAssertFalse(model.remindersOptIn, "a No stays a No even though the system allows it")
        XCTAssertEqual(notifications.requests, 1)
    }

    func testGrantedRemindersAreOn() async {
        let model = makeModel(notifications: FakeNotificationScheduler(grants: true))
        let on = await model.answerReminders(true)
        XCTAssertTrue(on)
        XCTAssertTrue(model.remindersOptIn)
    }

    // MARK: Call Ben

    func testCallBenNeedsAPickedNumberAndKeepsOnlyDigits() async {
        let model = makeModel()
        XCTAssertNil(model.callBenURL)
        let saved = await model.chooseBen()
        XCTAssertEqual(saved, .saved)
        XCTAssertEqual(model.callBenURL?.absoluteString, "tel:+14155550100")
    }

    func testCancelledPickerSavesNothing() async {
        let model = makeModel(pickedNumber: nil)
        let saved = await model.chooseBen()
        XCTAssertEqual(saved, .cancelled)
        XCTAssertNil(model.benNumber)
    }

    func testUnusablePickedNumberIsReported() async {
        for number in ["#1", "1-800-FLOWERS", "+1 415 555 0100 9999 9999"] {
            let model = makeModel(pickedNumber: number)
            let saved = await model.chooseBen()
            XCTAssertEqual(saved, .notSaved, number)
            XCTAssertNil(model.benNumber)
        }
        XCTAssertTrue(ShieldStrings.contains("whoToCall.notSaved"))
    }

    // MARK: Scam session (memory only)

    func testPastedScamGoesToResultAndIsForgottenOnLeaving() async {
        let model = makeModel()
        model.open(.scamEntry)
        model.open(.pasteMessage)
        model.scamDraft = DemoScreen.dangerSample
        await model.checkMessage()
        XCTAssertEqual(model.homePath.last, .scamResult)
        XCTAssertEqual(model.scamOutcome?.verdict, .danger)
        XCTAssertLessThanOrEqual(model.scamOutcome?.reasons.count ?? 9, 3)
        model.popToHome()
        XCTAssertNil(model.scamOutcome, "result is dropped when the scam screens close (§5.3)")
        XCTAssertEqual(model.scamDraft, "")
    }

    func testPastedCheckRunsOffTheMainActorAndIsDroppedAfterLeaving() async {
        let model = makeModel()
        model.homePath = [.scamEntry, .pasteMessage]
        model.scamDraft = String(repeating: "Call 1-800-555-0199 about your account. ", count: 190)
        let check = Task { await model.checkMessage() }
        // The main actor keeps running while the rules do (an 8,000-character paste never
        // freezes the screen).
        while !model.isCheckingMessage { await Task.yield() }
        model.homePath = []
        await check.value
        XCTAssertEqual(model.homePath, [], "the result is not pushed after leaving")
        XCTAssertNil(model.scamOutcome)
        XCTAssertFalse(model.isCheckingMessage)
    }

    func testScreenshotCheckFinishingAfterLeavingIsDiscarded() async {
        let image = Data(repeating: 0x7F, count: 2048)
        for leave in [[Route](), [Route.fix(.osPatched)]] {
            let model = makeModel()
            model.homePath = [.scamEntry]
            let check = Task { await model.checkScreenshot(image) }
            while !model.isCheckingScam { await Task.yield() }
            model.homePath = leave
            await check.value
            XCTAssertEqual(model.homePath, leave, "the result is not pushed onto Home or a fix step")
            XCTAssertNil(model.scamOutcome, "and the screenshot is not kept (§5.3)")
            XCTAssertFalse(model.isCheckingScam)
        }

        // Staying on the scam screens still shows the result.
        let model = makeModel()
        model.homePath = [.scamEntry]
        await model.checkScreenshot(image)
        XCTAssertEqual(model.homePath, [.scamEntry, .scamResult])
        XCTAssertNotNil(model.scamOutcome)
    }

    func testMenuBarShortcutsWaitForSetupAndSetupStartsAtHome() {
        let model = makeModel(platform: .mac)
        XCTAssertNotEqual(model.onboarding, .done)
        model.openFromMenuBar(.scamEntry)
        XCTAssertTrue(model.homePath.isEmpty, "nothing is pushed behind the setup screens")
        model.homePath = [.fix(.filevault)]
        model.finishOnboarding()
        XCTAssertTrue(model.homePath.isEmpty, "setup always ends on Home")
        model.openFromMenuBar(.scamEntry)
        XCTAssertEqual(model.homePath, [.scamEntry])
    }

    func testShareFailuresAreSaid() {
        for platform in Platform.allCases {
            XCTAssertEqual(AppModel.shareFailureNotice(.alreadyConnected, platform: platform),
                           L.t(L.platformKey("share.failed.alreadyConnected", platform)))
            XCTAssertEqual(AppModel.shareFailureNotice(.invalidShare, platform: platform), L.t("share.failed.invalid"))
            XCTAssertEqual(AppModel.shareFailureNotice(.notConnected, platform: platform), L.t("share.failed.notConnected"))
            XCTAssertEqual(AppModel.shareFailureNotice(.unavailable, platform: platform), L.t(L.platformKey("share.failed.offline", platform)))
            XCTAssertEqual(AppModel.shareFailureNotice(nil, platform: platform), L.t(L.platformKey("share.failed.offline", platform)))
            // A refused link says the link didn't work and what to do, not the About screen's
            // "keeps working here" line on its own.
            let rejected = AppModel.shareFailureNotice(.rejected, platform: platform)
            XCTAssertEqual(rejected, L.t("share.failed.rejected"))
            XCTAssertTrue(rejected.contains("link"), rejected)
            XCTAssertNotEqual(rejected, L.t("about.sync.notDelivering.detail"))
        }
        // The Mac says click; the iPhone says tap.
        XCTAssertTrue(AppModel.shareFailureNotice(.alreadyConnected, platform: .mac).contains("click"))
        XCTAssertTrue(AppModel.shareFailureNotice(.unavailable, platform: .mac).contains("click"))
        XCTAssertTrue(AppModel.shareFailureNotice(.unavailable, platform: .ios).contains("tap"))
    }

    func testCheckAnotherReturnsToEntry() async {
        let model = makeModel()
        model.homePath = [.scamEntry, .pasteMessage]
        model.scamDraft = "hello"
        await model.checkMessage()
        model.checkAnother()
        XCTAssertEqual(model.homePath, [.scamEntry])
        XCTAssertNil(model.scamOutcome)
    }

    func testCallQuizIsNeverGrey() {
        let model = makeModel()
        for caller in CallQuiz.Caller.allCases {
            for want in CallQuiz.Want.allCases {
                model.finishCallQuiz(CallQuiz.Answers(caller: caller, want: want, secretOrRushed: false, youCalledThem: true))
                XCTAssertNotEqual(model.scamOutcome?.verdict, .noCommonSignsFound)
            }
        }
    }

    // MARK: Sync

    func testRefreshReportsOnlyAllowlistedResults() async throws {
        let sink = InMemoryResultSink()
        let id = UUID()
        let sync = SyncServices(sink: sink, cloudSink: nil, owner: nil,
                                deviceIdentity: InMemoryDeviceIdentityStore(id), settings: .inMemory())
        let model = makeModel(sync: sync)
        await model.refresh()
        let stored = await sink.results(for: id)
        XCTAssertFalse(stored.isEmpty)
        XCTAssertEqual(Set(stored.map(\.checkID)), Set(model.snapshot.synced.map(\.checkID)))
        let device = await sink.devices[id]
        XCTAssertEqual(device?.appBuild, 7)
        XCTAssertEqual(device?.platform, .ios)
    }

    func testStopSharingLeavesAndSaysSo() async {
        let sink = InMemoryResultSink()
        let sync = SyncServices(sink: sink, cloudSink: nil, owner: nil,
                                deviceIdentity: InMemoryDeviceIdentityStore(), settings: .inMemory())
        let model = makeModel(sync: sync)
        await model.stopSharing()
        let leaves = await sink.leaveCount
        XCTAssertEqual(leaves, 1)
        XCTAssertEqual(model.notice, "You're no longer sharing with Ben.")
    }

    func testBensOwnDeviceHasNoStopSharing() async {
        // Ben's own iPhone reports into z_self; "Stop sharing with Ben" would delete its records.
        let sink = InMemoryResultSink()
        let settings = SyncSettings.inMemory()
        settings.isOwner = true
        settings.target = .ownerSelf
        settings.connection = .connected
        let sync = SyncServices(sink: sink, cloudSink: nil, owner: nil,
                                deviceIdentity: InMemoryDeviceIdentityStore(), settings: settings)
        let model = makeModel(sync: sync)
        XCTAssertEqual(model.connection, .connected)
        XCTAssertFalse(model.canStopSharing)
        await model.stopSharing()
        let leaves = await sink.leaveCount
        XCTAssertEqual(leaves, 0)

        let relative = SyncSettings.inMemory()
        relative.connection = .connected
        let family = makeModel(sync: SyncServices(sink: InMemoryResultSink(), cloudSink: nil, owner: nil,
                                                  deviceIdentity: InMemoryDeviceIdentityStore(), settings: relative))
        XCTAssertTrue(family.canStopSharing)
    }

    // MARK: Ben

    func testStartFamilyWithoutICloudShowsSampleFamily() async {
        let model = makeModel()
        let ok = await model.startFamily()
        XCTAssertTrue(ok)
        XCTAssertTrue(model.isOwner)
        XCTAssertTrue(model.dashboardIsSample)
        XCTAssertEqual(model.selectedTab, .family)
        XCTAssertEqual(model.onboarding, .done)
    }

    func testInviteWithoutICloudIsOffline() async {
        let model = makeModel()
        let result = await model.invite(label: "Mom")
        XCTAssertEqual(result, .offline)
    }

    // MARK: Accounts

    func testAccountsPickerStoresSelectionLocally() async {
        let model = makeModel()
        model.setSelectedServices([.gmail, .bank])
        XCTAssertEqual(model.selectedServices, [.gmail, .bank])
        model.skipAccountsPicker()
        XCTAssertFalse(model.showAccountsPrompt)
    }
}

/// `-FSDemoState` screens (§13.2).
@MainActor
final class DemoScreenTests: XCTestCase {
    func testEveryDemoScreenBuildsOffline() {
        for screen in DemoScreen.allCases {
            for platform in Platform.allCases {
                let model = AppModel.demo(screen, platform: platform)
                XCTAssertTrue(model.options.noCloud, "\(screen)")
                XCTAssertFalse(model.sync.usesCloud, "\(screen)")
                XCTAssertNotNil(model.lastCheckedAt, "\(screen)")
            }
        }
    }

    func testNamesAndAliases() {
        XCTAssertEqual(DemoScreen(name: "homeOneRed"), .homeOneRed)
        XCTAssertEqual(DemoScreen(name: "HOMEONERED"), .homeOneRed)
        XCTAssertEqual(DemoScreen(name: "oneRed"), .homeOneRed)
        XCTAssertEqual(DemoScreen(name: "firstRun"), .homeFirstRun)
        XCTAssertNil(DemoScreen(name: "nope"))
        XCTAssertTrue(Set(DemoScreen.screenshotMatrix).isSubset(of: Set(DemoScreen.allCases)))
    }

    func testHomeDemoStates() {
        XCTAssertEqual(AppModel.demo(.homeProtected, platform: .ios).snapshot.home, .protected)
        let red = AppModel.demo(.homeOneRed, platform: .ios)
        XCTAssertEqual(red.snapshot.home.nextStep?.checkID, .osPatched)
        XCTAssertTrue(red.snapshot.home.isToday)
        XCTAssertTrue(AppModel.demo(.homeBuildBanner, platform: .ios).snapshot.showBuildAgeBanner)
    }

    func testResultSamplesGiveTheirVerdicts() {
        XCTAssertEqual(AppModel.demo(.resultDanger, platform: .ios).scamOutcome?.verdict, .danger)
        XCTAssertEqual(AppModel.demo(.resultCareful, platform: .ios).scamOutcome?.verdict, .beCareful)
        XCTAssertEqual(AppModel.demo(.resultNoSigns, platform: .ios).scamOutcome?.verdict, .noCommonSignsFound)
    }

    func testDemoRefreshKeepsFixedResults() async {
        let model = AppModel.demo(.homeOneRed, platform: .ios)
        await model.refresh()
        XCTAssertEqual(model.snapshot.home.nextStep?.checkID, .osPatched)
    }

    func testBenScreensOpenTheFamilyTab() {
        for screen in [DemoScreen.familyTab, .deviceDetail, .addPerson, .feedHealth] {
            let model = AppModel.demo(screen, platform: .ios)
            XCTAssertTrue(model.isOwner, "\(screen)")
            XCTAssertEqual(model.selectedTab, .family, "\(screen)")
            XCTAssertNotNil(model.dashboard)
        }
        let detail = AppModel.demo(.deviceDetail, platform: .ios)
        XCTAssertNotNil(detail.device(zoneName: DemoFamily.momZone, deviceID: DemoFamily.momPhone))
    }

    func testDemoFamilyFollowsStalenessRules() {
        let today = DateDay(year: 2026, month: 10, day: 22)!
        let dashboard = DemoFamily.dashboard(today: today, catalog: .shared)
        let devices = dashboard.people.flatMap(\.devices)
        let dad = try! XCTUnwrap(devices.first { $0.deviceID == DemoFamily.dadPhone })
        XCTAssertEqual(dad.staleness, .notReporting)
        XCTAssertEqual(DashboardCopy.chip(dad, catalog: .shared), .cantCheck, "grey past 7 days (§8.4)")
        let mom = try! XCTUnwrap(devices.first { $0.deviceID == DemoFamily.momPhone })
        XCTAssertEqual(DashboardCopy.chip(mom, catalog: .shared), .today,
                       "os_patched failing while an exploited fix is out is red on Mom's iPhone, so red here too")
        XCTAssertTrue(dashboard.people.first?.isSelf ?? false, "Ben's own devices first")
        XCTAssertEqual(dashboard.people.first { $0.zoneName == DemoFamily.grandmaZone }?.inviteAccepted, false)
    }
}

// MARK: - Family tab (§10.3)

extension AppModelTests {

    /// A model in Ben's owner mode over an in-memory CloudKit, past onboarding.
    private func makeOwnerModel(backend: InMemoryCloudBackend) async throws -> AppModel {
        let settings = SyncSettings.inMemory()
        let owner = OwnerStore(container: backend.container(), settings: settings, clock: .fixed(day.date))
        try await owner.startFamily()
        let sync = SyncServices(sink: InMemoryResultSink(), cloudSink: nil, owner: owner,
                                deviceIdentity: InMemoryDeviceIdentityStore(UUID()), settings: settings)
        let model = makeModel(sync: sync)
        XCTAssertTrue(model.isOwner)
        model.finishOnboarding()
        return model
    }

    func testSelectingTheFamilyTabRefreshesTheDashboard() async throws {
        let backend = InMemoryCloudBackend()
        let model = try await makeOwnerModel(backend: backend)
        XCTAssertNil(model.dashboard)
        let before = await backend.fetchCount

        model.selectedTab = .family
        await model.familyTabRefresh?.value
        let afterOpen = await backend.fetchCount
        XCTAssertEqual(afterOpen, before + 1, "opening the tab fetches")
        XCTAssertNotNil(model.dashboard)
        XCTAssertNil(model.dashboardMessage)

        // Setting the same tab again is not "opening" it.
        model.familyTabRefresh = nil
        model.selectedTab = .family
        XCTAssertNil(model.familyTabRefresh)

        // Leaving and coming back fetches again.
        model.selectedTab = .home
        model.selectedTab = .family
        await model.familyTabRefresh?.value
        let afterReturn = await backend.fetchCount
        XCTAssertEqual(afterReturn, before + 2)
    }

    func testFamilyTabRefreshNeedsOwnerMode() {
        let model = makeModel()
        XCTAssertFalse(model.isOwner)
        model.selectedTab = .family
        XCTAssertNil(model.familyTabRefresh)
    }

    func testDemoFamilyTabKeepsItsSampleDashboard() {
        let model = AppModel.demo(.familyTab, platform: .mac)
        let sample = model.dashboard
        model.selectedTab = .home
        model.selectedTab = .family
        XCTAssertNil(model.familyTabRefresh)
        XCTAssertEqual(model.dashboard, sample)
    }

    func testCommandRRefreshesTheDashboardOnTheFamilyTab() async throws {
        let backend = InMemoryCloudBackend()
        let model = try await makeOwnerModel(backend: backend)

        XCTAssertEqual(model.selectedTab, .home)
        XCTAssertFalse(model.refreshesDashboard, "Home: ⌘R checks again")
        let start = await backend.fetchCount
        await model.refreshCurrentTab()
        let afterHome = await backend.fetchCount
        XCTAssertEqual(afterHome, start)
        XCTAssertNotNil(model.lastCheckedAt, "the checks ran")

        model.selectedTab = .family
        await model.familyTabRefresh?.value
        XCTAssertTrue(model.refreshesDashboard)
        let opened = await backend.fetchCount
        await model.refreshCurrentTab()
        let afterFamily = await backend.fetchCount
        XCTAssertEqual(afterFamily, opened + 1, "Family tab: ⌘R calls refreshDashboard")
        XCTAssertFalse(model.isRefreshingCurrentTab)
    }

    func testDashboardChipFollowsTheComputedTier() {
        let today = day
        func device(_ checks: [(CheckID, Status, Tier)]) -> DashboardDevice {
            DashboardDevice(
                deviceID: UUID(), label: nil, platform: .ios, enrolledOn: today, lastReport: today, appBuild: 1,
                catalogVersion: 1, daysSinceReport: 0, staleness: .fresh,
                worstStatus: Status.worst(of: checks.map(\.1)),
                checks: checks.map {
                    DashboardCheck(checkID: $0.0, status: $0.1, reportedStatus: $0.1, source: .measured,
                                   checkedOn: today, writtenBySomeoneElse: false, tier: $0.2)
                },
                creatorMismatch: false)
        }
        XCTAssertEqual(DashboardCopy.chip(device([(.osPatched, .fail, .red)])), .today)
        XCTAssertEqual(DashboardCopy.chip(device([(.osPatched, .fail, .amber)])), .toDo)
        XCTAssertEqual(DashboardCopy.chip(device([(.osPatched, .pass, .red)])), .done)
        let red = device([(.osPatched, .fail, .red)]).checks[0]
        XCTAssertEqual(DashboardCopy.appearance(red), .today, "device detail row is red too")
    }
}

/// Notification permission as the system would answer it.
final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorized = false
    private var _requests = 0
    private let grants: Bool

    init(grants: Bool) { self.grants = grants }

    var authorized: Bool {
        get { lock.withLock { _authorized } }
        set { lock.withLock { _authorized = newValue } }
    }
    var requests: Int { lock.withLock { _requests } }

    func isAuthorized() async -> Bool { authorized }
    func requestAuthorization() async -> Bool {
        lock.withLock {
            _requests += 1
            if grants { _authorized = true }
            return _authorized
        }
    }
    private var _pending: Set<String> = []
    /// Requests scheduled and not cancelled (delivered ones stay, like a delayed trigger).
    var pending: Set<String> { lock.withLock { _pending } }

    func schedule(_ notification: PlannedNotification) async throws {
        _ = lock.withLock { _pending.insert(notification.identifier) }
    }
    func cancel(identifiers: [String]) async {
        lock.withLock { _pending.subtract(identifiers) }
    }
}

/// Holds `measure()` until the test opens it.
actor MeasureGate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        open = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
