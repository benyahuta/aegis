import XCTest
@testable import ShieldCore

/// SPEC §13.1 StatusEngineTests: pacing unlocks; 90-day re-ask; "Not sure" → unknown;
/// reminder count (1 + 1); account rollups (all done → pass, none picked → unknown,
/// "Not now" 14 days → fail). Plus Home state, Next-step ordering and the sync payload.
final class StatusEngineTests: XCTestCase {
    let catalog = CatalogLintTests.catalog
    let day0 = DateDay(year: 2026, month: 10, day: 22)!
    var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock(day: day0)
    }

    func engine(_ platform: Platform = .ios, major: Int = 26, priorities: Set<Priority> = [.p0]) -> StatusEngine {
        StatusEngine(catalog: catalog, platform: platform, osMajor: major, includedPriorities: priorities, clock: clock.clock)
    }

    func store(_ platform: Platform = .ios, persistence: InMemoryPersistence = InMemoryPersistence()) -> SelfReportStore {
        SelfReportStore(persistence: persistence, pacing: Pacing(catalog: catalog, platform: platform), clock: clock.clock)
    }

    /// Every P0 family measured check passes.
    func allPass(_ platform: Platform = .ios) -> [MeasuredResult] {
        DemoState.firstRun.measured(catalog: catalog, platform: platform, today: clock.clock.today())
    }

    func answerGroup(_ group: Int, _ answer: SelfAnswer, in store: SelfReportStore, platform: Platform = .ios) {
        for id in Pacing(catalog: catalog, platform: platform).selfChecks(inGroup: group) {
            XCTAssertTrue(store.record(answer, for: .check(id)), id.rawValue)
        }
    }

    func item(_ snapshot: StatusSnapshot, _ id: CheckID) -> StatusItem? {
        snapshot.familyItems.first { $0.id == .check(id) }
    }

    func synced(_ snapshot: StatusSnapshot, _ id: CheckID) -> Status? {
        snapshot.synced.first { $0.checkID == id }?.status
    }

    // MARK: Pacing

    func testFirstRunShowsOnlyGroupOne() {
        let snapshot = engine().evaluate(measured: allPass(), selfReports: SelfReportState())
        XCTAssertEqual(snapshot.unlockedGroups, [1])
        let shownSelf = Set(snapshot.familyItems.filter { $0.kind == .selfCheck }.map(\.checkID))
        XCTAssertEqual(shownSelf, [.autoUpdates, .stolenDeviceProtection, .recoveryContact, .screenUnknown, .findMy, .familyCodeWord])
        XCTAssertEqual(snapshot.home.count, 6)
        XCTAssertEqual(snapshot.home.headline, "6 things to do")
        XCTAssertEqual(snapshot.home.laterText, "5 more for later")
        XCTAssertNil(snapshot.nextUnlockDay)
        // Locked group-2 checks still sync, as unknown.
        XCTAssertEqual(synced(snapshot, .carrierLock), .unknown)
        XCTAssertEqual(synced(snapshot, .creditFreezeEquifax), .unknown)
    }

    func testGroupTwoUnlocksThreeDaysAfterGroupOneIsAnswered() {
        let store = store()
        store.refresh()
        clock.advance(days: 1)
        answerGroup(1, .didIt, in: store)
        XCTAssertEqual(store.current.groupCompletedOn[1], day0.adding(days: 1))

        clock.advance(days: 2) // day 3: only 2 days after answering
        var snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(snapshot.unlockedGroups, [1])
        XCTAssertEqual(snapshot.home, .protected)
        XCTAssertEqual(snapshot.nextUnlockDay, day0.adding(days: 4))

        clock.advance(days: 1) // day 4
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(snapshot.unlockedGroups, [1, 2])
        XCTAssertEqual(Set(snapshot.toDo.map(\.checkID)), [.carrierLock, .creditFreezeEquifax, .creditFreezeExperian, .creditFreezeTransunion])
    }

    func testAnyAnswerCountsAsAnsweredForPacing() {
        let store = store()
        answerGroup(1, .notNow, in: store)
        clock.advance(days: 3)
        XCTAssertTrue(engine().evaluate(measured: allPass(), selfReports: store.refresh()).unlockedGroups.contains(2))
    }

    func testPartiallyAnsweredGroupDoesNotUnlock() {
        let store = store()
        store.record(.didIt, for: .check(.familyCodeWord))
        clock.advance(days: 10)
        XCTAssertEqual(engine().evaluate(measured: allPass(), selfReports: store.refresh()).unlockedGroups, [1])
    }

    func testPickedAccountsShowUpRightAway() throws {
        let store = store()
        // Nothing picked: no account items, group 3 stays locked on day 0.
        var snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertFalse(snapshot.unlockedGroups.contains(3))
        XCTAssertTrue(snapshot.familyItems.allSatisfy { $0.service == nil })

        // Picking accounts on day 0, before groups 1 and 2 are done, shows every picked service.
        store.setSelectedServices([.gmail, .bank, .facebook])
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertTrue(snapshot.unlockedGroups.contains(3))
        XCTAssertEqual(Set(snapshot.familyItems.compactMap(\.service)), [.gmail, .bank, .facebook])
        XCTAssertEqual(store.current.serviceIntroducedOn.count, 3)

        // Answering Gmail leaves the other two to do; group 2 is still paced.
        let gmail = try XCTUnwrap(Services.service(.gmail))
        for step in gmail.steps { store.record(.didIt, for: .accountStep(.gmail, step)) }
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(Set(snapshot.toDo.compactMap(\.service)), [.bank, .facebook])
        XCTAssertFalse(snapshot.unlockedGroups.contains(2))

        // A service picked later shows up the same day.
        store.setSelectedServices([.gmail, .bank, .facebook, .amazon])
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertTrue(snapshot.toDo.contains { $0.service == .amazon })
    }

    func testDoItAllNowUnlocksEverything() {
        let store = store()
        store.setSelectedServices([.gmail, .bank, .facebook, .ssa])
        store.setDoItAllNow(true)
        let snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(snapshot.unlockedGroups, [1, 2, 3])
        XCTAssertEqual(Set(snapshot.toDo.compactMap(\.service)), [.gmail, .bank, .facebook, .ssa])
        XCTAssertTrue(snapshot.toDo.contains { $0.checkID == .carrierLock })
        // Turning it off keeps what was already introduced.
        store.setDoItAllNow(false)
        XCTAssertEqual(store.current.serviceIntroducedOn.count, 4)
    }

    func testReaskDoesNotRelockGroups() {
        let store = store()
        answerGroup(1, .didIt, in: store)
        clock.advance(days: 3)
        store.refresh()
        clock.advance(days: 100) // group-1 answers expired
        let snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertTrue(snapshot.unlockedGroups.contains(2))
    }

    func testMacPacingUsesMacSelfChecks() {
        let store = store(.mac)
        let snapshot = engine(.mac).evaluate(measured: allPass(.mac), selfReports: store.refresh())
        let selfItems = Set(snapshot.familyItems.filter { $0.kind == .selfCheck }.map(\.checkID))
        XCTAssertEqual(selfItems, [.recoveryContact, .familyCodeWord])
        XCTAssertFalse(store.record(.didIt, for: .check(.stolenDeviceProtection)), "iOS-only self-check")
        XCTAssertFalse(store.record(.didIt, for: .check(.filevault)), "measured, not a self-check")
        XCTAssertEqual(snapshot.home.menuBarWord, "2 to do")
    }

    // MARK: Self-report semantics

    func testNotSureIsUnknownOnTheWireButAmberLocally() throws {
        let store = store()
        store.record(.notSure, for: .check(.stolenDeviceProtection))
        let snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        let sdp = try XCTUnwrap(item(snapshot, .stolenDeviceProtection))
        XCTAssertEqual(sdp.status, .unknown)
        XCTAssertEqual(sdp.answer, .notSure)
        XCTAssertEqual(sdp.tier, .amber)
        XCTAssertTrue(sdp.needsAction)
        XCTAssertEqual(sdp.appearanceStatus, .fail, "drawn as To do (amber)")
        XCTAssertEqual(sdp.messageKey, "selfcheck.notSure.response")
        XCTAssertEqual(synced(snapshot, .stolenDeviceProtection), .unknown)
        let result = try XCTUnwrap(snapshot.results(deviceID: UUID()).first { $0.checkID == .stolenDeviceProtection })
        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.source, .selfReported)
    }

    func testDidItPassesAndNotNowFails() {
        let store = store()
        store.record(.didIt, for: .check(.recoveryContact))
        store.record(.notNow, for: .check(.screenUnknown))
        let snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .recoveryContact), .pass)
        XCTAssertEqual(synced(snapshot, .screenUnknown), .fail)
        XCTAssertFalse(item(snapshot, .recoveryContact)!.needsAction)
        XCTAssertTrue(item(snapshot, .screenUnknown)!.deferred)
        XCTAssertEqual(snapshot.toDo.last?.checkID, .screenUnknown, "Not now sorts last")
    }

    func testCodeWordAnswers() throws {
        let variant = try XCTUnwrap(catalog.variant(.familyCodeWord, platform: .ios))
        XCTAssertEqual(variant.answerOptions.map(\.answer), [.didIt, .notNow])
        XCTAssertEqual(variant.answerOptions.map { ShieldStrings.text($0.labelKey) }, ["We have one", "Not yet"])
    }

    func testNinetyDayReask() throws {
        let store = store()
        store.record(.didIt, for: .check(.findMy))
        clock.advance(days: 89)
        var snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .findMy), .pass)
        XCTAssertFalse(try XCTUnwrap(item(snapshot, .findMy)).needsReask)

        clock.advance(days: 1) // day 90
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        let findMy = try XCTUnwrap(item(snapshot, .findMy))
        XCTAssertEqual(findMy.status, .unknown)
        XCTAssertNil(findMy.answer)
        XCTAssertTrue(findMy.needsReask)
        XCTAssertTrue(findMy.needsAction)
        XCTAssertEqual(findMy.messageKey, "selfcheck.reask")
        XCTAssertEqual(synced(snapshot, .findMy), .unknown)

        store.record(.didIt, for: .check(.findMy))
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .findMy), .pass)
    }

    // MARK: Account rollups (§6.4)

    func testRollupNonePickedIsUnknown() {
        let snapshot = engine().evaluate(measured: allPass(), selfReports: SelfReportState())
        for id in CheckID.accountRollups {
            XCTAssertEqual(synced(snapshot, id), .unknown, id.rawValue)
        }
    }

    func testRollupAllDoneIsPass() throws {
        let store = store()
        store.setSelectedServices([.gmail, .outlook])
        for key in [ServiceKey.gmail, .outlook] {
            for step in try XCTUnwrap(Services.service(key)).steps { store.record(.didIt, for: .accountStep(key, step)) }
        }
        let snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .accountsEmail), .pass)
        XCTAssertEqual(synced(snapshot, .accountsMoney), .unknown, "none picked")
        XCTAssertEqual(snapshot.accounts.first { $0.category == .email }?.status, .pass)
    }

    func testRollupPartialOrNotSureIsUnknown() throws {
        let store = store()
        store.setSelectedServices([.gmail])
        let steps = try XCTUnwrap(Services.service(.gmail)).steps
        for step in steps.dropLast() { store.record(.didIt, for: .accountStep(.gmail, step)) }
        var snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .accountsEmail), .unknown)
        store.record(.notSure, for: .accountStep(.gmail, steps.last!))
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .accountsEmail), .unknown)
    }

    func testServiceStepProgressCarriesCopyAndWhyKeys() throws {
        let store = store()
        store.setSelectedServices([.bank])
        let snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        let bank = try XCTUnwrap(snapshot.accounts.first { $0.category == .money }?.services.first { $0.service.key == .bank })
        let service = bank.service
        XCTAssertEqual(bank.steps.map(\.step), service.steps)
        for step in bank.steps {
            XCTAssertEqual(step.copyKey, service.copyKey(for: step.step))
            XCTAssertEqual(step.whyKey, service.whyKey(for: step.step))
        }
        XCTAssertEqual(bank.steps.first { $0.step == .alerts }?.whyKey, "service.bank.why.alerts")
        XCTAssertEqual(bank.steps.first { $0.step == .twoFactor }?.whyKey, "accounts.why.2fa")
    }

    func testRollupNotNowFailsAfterFourteenDays() throws {
        let store = store()
        store.setSelectedServices([.bank, .paypal])
        for step in try XCTUnwrap(Services.service(.paypal)).steps { store.record(.didIt, for: .accountStep(.paypal, step)) }
        store.record(.notNow, for: .accountStep(.bank, .twoFactor))
        clock.advance(days: 13)
        var snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .accountsMoney), .unknown, "13 days: not yet")
        clock.advance(days: 1)
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .accountsMoney), .fail, "14 days: fail")
    }

    func testRollupIncludesLinkedChecks() throws {
        let store = store()
        store.setSelectedServices([.amazon, .carrierAccount])
        for key in [ServiceKey.amazon, .carrierAccount] {
            for step in try XCTUnwrap(Services.service(key)).steps { store.record(.didIt, for: .accountStep(key, step)) }
        }
        var snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .accountsShopping), .unknown, "carrier_lock not answered yet")
        store.record(.didIt, for: .check(.carrierLock))
        snapshot = engine().evaluate(measured: allPass(), selfReports: store.refresh())
        XCTAssertEqual(synced(snapshot, .accountsShopping), .pass)
    }

    func testAccountStepsExpireAfterNinetyDays() throws {
        let store = store()
        store.setSelectedServices([.irsIPPin])
        store.record(.didIt, for: .accountStep(.irsIPPin, .checkup))
        XCTAssertEqual(synced(engine().evaluate(measured: allPass(), selfReports: store.refresh()), .accountsGovernment), .pass)
        clock.advance(days: 90)
        XCTAssertEqual(synced(engine().evaluate(measured: allPass(), selfReports: store.refresh()), .accountsGovernment), .unknown)
    }

    func testServiceNamesNeverSync() throws {
        let store = store()
        store.setSelectedServices(Set(ServiceKey.allCases))
        store.setDoItAllNow(true)
        let results = engine().evaluate(measured: allPass(), selfReports: store.refresh()).results(deviceID: UUID())
        for result in results {
            XCTAssertNil(ServiceKey(rawValue: result.checkID.rawValue))
            XCTAssertTrue(CheckResult.isValidRecordName(result.recordName))
        }
        let ids = results.map(\.checkID)
        XCTAssertEqual(Set(ids).count, ids.count, "one result per check")
        XCTAssertTrue(Set(CheckID.accountRollups).isSubset(of: Set(ids)))
    }

    // MARK: Measured results, Home and ordering

    func testProtectedWhenNothingRedOrAmber() {
        let state = DemoState.protected.selfReports(catalog: catalog, platform: .ios, today: day0)
        let snapshot = engine().evaluate(measured: allPass(), selfReports: state)
        XCTAssertEqual(snapshot.home, .protected)
        XCTAssertEqual(snapshot.home.headline, "You're protected. Nothing to do.")
        XCTAssertEqual(snapshot.home.menuBarWord, "Protected")
        XCTAssertTrue(snapshot.toDo.isEmpty)
    }

    func testBeforeTheFirstMeasurementNothingIsProtected() {
        // H7: `measured: nil` (cold launch, checks still running) is not "all measured checks pass".
        for platform in [Platform.ios, .mac] {
            let state = DemoState.protected.selfReports(catalog: catalog, platform: platform, today: day0)
            let pending = engine(platform).evaluate(measured: nil, selfReports: state)
            XCTAssertEqual(pending.home, .checking, "\(platform)")
            XCTAssertTrue(pending.measurementPending)
            XCTAssertEqual(pending.home.count, 0)
            XCTAssertNil(pending.home.nextStep)
            XCTAssertNotEqual(pending.home.menuBarWord, "Protected")
            XCTAssertTrue(pending.reminderCandidates.isEmpty)
        }
        // Something to do is still shown while checking (it is true either way).
        let firstRun = engine().evaluate(measured: nil, selfReports: SelfReportState())
        XCTAssertEqual(firstRun.home.nextStep?.checkID, .autoUpdates)
        // A measurement that returned nothing is a measurement: no "Checking" forever.
        let state = DemoState.protected.selfReports(catalog: catalog, platform: .ios, today: day0)
        XCTAssertEqual(engine().evaluate(measured: [], selfReports: state).home, .protected)
        XCTAssertFalse(engine().evaluate(measured: [], selfReports: state).measurementPending)
    }

    func testOneRedIsTheNextStep() throws {
        let state = DemoState.oneRed.selfReports(catalog: catalog, platform: .ios, today: day0)
        let measured = DemoState.oneRed.measured(catalog: catalog, platform: .ios, today: day0)
        let snapshot = engine().evaluate(measured: measured, selfReports: state)
        let next = try XCTUnwrap(snapshot.home.nextStep)
        XCTAssertEqual(next.checkID, .osPatched)
        XCTAssertEqual(next.tier, .red)
        XCTAssertTrue(next.urgent)
        XCTAssertEqual(ShieldStrings.text(next.messageKey), "Please update your iPhone today. Apple fixed a problem that criminals are already using.")
        XCTAssertEqual(snapshot.home.headline, "1 thing to do today.")
        XCTAssertNil(snapshot.home.laterText)
        XCTAssertEqual(snapshot.home.menuBarWord, "Today")
        XCTAssertEqual(next.stepKeys, catalog.variant(.osPatched, platform: .ios)?.steps(forOSMajor: 26))
        XCTAssertEqual(next.deepLink, .iosSettingsHome)
    }

    func testNonExploitedUpdateIsAmberWithNormalCopy() throws {
        var measured = allPass()
        measured.removeAll { $0.checkID == .osPatched }
        measured.append(MeasuredResult(checkID: .osPatched, status: .fail, checkedOn: day0))
        let snapshot = engine().evaluate(measured: measured, selfReports: SelfReportState())
        let osPatched = try XCTUnwrap(item(snapshot, .osPatched))
        XCTAssertEqual(osPatched.tier, .amber)
        XCTAssertEqual(ShieldStrings.text(osPatched.messageKey), "An update with safety fixes is ready.")
        XCTAssertEqual(snapshot.toDo.first?.checkID, .osPatched, "a measured failure comes before unanswered self-checks")
    }

    func testOrderingByUrgency() {
        var measured = allPass()
        measured.removeAll { [.osPatched, .passcodeSet, .biometricsEnrolled].contains($0.checkID) }
        measured += [
            MeasuredResult(checkID: .biometricsEnrolled, status: .fail, checkedOn: day0),
            MeasuredResult(checkID: .osPatched, status: .fail, checkedOn: day0, urgent: true),
            MeasuredResult(checkID: .passcodeSet, status: .fail, checkedOn: day0),
        ]
        let snapshot = engine().evaluate(measured: measured, selfReports: SelfReportState())
        let order = snapshot.toDo.map(\.checkID)
        XCTAssertEqual(Array(order.prefix(3)), [.osPatched, .passcodeSet, .biometricsEnrolled])
        XCTAssertEqual(snapshot.home.count, 3 + 6)
        XCTAssertTrue(snapshot.home.isToday)
    }

    func testUnknownMeasuredIsGreyAndNotCounted() throws {
        var measured = allPass()
        measured.removeAll { $0.checkID == .osPatched }
        measured.append(MeasuredResult(checkID: .osPatched, status: .unknown, checkedOn: day0))
        let state = DemoState.protected.selfReports(catalog: catalog, platform: .ios, today: day0)
        let snapshot = engine().evaluate(measured: measured, selfReports: state)
        let osPatched = try XCTUnwrap(item(snapshot, .osPatched))
        XCTAssertEqual(osPatched.appearanceStatus, .unknown)
        XCTAssertFalse(osPatched.needsAction)
        XCTAssertEqual(ShieldStrings.text(osPatched.messageKey), "Can't confirm. Check Software Update.")
        XCTAssertEqual(snapshot.home, .protected)
    }

    func testMacYellowAndRedRules() throws {
        var measured = allPass(.mac)
        measured.removeAll { [.firewall, .remoteAccessOff, .gatekeeper].contains($0.checkID) }
        measured += [
            MeasuredResult(checkID: .firewall, status: .fail, checkedOn: day0),
            MeasuredResult(checkID: .remoteAccessOff, status: .fail, checkedOn: day0),
        ]
        let state = DemoState.protected.selfReports(catalog: catalog, platform: .mac, today: day0)
        var snapshot = engine(.mac).evaluate(measured: measured, selfReports: state)
        XCTAssertEqual(snapshot.home, .protected, "firewall and remote access are advisory (yellow)")
        XCTAssertEqual(Set(snapshot.suggestions.map(\.checkID)), [.firewall, .remoteAccessOff])

        measured.removeAll { $0.checkID == .remoteAccessOff }
        measured.append(MeasuredResult(checkID: .remoteAccessOff, status: .fail, checkedOn: day0, urgent: true))
        measured.append(MeasuredResult(checkID: .gatekeeper, status: .fail, checkedOn: day0))
        snapshot = engine(.mac).evaluate(measured: measured, selfReports: state)
        XCTAssertEqual(snapshot.toDo.map(\.checkID), [.remoteAccessOff, .gatekeeper].sortedByCatalog(catalog))
        XCTAssertTrue(snapshot.toDo.allSatisfy { $0.tier == .red })
        XCTAssertTrue(try XCTUnwrap(item(snapshot, .gatekeeper)).callBen)
        XCTAssertEqual(snapshot.home.menuBarWord, "Today")
    }

    func testMacStepsFollowOSMajor() throws {
        let measured = [MeasuredResult(checkID: .findMy, status: .fail, checkedOn: day0)]
        let sonoma = try XCTUnwrap(engine(.mac, major: 14).evaluate(measured: measured, selfReports: SelfReportState())
            .familyItems.first { $0.checkID == .findMy })
        let tahoe = try XCTUnwrap(engine(.mac, major: 26).evaluate(measured: measured, selfReports: SelfReportState())
            .familyItems.first { $0.checkID == .findMy })
        XCTAssertTrue(ShieldStrings.plain(sonoma.stepKeys[0]).contains("Show More Apps"))
        XCTAssertTrue(ShieldStrings.plain(tahoe.stepKeys[0]).contains("See All"))
        XCTAssertEqual(tahoe.source, .measured)
    }

    func testIPhoneStepsNameTheRightSensor() throws {
        let measured = [MeasuredResult(checkID: .passcodeSet, status: .fail, checkedOn: day0)]
        func firstStep(_ biometry: Biometry) throws -> String {
            let engine = StatusEngine(catalog: catalog, platform: .ios, osMajor: 26, biometry: biometry, clock: clock.clock)
            let item = try XCTUnwrap(engine.evaluate(measured: measured, selfReports: SelfReportState())
                .familyItems.first { $0.checkID == .passcodeSet })
            return ShieldStrings.plain(item.stepKeys[0])
        }
        XCTAssertEqual(try firstStep(.touchID), "Open Settings → Touch ID & Passcode.")
        XCTAssertEqual(try firstStep(.faceID), "Open Settings → Face ID & Passcode.")
        let generic = try firstStep(.unknown)
        XCTAssertTrue(generic.contains("Face ID & Passcode") && generic.contains("Touch ID & Passcode"), generic)
    }

    func testBenOnlyItemsAreHiddenFromTheFamilyButSync() throws {
        var measured = allPass()
        measured.removeAll { $0.checkID == .appBuildFresh }
        measured.append(MeasuredResult(checkID: .appBuildFresh, status: .fail, checkedOn: day0))
        let state = DemoState.protected.selfReports(catalog: catalog, platform: .ios, today: day0)
        let snapshot = engine().evaluate(measured: measured, selfReports: state)
        XCTAssertNil(item(snapshot, .appBuildFresh))
        XCTAssertEqual(snapshot.benOnly.map(\.checkID), [.appBuildFresh])
        XCTAssertTrue(snapshot.showBuildAgeBanner)
        XCTAssertEqual(snapshot.home, .protected)
        XCTAssertEqual(synced(snapshot, .appBuildFresh), .fail)
    }

    func testOptionalItemsNeverFailNeverSyncAndAreDeduplicated() {
        var measured = allPass(.mac)
        measured.append(MeasuredResult(checkID: .lockdown, status: .fail, checkedOn: day0))
        let snapshot = engine(.mac, priorities: [.p0, .p1, .p2]).evaluate(measured: measured, selfReports: SelfReportState())
        XCTAssertEqual(Set(snapshot.optionalLinks.map(\.checkID)), [.lockdown, .advancedDataProtection], "adp folds into advanced_data_protection")
        XCTAssertTrue(snapshot.optionalLinks.allSatisfy { !$0.needsAction && $0.status == .unknown })
        for id in CheckID.neverFails { XCTAssertNil(synced(snapshot, id), id.rawValue) }

        let p0 = engine(.mac).evaluate(measured: allPass(.mac), selfReports: SelfReportState())
        XCTAssertEqual(Set(p0.optionalLinks.map(\.checkID)), [.lockdown, .adp])
    }

    func testResultsPayloadUsesDeviceAndCatalogVersion() throws {
        let device = UUID()
        let snapshot = engine().evaluate(measured: allPass(), selfReports: SelfReportState())
        let results = snapshot.results(deviceID: device)
        XCTAssertFalse(results.isEmpty)
        let info = DeviceInfo(deviceID: device, platform: .ios, enrolledOn: day0, catalogVersion: catalog.version, appBuild: 1, lastReport: day0)
        XCTAssertNoThrow(try validateForSink(device: info, results: results))
        XCTAssertTrue(results.allSatisfy { $0.catalogVersion == catalog.version && $0.deviceID == device })
        XCTAssertEqual(results.first { $0.checkID == .osPatched }?.source, .measured)
        XCTAssertEqual(results.first { $0.checkID == .osPatched }?.status, .pass)
    }

    func testDuplicateMeasurementsKeepTheNewest() {
        let measured = [
            MeasuredResult(checkID: .passcodeSet, status: .fail, checkedOn: day0.adding(days: -1)),
            MeasuredResult(checkID: .passcodeSet, status: .pass, checkedOn: day0),
        ]
        let snapshot = engine().evaluate(measured: measured, selfReports: SelfReportState())
        XCTAssertEqual(synced(snapshot, .passcodeSet), .pass)
    }

    func testEvaluateIsPureForTheSameDay() {
        let state = DemoState.accounts.selfReports(catalog: catalog, platform: .ios, today: day0)
        let a = engine().evaluate(measured: allPass(), selfReports: state)
        let b = engine().evaluate(measured: allPass(), selfReports: state)
        XCTAssertEqual(a.toDo, b.toDo)
        XCTAssertEqual(a.synced, b.synced)
        XCTAssertEqual(a.selfReports, b.selfReports)
    }

    func testEmptyCatalogNeverCrashesAndIsNeverGreen() {
        let empty = StatusEngine(catalog: CheckCatalog(version: 0, entries: []), platform: .ios, osMajor: 26, clock: clock.clock)
        let snapshot = empty.evaluate(measured: allPass(), selfReports: SelfReportState())
        XCTAssertTrue(snapshot.synced.isEmpty)
        XCTAssertTrue(snapshot.familyItems.isEmpty)
    }

    func testDemoStatesEvaluate() {
        for demo in DemoState.allCases {
            for platform in Platform.allCases {
                let snapshot = engine(platform).evaluate(
                    measured: demo.measured(catalog: catalog, platform: platform, today: day0),
                    selfReports: demo.selfReports(catalog: catalog, platform: platform, today: day0))
                switch demo {
                case .protected: XCTAssertEqual(snapshot.home, .protected, "\(demo) \(platform)")
                case .oneRed: XCTAssertTrue(snapshot.home.isToday, "\(demo) \(platform)")
                case .firstRun: XCTAssertGreaterThan(snapshot.home.count, 0)
                case .accounts: XCTAssertTrue(snapshot.unlockedGroups.contains(3))
                }
            }
        }
        XCTAssertEqual(DemoState(options: LaunchOptions(arguments: ["-FSDemoState", "oneRed"])), .oneRed)
        XCTAssertNil(DemoState(options: LaunchOptions(arguments: ["-FSDemoState", "nope"])))
    }

    // MARK: Reminders through the engine (1 + 1)

    func testReminderCountIsOnePlusOne() async {
        let scheduler = RecordingScheduler(authorized: true)
        let notifier = LocalNotifier(scheduler: scheduler, persistence: InMemoryPersistence(), clock: clock.clock)
        let measured = DemoState.oneRed.measured(catalog: catalog, platform: .ios, today: day0)
        let state = DemoState.oneRed.selfReports(catalog: catalog, platform: .ios, today: day0)
        for _ in 0..<5 {
            await notifier.update(with: engine().evaluate(measured: measured, selfReports: state))
            clock.advance(days: 1)
        }
        let scheduled = await scheduler.scheduled
        XCTAssertEqual(scheduled.map(\.kind), [.first, .reminder])
        XCTAssertEqual(scheduled.last?.delay, 3 * 86_400)
        let asked = await scheduler.requestCount
        XCTAssertEqual(asked, 0, "updates never ask for permission")
    }

    func testSelfChecksAndGreenNeverNotify() {
        let snapshot = engine().evaluate(measured: allPass(), selfReports: SelfReportState())
        XCTAssertTrue(snapshot.reminderCandidates.isEmpty, "unanswered self-checks and passes never notify")
    }
}
