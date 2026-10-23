import XCTest
@testable import ShieldCore

/// §5.1: the tier is computed on the device that shows it from `CheckID` + context and is never
/// synced. A red item on a relative's device must show as red on Ben's dashboard.
final class DashboardTierTests: XCTestCase {
    let today = DateDay(year: 2026, month: 10, day: 22)!
    let catalog = CheckCatalog.shared

    private func tier(_ id: CheckID, _ statuses: [CheckID: Status], _ platform: Platform? = .ios,
                      bundled: BundledMinimums = .current) -> Tier {
        DashboardTiers.tier(for: id, statuses: statuses, platform: platform, catalog: catalog, bundled: bundled)
    }

    /// The bundled table with no known exploited bug.
    private var noExploits: BundledMinimums {
        var table = BundledMinimums.current
        table.exploitedUnpatchedBelow = [:]
        return table
    }

    func testFixedRedChecksStayRed() {
        XCTAssertEqual(tier(.passcodeSet, [.passcodeSet: .fail]), .red)
        XCTAssertEqual(tier(.gatekeeper, [.gatekeeper: .fail], .mac), .red)
        XCTAssertEqual(tier(.sip, [.sip: .fail], .mac), .red)
        XCTAssertEqual(tier(.mdmUnexpected, [.mdmUnexpected: .fail], .mac), .red)
        XCTAssertEqual(tier(.filevault, [.filevault: .fail], .mac), .amber)
        XCTAssertEqual(tier(.firewall, [.firewall: .fail], .mac), .yellow, "firewall is never red (§6.2)")
    }

    func testOSPatchedFailIsRedWhileAnExploitedFixIsOut() {
        // BundledMinimums 2026-10-22: CVE-2026-86950 is fixed in iOS 26.7.1 and macOS 26.7.1 / 15.8.1.
        XCTAssertTrue(DashboardTiers.exploitedFixOut(platform: .ios))
        XCTAssertTrue(DashboardTiers.exploitedFixOut(platform: .mac))
        XCTAssertEqual(tier(.osPatched, [.osPatched: .fail], .ios), .red)
        XCTAssertEqual(tier(.osPatched, [.osPatched: .fail], .mac), .red)
        XCTAssertEqual(tier(.osPatched, [.osPatched: .fail], nil), .red, "no Device record yet: lean red")
    }

    func testOSPatchedFailIsAmberWithNoKnownExploit() {
        XCTAssertFalse(DashboardTiers.exploitedFixOut(platform: .ios, bundled: noExploits))
        XCTAssertEqual(tier(.osPatched, [.osPatched: .fail], .ios, bundled: noExploits), .amber)
    }

    func testExploitOnALineAppleNoLongerPatchesDoesNotCount() {
        var table = noExploits
        table.exploitedUnpatchedBelow = [.ios: [OSVersion(17, 7, 9)]]
        XCTAssertFalse(DashboardTiers.exploitedFixOut(platform: .ios, bundled: table))
    }

    func testRemoteAccessIsRedOnlyOnAnUnpatchedMac() {
        XCTAssertEqual(tier(.remoteAccessOff, [.remoteAccessOff: .fail, .osPatched: .fail], .mac), .red)
        XCTAssertEqual(tier(.remoteAccessOff, [.remoteAccessOff: .fail, .osPatched: .pass], .mac), .yellow)
        XCTAssertEqual(tier(.remoteAccessOff, [.remoteAccessOff: .fail], .mac), .yellow)
        XCTAssertEqual(tier(.remoteAccessOff, [.remoteAccessOff: .fail, .osPatched: .fail], .mac, bundled: noExploits), .yellow)
    }

    func testPassingAndUnknownKeepTheCatalogTier() {
        XCTAssertEqual(tier(.osPatched, [.osPatched: .pass]), .amber)
        XCTAssertEqual(tier(.osPatched, [.osPatched: .unknown]), .amber)
        XCTAssertEqual(tier(.remoteAccessOff, [.remoteAccessOff: .unknown, .osPatched: .fail], .mac), .yellow)
    }

    // MARK: Through the aggregator

    private func dashboardDevice(_ platform: Platform, daysAgo: Int = 0, _ results: [(CheckID, Status)]) -> DashboardDevice {
        let id = UUID()
        let info = DeviceInfo(deviceID: id, platform: platform, enrolledOn: today.adding(days: -30),
                              catalogVersion: 1, appBuild: 5, lastReport: today.adding(days: -daysAgo))
        let authorship = RecordAuthorship(creator: "_mom", lastModifier: "_mom")
        var map: [String: ResultSnapshot] = [:]
        for (check, status) in results {
            let result = CheckResult(deviceID: id, checkID: check, status: status, source: .measured,
                                     checkedOn: today.adding(days: -daysAgo), catalogVersion: 1)
            map[result.recordName] = ResultSnapshot(result: result, authorship: authorship)
        }
        let zone = ZoneSnapshot(zoneName: "z_00000000000000aa", devices: [id: DeviceSnapshot(info: info, authorship: authorship)],
                                results: map)
        let dashboard = DashboardAggregator.build(zones: [zone], personLabels: [:], deviceLabels: [:], today: today, catalog: catalog)
        return dashboard.people[0].devices[0]
    }

    func testAggregatorStampsTheTierOnEachCheck() {
        let phone = dashboardDevice(.ios, [(.osPatched, .fail), (.biometricsEnrolled, .fail), (.passcodeSet, .pass)])
        let tiers = Dictionary(uniqueKeysWithValues: phone.checks.map { ($0.checkID, $0.tier) })
        XCTAssertEqual(tiers[.osPatched], .red)
        XCTAssertEqual(tiers[.biometricsEnrolled], .amber)
        XCTAssertEqual(tiers[.passcodeSet], .red)

        let mac = dashboardDevice(.mac, [(.osPatched, .fail), (.remoteAccessOff, .fail)])
        XCTAssertEqual(mac.checks.first { $0.checkID == .remoteAccessOff }?.tier, .red)
    }

    func testExpiredDeviceKeepsTheCatalogTier() {
        let stale = dashboardDevice(.mac, daysAgo: 20, [(.osPatched, .fail), (.remoteAccessOff, .fail)])
        XCTAssertEqual(stale.staleness, .expired)
        XCTAssertEqual(stale.checks.first { $0.checkID == .remoteAccessOff }?.tier, .yellow)
        XCTAssertEqual(stale.checks.first { $0.checkID == .osPatched }?.status, .unknown, "grey (H7)")
    }
}
