import Foundation
import XCTest
@testable import ShieldCore

/// VersionEvaluator → MacVersionAssessing (§5.2, §6.2 os_patched / device_supported /
/// xprotect_current / remote_access_off red rule).
final class MacVersionAdapterTests: XCTestCase {
    func mac(_ major: Int, _ minor: Int, _ patch: Int, board: String? = "J704AP", model: String? = "Mac17,2") -> MacDeviceIdentity {
        MacDeviceIdentity(osMajor: major, osMinor: minor, osPatch: patch, boardID: board, modelID: model)
    }

    func fresh() throws -> FeedState { try VersionFixtures.state(VersionFixtures.macToday) }

    // MARK: Fresh feed

    func testBensMacWithFreshFeedIsRedAndScreenSharingExposed() throws {
        let a = MacVersionAdapter.assess(mac(26, 5, 1), feed: try fresh(), now: VersionFixtures.now).assessment
        XCTAssertEqual(a.osPatched, .fail)
        XCTAssertTrue(a.activelyExploited)
        XCTAssertEqual(MacDerivedParsers.osPatched(a).tierOverride, .red)
        // 26.6.1 fixed CVE-2026-65400 and 26.7.1 fixed CVE-2026-86950; 26.5.1 has neither.
        XCTAssertTrue(a.unpatchedExploitedCVEs.isSuperset(of: ["CVE-2026-65400", "CVE-2026-86950"]))
        XCTAssertTrue(a.screenSharingExploitUnpatched)
        XCTAssertEqual(a.deviceSupported, .pass)
        XCTAssertFalse(a.agingDevice)
        XCTAssertEqual(a.xprotectFeed, XProtectFeedVersions(plistConfigData: "5368", payloads: "170"))
    }

    func testPatchedMacsPassWithFreshFeed() throws {
        for (major, minor, patch) in [(27, 0, 1), (26, 7, 1)] {
            let a = MacVersionAdapter.assess(mac(major, minor, patch), feed: try fresh(), now: VersionFixtures.now).assessment
            XCTAssertEqual(a.osPatched, .pass, "\(major).\(minor).\(patch)")
            XCTAssertFalse(a.activelyExploited)
            XCTAssertTrue(a.unpatchedExploitedCVEs.isEmpty)
            XCTAssertFalse(a.screenSharingExploitUnpatched)
        }
    }

    func testFixWithoutExploitIsAmber() throws {
        // 27.0 → 27.0.1 lists no exploited CVE, and 27.0 is not below a bundled exploited entry.
        let a = MacVersionAdapter.assess(mac(27, 0, 0), feed: try fresh(), now: VersionFixtures.now).assessment
        XCTAssertEqual(a.osPatched, .fail)
        XCTAssertFalse(a.activelyExploited)
        XCTAssertEqual(MacDerivedParsers.osPatched(a).tierOverride, .amber)
        XCTAssertFalse(a.screenSharingExploitUnpatched)
    }

    func testSonomaBelowScreenSharingFix() throws {
        let a = MacVersionAdapter.assess(mac(14, 8, 8, board: nil, model: nil), feed: try fresh(), now: VersionFixtures.now).assessment
        XCTAssertEqual(a.osPatched, .fail)
        XCTAssertTrue(a.activelyExploited)
        XCTAssertEqual(a.unpatchedExploitedCVEs, ["CVE-2026-65400"])
        XCTAssertTrue(a.screenSharingExploitUnpatched)
    }

    func testUnsupportedLineIsAmberAndNeverScreenSharingRedWhenNotFailing() throws {
        let a = MacVersionAdapter.assess(mac(13, 7, 8, board: nil, model: "MacBookPro14,1"), feed: try fresh(), now: VersionFixtures.now).assessment
        XCTAssertEqual(a.osPatched, .fail)
        XCTAssertFalse(a.activelyExploited, "an unsupported line is amber (no fix is out for it)")
        XCTAssertEqual(MacDerivedParsers.osPatched(a).tierOverride, .amber)
    }

    // MARK: Stale / never fetched (H7)

    func testStaleFeedAboveMinimumIsUnknownAndHasNoXProtectFeed() throws {
        let stale = try VersionFixtures.state(VersionFixtures.macToday, fetchedAt: VersionFixtures.utc("2026-09-01T00:00:00Z"))
        let a = MacVersionAdapter.assess(mac(26, 7, 1), feed: stale, now: VersionFixtures.now).assessment
        XCTAssertEqual(a.osPatched, .unknown)
        XCTAssertNil(a.xprotectFeed, "a stale feed can't confirm XProtect (unknown, never pass)")
    }

    func testStaleFeedBelowBundledMinimumStillFails() throws {
        let stale = try VersionFixtures.state(VersionFixtures.macToday, fetchedAt: VersionFixtures.utc("2026-09-01T00:00:00Z"))
        let a = MacVersionAdapter.assess(mac(26, 5, 1), feed: stale, now: VersionFixtures.now).assessment
        XCTAssertEqual(a.osPatched, .fail)
        XCTAssertTrue(a.activelyExploited)
        XCTAssertTrue(a.screenSharingExploitUnpatched)
    }

    func testBundledAssessorUsesEvaluatorWithNoFeed() async {
        let ben = mac(26, 5, 1)
        let a = await BundledMacVersionAssessor().assess(ben, now: VersionFixtures.now)
        XCTAssertEqual(a.osPatched, .fail)
        XCTAssertEqual(a.unpatchedExploitedCVEs, [MacVersionAdapter.bundledExploitedCVE])
        XCTAssertFalse(a.screenSharingExploitUnpatched, "without a feed the 65400 fix version is unknown")
        XCTAssertNil(a.xprotectFeed)
    }

    // MARK: FeedStore-backed assessor

    func testFeedAssessorRefreshesEvaluatesAndRaisesFloors() async throws {
        let directory = try VersionFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeFeedTransport([.ok(try VersionFixtures.data(VersionFixtures.macToday), etag: "\"a\"")])
        let store = FeedStore(platform: .mac, transport: transport, directory: directory,
                              clock: .fixed(VersionFixtures.now), appVersion: "1.0", snapshot: { nil })
        let assessor = FeedMacVersionAssessor(store: store)

        let a = await assessor.assess(mac(26, 7, 1), now: VersionFixtures.now)
        XCTAssertEqual(transport.requestCount, 1)
        XCTAssertEqual(a.osPatched, .pass)
        XCTAssertNotNil(a.xprotectFeed)
        let floors = await store.minimumFloors()
        XCTAssertEqual(floors[26], OSVersion(26, 7, 1))
    }

    func testFeedAssessorWithNetworkDownAndNoCacheNeverPasses() async throws {
        let directory = try VersionFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedStore(platform: .mac, transport: FakeFeedTransport([.failure]), directory: directory,
                              clock: .fixed(VersionFixtures.now), appVersion: "1.0", snapshot: { nil })
        let a = await FeedMacVersionAssessor(store: store).assess(mac(27, 0, 1), now: VersionFixtures.now)
        XCTAssertEqual(a.osPatched, .unknown)
        XCTAssertNil(a.xprotectFeed)
    }

    func testFeedAssessorFallsBackToBundledSnapshot() async throws {
        let directory = try VersionFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FeedStore(platform: .mac, transport: FakeFeedTransport([.failure]), directory: directory,
                              clock: .fixed(VersionFixtures.now), appVersion: "1.0")
        let a = await FeedMacVersionAssessor(store: store).assess(mac(27, 0, 1), now: VersionFixtures.now)
        XCTAssertEqual(a.osPatched, .pass, "the bundled snapshot (2026-10-22) is a day old, so it is usable")
        XCTAssertNotNil(a.xprotectFeed)
    }

    // MARK: Whole suite with the real evaluator

    func testBensMacSuiteWithFreshFeed() async throws {
        let feed = try fresh()
        let version = MacVersionAdapter.assess(mac(26, 5, 1), feed: feed, now: VersionFixtures.now).assessment
        XCTAssertEqual(MacDerivedParsers.remoteAccess([22: .closed, 5900: .open, 445: .closed, 548: .closed],
                                                     screenSharingExploitUnpatched: version.screenSharingExploitUnpatched).tierOverride,
                       .red)
        let installedCurrent = XProtectInstalledVersions(bundleVersion: "5368", appVersion: "170")
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installedCurrent, feed: version.xprotectFeed).status, .pass)
        let installedOld = XProtectInstalledVersions(bundleVersion: "5300", appVersion: "160")
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installedOld, feed: version.xprotectFeed).status, .fail)
    }
}
