import LocalAuthentication
import XCTest
@testable import ShieldCore

/// BuildInfo, CallBenStore, DeviceAuthCheck and the measured-result adapters used by the apps.
final class UISupportTests: XCTestCase {
    private let today = DateDay(year: 2026, month: 10, day: 22)!

    // MARK: app_build_fresh (§6.1)

    func testBuildAge() {
        let fresh = BuildInfo(version: "1.0", build: 3, buildDay: today.adding(days: -59))
        XCTAssertEqual(fresh.freshStatus(today: today), .pass)
        let old = BuildInfo(version: "1.0", build: 3, buildDay: today.adding(days: -60))
        XCTAssertEqual(old.freshStatus(today: today), .fail)
        XCTAssertEqual(old.measuredResult(today: today).checkID, .appBuildFresh)
        let unknown = BuildInfo(version: "1.0", build: 3, buildDay: nil)
        XCTAssertEqual(unknown.freshStatus(today: today), .unknown, "H7: no build date is never a pass")
        XCTAssertNil(unknown.ageDays(today: today))
    }

    func testBuildDayPrefersInfoPlistStamp() {
        XCTAssertEqual(BuildInfo.resolveBuildDay(info: ["FSBuildDate": "2026-09-01"], executable: nil),
                       DateDay(year: 2026, month: 9, day: 1))
        XCTAssertNil(BuildInfo.resolveBuildDay(info: ["FSBuildDate": "junk"], executable: nil))
    }

    // MARK: Who to call (§10.1 3)

    func testCallBenNumberKeepsDigitsAndPlus() {
        XCTAssertEqual(CallBenNumber.clean(" +1 (415) 555-0100 "), "+14155550100")
        XCTAssertEqual(CallBenNumber.clean("415.555.0100"), "4155550100")
        XCTAssertNil(CallBenNumber.clean("12"))
        XCTAssertNil(CallBenNumber.clean("call me"))
        XCTAssertNil(CallBenNumber.clean(String(repeating: "1", count: 16)))
    }

    func testCallBenNumberStopsAtAPauseOrExtension() {
        // Contacts keeps numbers as typed; joining the extension's digits dials someone else.
        for (raw, expected) in [
            ("(555) 123-4567,890", "5551234567"),
            ("555-123-4567;12", "5551234567"),
            ("555-123-4567 ext. 12", "5551234567"),
            ("555-123-4567 Ext 12", "5551234567"),
            ("+1 555 123 4567 x12", "+15551234567"),
            ("555-123-4567 extension: 9", "5551234567"),
            ("555-123-4567#22", "5551234567"),
            ("+44 20 7946 0958", "+442079460958"),
        ] {
            XCTAssertEqual(CallBenNumber.clean(raw), expected, raw)
            XCTAssertEqual(OfficialLinks.telURL(raw)?.absoluteString, "tel:" + expected, raw)
        }
        // Letters that aren't an extension can't become digits safely.
        XCTAssertNil(CallBenNumber.clean("1-800-FLOWERS"))
        XCTAssertNil(CallBenNumber.clean(",5551234567"), "nothing before the pause")
    }

    func testInMemoryStore() {
        let store = InMemoryCallBenStore()
        XCTAssertNil(store.load())
        XCTAssertFalse(store.save("x"))
        XCTAssertTrue(store.save("(415) 555-0100"))
        XCTAssertEqual(store.load(), "4155550100")
        XCTAssertEqual(OfficialLinks.telURL(store.load()!)?.absoluteString, "tel:4155550100")
        store.clear()
        XCTAssertNil(store.load())
    }

    // MARK: passcode_set / biometrics_enrolled (§6.1)

    func testPasscodeMapping() {
        XCTAssertEqual(DeviceAuthCheck.passcodeStatus(canEvaluate: true, errorCode: nil), .pass)
        XCTAssertEqual(DeviceAuthCheck.passcodeStatus(canEvaluate: false, errorCode: .passcodeNotSet), .fail)
        XCTAssertEqual(DeviceAuthCheck.passcodeStatus(canEvaluate: false, errorCode: .notInteractive), .unknown)
        XCTAssertEqual(DeviceAuthCheck.passcodeStatus(canEvaluate: false, errorCode: nil), .unknown)
    }

    func testBiometricsMapping() {
        XCTAssertEqual(DeviceAuthCheck.biometricsStatus(canEvaluate: true, errorCode: nil), .pass)
        XCTAssertEqual(DeviceAuthCheck.biometricsStatus(canEvaluate: false, errorCode: .biometryNotEnrolled), .fail)
        XCTAssertEqual(DeviceAuthCheck.biometricsStatus(canEvaluate: false, errorCode: .biometryNotAvailable), .unknown)
        XCTAssertEqual(DeviceAuthCheck.biometricsStatus(canEvaluate: false, errorCode: .passcodeNotSet), .unknown)
    }

    // MARK: Version → StatusEngine

    func testExploitedUpdateIsUrgent() {
        let evaluator = VersionEvaluator()
        let input = VersionEvaluator.Input(platform: .ios, osVersion: OSVersion(26, 5, 1),
                                           device: DeviceIdentifier(modelIdentifier: "iPhone17,1"), feed: nil,
                                           now: today.date)
        let results = evaluator.evaluate(input).measuredResults(today: today)
        XCTAssertEqual(results.map(\.checkID), [.osPatched, .deviceSupported])
        XCTAssertEqual(results[0].status, .fail)
        XCTAssertTrue(results[0].urgent, "26.5.1 is below the exploited 26.7.1 fix (CVE-2026-86950)")
    }

    func testPatchedIsNotUrgent() {
        let input = VersionEvaluator.Input(platform: .ios, osVersion: OSVersion(27, 0, 1),
                                           device: DeviceIdentifier(modelIdentifier: "iPhone17,1"), feed: nil,
                                           now: today.date)
        let results = VersionEvaluator().evaluate(input).measuredResults(today: today)
        XCTAssertFalse(results[0].urgent)
        XCTAssertNotEqual(results[0].status, .fail)
    }

    func testMacOutcomeRedOverrideIsUrgent() {
        let red = MacCheckOutcome(checkID: .remoteAccessOff, status: .fail, note: .measured, tierOverride: .red)
        XCTAssertTrue(red.measuredResult(today: today).urgent)
        let yellow = MacCheckOutcome(checkID: .firewall, status: .fail, note: .measured)
        XCTAssertFalse(yellow.measuredResult(today: today).urgent)
        let passing = MacCheckOutcome(checkID: .osPatched, status: .pass, note: .measured, tierOverride: .red)
        XCTAssertFalse(passing.measuredResult(today: today).urgent)
    }
}

/// §10.3: the scam-corpus numbers baked into the build must match the corpus and rules.
final class ScamCorpusStatsTests: XCTestCase {
    func testBakedNumbersMatchTheCorpus() throws {
        let scams = try ScamCorpusTests.load("scam_corpus", as: ScamCorpusTests.ScamCase.self).filter(\.clear)
        let benign = try ScamCorpusTests.load("benign_corpus", as: ScamCorpusTests.BenignCase.self)
        XCTAssertEqual(scams.count, ScamCorpusStats.clearScamsTotal)
        XCTAssertEqual(scams.filter { ScamRules.assess($0.text).verdict == .danger }.count, ScamCorpusStats.clearScamsDanger)
        XCTAssertEqual(benign.count, ScamCorpusStats.benignTotal)
        XCTAssertEqual(benign.filter { ScamRules.assess($0.text).verdict != .danger }.count, ScamCorpusStats.benignNotDanger)
    }
}
