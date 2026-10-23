import XCTest
@testable import ShieldCore

/// §8.4 "on the Mac every 24 h and on wake", and the §13.3 smoke-run report format.
final class MacScheduleAndReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_660_440)

    func testLaunchAndNeverCheckedAlwaysRefresh() {
        for trigger in RefreshTrigger.allCases {
            XCTAssertTrue(RefreshPolicy.shouldRefresh(trigger, lastChecked: nil, now: now), trigger.rawValue)
        }
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.launch, lastChecked: now, now: now))
    }

    func testTimerWaitsTwentyFourHours() {
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.timer, lastChecked: now.addingTimeInterval(-23 * 3_600), now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.timer, lastChecked: now.addingTimeInterval(-24 * 3_600), now: now))
        XCTAssertLessThan(RefreshPolicy.tick, RefreshPolicy.interval)
    }

    func testWakeChecksUnlessJustChecked() {
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.wake, lastChecked: now.addingTimeInterval(-5 * 60), now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.wake, lastChecked: now.addingTimeInterval(-11 * 60), now: now))
    }

    func testActivationChecksAfterAMinute() {
        XCTAssertFalse(RefreshPolicy.shouldRefresh(.activated, lastChecked: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.activated, lastChecked: now.addingTimeInterval(-61), now: now))
    }

    func testClockMovedBackwardsRefreshes() {
        XCTAssertTrue(RefreshPolicy.shouldRefresh(.timer, lastChecked: now.addingTimeInterval(3_600), now: now))
    }

    func testReportLinesForBensMac() {
        let catalog = CheckCatalog.shared
        let outcomes = MacDemoState.bensMac.outcomes
        let lines = MacCheckReport.lines(outcomes, catalog: catalog, menuBarWord: "Today", elapsed: 1.25)
        XCTAssertEqual(lines.first, "Family Shield Mac checks (\(MacCheckSuite.p0Checks.count))")
        XCTAssertTrue(lines.contains("os_patched -> fail (red) [demo]"))
        XCTAssertTrue(lines.contains("os_update_stuck -> fail (amber) [demo]"))
        XCTAssertTrue(lines.contains("beta_catalog -> fail (info) [demo]"))
        XCTAssertTrue(lines.contains("firewall -> fail (yellow) [demo]"), "firewall is advisory, never red (§6.2)")
        XCTAssertTrue(lines.contains("filevault -> pass [demo]"))
        XCTAssertEqual(lines.suffix(2), ["menubar -> Today", "elapsed -> 1.2 s"])
        for (outcome, line) in zip(outcomes, lines.dropFirst()) {
            XCTAssertTrue(line.hasPrefix("\(outcome.checkID.rawValue) -> "))
        }
    }

    func testUnknownNeverPrintsATier() {
        let outcome = MacCheckOutcome(checkID: .gatekeeper, status: .unknown, note: .timedOut)
        XCTAssertNil(MacCheckReport.tier(outcome, catalog: .shared))
        XCTAssertEqual(MacCheckReport.line(outcome, catalog: .shared), "gatekeeper -> unknown [timed_out]")
    }
}
