import XCTest
@testable import ShieldCore

final class SelfReportStoreTests: XCTestCase {
    let catalog = CatalogLintTests.catalog
    let day0 = DateDay(year: 2026, month: 10, day: 22)!

    func makeStore(_ persistence: any LocalStatePersistence, platform: Platform = .ios, clock: Clock? = nil) -> SelfReportStore {
        SelfReportStore(persistence: persistence, pacing: Pacing(catalog: catalog, platform: platform),
                        clock: clock ?? .fixed(day0.date))
    }

    func testRecordStampsTheDayAndPersists() throws {
        let persistence = InMemoryPersistence()
        let store = makeStore(persistence)
        XCTAssertTrue(store.record(.didIt, for: .check(.recoveryContact)))
        XCTAssertEqual(store.report(for: .check(.recoveryContact)), SelfReport(answer: .didIt, answeredOn: day0))
        store.setSelectedServices([.gmail, .ssa])
        store.setCarrier(.verizon)
        store.setDoItAllNow(true)

        let reopened = makeStore(persistence)
        XCTAssertEqual(reopened.current, store.current)
        XCTAssertEqual(reopened.current.selectedServices, [.gmail, .ssa])
        XCTAssertEqual(reopened.current.carrier, .verizon)
        XCTAssertTrue(reopened.current.doItAllNow)
        XCTAssertTrue(reopened.current.accountsPickerDone)
        XCTAssertEqual(reopened.current.firstRunOn, day0)
    }

    func testRejectsKeysThatAreNotSelfChecks() {
        let store = makeStore(InMemoryPersistence())
        XCTAssertFalse(store.record(.didIt, for: .check(.passcodeSet)), "measured")
        XCTAssertFalse(store.record(.didIt, for: .check(.accountsEmail)), "rollups are computed")
        XCTAssertFalse(store.record(.didIt, for: .check(.filevault)), "not on iOS")
        XCTAssertFalse(store.record(.didIt, for: .check(.lockdown)), "optional")
        XCTAssertFalse(store.record(.didIt, for: .accountStep(.irsIPPin, .sessions)), "step doesn't apply")
        XCTAssertTrue(store.record(.didIt, for: .accountStep(.irsIPPin, .checkup)))
        XCTAssertEqual(store.current.answers.count, 1)
    }

    func testClearAndEraseAll() {
        let persistence = InMemoryPersistence()
        let store = makeStore(persistence)
        store.record(.notSure, for: .check(.findMy))
        store.clearAnswer(for: .check(.findMy))
        XCTAssertNil(store.report(for: .check(.findMy)))
        store.record(.notSure, for: .check(.findMy))
        store.eraseAll()
        XCTAssertEqual(store.current, SelfReportState())
        XCTAssertNil(persistence.load())
    }

    func testCorruptDataStartsFresh() {
        let store = makeStore(InMemoryPersistence(Data("not json".utf8)))
        XCTAssertEqual(store.current, SelfReportState())
        XCTAssertTrue(store.record(.didIt, for: .check(.findMy)))
    }

    func testLenientDecodingDropsUnknownValues() throws {
        let json = """
        {"version": 1,
         "answers": {"check.find_my": {"answer": "didIt", "answeredOn": "2026-10-01"},
                     "check.nope": {"answer": "didIt", "answeredOn": "2026-10-01"},
                     "account.gmail.2fa": {"answer": "maybe", "answeredOn": "2026-10-01"}},
         "selectedServices": ["gmail", "myspace"], "carrier": "sprint", "groupCompletedOn": {"1": "2026-10-02", "x": "2026-10-02"},
         "serviceIntroducedOn": {"gmail": "2026-10-05", "myspace": "2026-10-05"}}
        """
        let state = try JSONDecoder().decode(SelfReportState.self, from: Data(json.utf8))
        XCTAssertEqual(Array(state.answers.keys), ["check.find_my"])
        XCTAssertEqual(state.selectedServices, [.gmail])
        XCTAssertNil(state.carrier)
        XCTAssertEqual(state.groupCompletedOn, [1: DateDay(year: 2026, month: 10, day: 2)!])
        XCTAssertEqual(state.serviceIntroducedOn, [.gmail: DateDay(year: 2026, month: 10, day: 5)!])
    }

    func testFilePersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fs-selfreports-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FilePersistence(url: directory.appendingPathComponent("state.json"))
        let store = makeStore(persistence)
        store.record(.notNow, for: .check(.screenUnknown))
        let reopened = makeStore(persistence)
        XCTAssertEqual(reopened.report(for: .check(.screenUnknown))?.answer, .notNow)
        persistence.erase()
        XCTAssertNil(persistence.load())
    }

    func testSelfReportKeyRawValues() {
        let keys: [SelfReportKey] = [.check(.carrierLock), .accountStep(.icloudMail, .twoFactor), .accountStep(.brokerage, .trustedContact)]
        for key in keys {
            XCTAssertEqual(SelfReportKey(rawValue: key.rawValue), key)
        }
        XCTAssertEqual(SelfReportKey.accountStep(.icloudMail, .twoFactor).rawValue, "account.icloud_mail.2fa")
        XCTAssertNil(SelfReportKey(rawValue: "check.gmail"))
        XCTAssertNil(SelfReportKey(rawValue: "account.gmail"))
        XCTAssertNil(SelfReportKey(rawValue: "account.gmail.2fa.extra"))
        XCTAssertNil(SelfReportKey(rawValue: ""))
    }

    func testExpiryBoundary() {
        let report = SelfReport(answer: .didIt, answeredOn: day0)
        XCTAssertFalse(report.isExpired(on: day0.adding(days: 89)))
        XCTAssertTrue(report.isExpired(on: day0.adding(days: 90)))
    }

    func testRefreshRecordsFirstRunOnce() {
        let clock = TestClock(day: day0)
        let store = makeStore(InMemoryPersistence(), clock: clock.clock)
        store.refresh()
        clock.advance(days: 5)
        store.refresh()
        XCTAssertEqual(store.current.firstRunOn, day0)
    }

    func testStoredStateHoldsNoFreeText() throws {
        let persistence = InMemoryPersistence()
        let store = makeStore(persistence)
        store.record(.didIt, for: .check(.familyCodeWord))
        store.setCarrier(.att)
        // Only enum values and days are representable: there is no API that accepts a string.
        let decoded = try JSONSerialization.jsonObject(with: XCTUnwrap(persistence.load())) as? [String: Any]
        XCTAssertEqual(Set((decoded ?? [:]).keys), [
            "version", "answers", "selectedServices", "accountsPickerDone", "carrier", "doItAllNow",
            "firstRunOn", "groupCompletedOn", "serviceIntroducedOn",
        ])
    }
}
