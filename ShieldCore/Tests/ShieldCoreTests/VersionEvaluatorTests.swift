import Foundation
import XCTest
@testable import ShieldCore

/// SPEC §13.1 VersionEvaluatorTests, against the captured 2026-10-22 SOFA v2 feeds.
final class VersionEvaluatorTests: XCTestCase {
    let evaluator = VersionEvaluator()

    // Devices.
    let iPhone16Pro = DeviceIdentifier(modelIdentifier: "iPhone17,1")
    let iPhone15 = DeviceIdentifier(modelIdentifier: "iPhone15,4")
    let iPhoneXS = DeviceIdentifier(modelIdentifier: "iPhone11,2")
    let iPhone11 = DeviceIdentifier(modelIdentifier: "iPhone12,1")
    let iPhoneX = DeviceIdentifier(modelIdentifier: "iPhone10,3")
    /// Ben's Mac: MacBook Pro 14-inch (M5).
    let bensMac = DeviceIdentifier(modelIdentifier: "Mac17,2", boardID: "J704AP")
    let macBookAir2020 = DeviceIdentifier(modelIdentifier: "MacBookAir9,1")
    let macBookAir2018 = DeviceIdentifier(modelIdentifier: "MacBookAir8,1", boardID: "J140AAP")
    let macBookPro2016 = DeviceIdentifier(modelIdentifier: "MacBookPro14,1")

    func evaluate(
        _ platform: Platform,
        _ version: String,
        on device: DeviceIdentifier,
        feed: FeedState?,
        cached: [Int: OSVersion] = [:],
        now: Date = VersionFixtures.now
    ) throws -> VersionEvaluation {
        let osVersion = try XCTUnwrap(OSVersion(version))
        return evaluator.evaluate(.init(platform: platform, osVersion: osVersion, device: device, feed: feed,
                                        cachedMinimums: cached, now: now))
    }

    func iosFeed() throws -> FeedState { try VersionFixtures.state(VersionFixtures.iosToday) }
    func macFeed() throws -> FeedState { try VersionFixtures.state(VersionFixtures.macToday) }

    // MARK: Feed target vs. the raise-only baseline

    func testLatestAheadOfSecurityReleasesIsNeitherTheTargetNorARememberedFloor() throws {
        // SOFA's `Latest` comes from Apple's catalog and often runs ahead of `SecurityReleases`
        // (the security page lags). §5.2 step 2 sets feedTarget from SecurityReleases only, the same
        // rule FeedStore's raise-only baseline uses, so the floor remembered from one feed can never
        // make the identical feed look like a rollback on the next fetch.
        let empty = BundledMinimums(asOf: FeedStore.snapshotDate, lines: [:], exploitedUnpatchedBelow: [:])
        let evaluator = VersionEvaluator(bundled: empty)
        let line = SOFAOSVersion(major: 26, latest: SOFARelease(productVersion: OSVersion(26, 7, 2)),
                                 securityReleases: [SOFARelease(productVersion: OSVersion(26, 7, 1))])
        let feed = SOFAFeed(osVersions: [line])
        let state = FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network)
        let result = evaluator.evaluate(.init(platform: .ios, osVersion: OSVersion(26, 7, 1), device: iPhone15,
                                              feed: state, cachedMinimums: [:], now: VersionFixtures.now))
        XCTAssertEqual(result.feedTarget, OSVersion(26, 7, 1))
        XCTAssertEqual(result.osPatched, .pass)
        XCTAssertEqual(result.minimumsToRemember[26], OSVersion(26, 7, 1))
        XCTAssertTrue(FeedStore.loweredMajors(new: feed, baseline: feed, floors: result.minimumsToRemember,
                                              bundled: empty, platform: .ios).isEmpty,
                      "the same feed, fetched again, is not a rollback")

        // A line that lists only `Latest` still has a target (and the same baseline).
        let latestOnly = SOFAFeed(osVersions: [SOFAOSVersion(major: 27, latest: SOFARelease(productVersion: OSVersion(27, 0, 1)),
                                                             securityReleases: [])])
        let newer = evaluator.evaluate(.init(platform: .ios, osVersion: OSVersion(27, 0), device: iPhone16Pro,
                                             feed: FeedState(feed: latestOnly, fetchedAt: VersionFixtures.now, origin: .network),
                                             cachedMinimums: [:], now: VersionFixtures.now))
        XCTAssertEqual(newer.feedTarget, OSVersion(27, 0, 1))
        XCTAssertEqual(newer.osPatched, .fail)
        XCTAssertTrue(FeedStore.loweredMajors(new: latestOnly, baseline: latestOnly, floors: newer.minimumsToRemember,
                                              bundled: empty, platform: .ios).isEmpty)
    }

    // MARK: iOS

    func testIOS27_0_1Passes() throws {
        let result = try evaluate(.ios, "27.0.1", on: iPhone16Pro, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .pass)
        XCTAssertEqual(result.patchOutcome, .patched)
        XCTAssertFalse(result.exploited)
        XCTAssertEqual(result.feedTarget, OSVersion(27, 0, 1))
        XCTAssertEqual(result.effectiveMinimum, OSVersion(27, 0, 1))
        XCTAssertEqual(result.deviceSupported, .pass)
        XCTAssertEqual(result.supportOutcome, .current)
        XCTAssertEqual(result.freshness, .fresh(ageDays: 0))
        XCTAssertNil(result.lastCheckedDays)
    }

    func testIOS27_0_0FailsEvenThough27_0_1ListsNoCVEs() throws {
        // §5.2 step 4: version comparison only. 27.0.1 has 0 CVEs, but 27.0 is still not patched.
        let result = try evaluate(.ios, "27.0", on: iPhone16Pro, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.patchOutcome, .updateAvailable)
        XCTAssertEqual(result.osPatchedTier, .amber)
    }

    func testIOS26_7_1Passes() throws {
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .pass)
        XCTAssertEqual(result.effectiveMinimum, OSVersion(26, 7, 1))
        XCTAssertEqual(result.deviceSupported, .pass)
    }

    func testIOS26_5_1FailsExploitedRed() throws {
        let result = try evaluate(.ios, "26.5.1", on: iPhone15, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertTrue(result.exploited)
        XCTAssertEqual(result.patchOutcome, .updateExploited)
        XCTAssertEqual(result.osPatchedTier, .red)
        XCTAssertEqual(result.effectiveMinimum, OSVersion(26, 7, 1))
    }

    func testIOS18_7_10OnXSPasses() throws {
        let result = try evaluate(.ios, "18.7.10", on: iPhoneXS, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .pass)
        XCTAssertEqual(result.bundledMinimum, OSVersion(18, 7, 10))
        XCTAssertEqual(result.feedTarget, OSVersion(18, 7, 10))
        // §5.2 step 6: highest major (18) is not current but still patched → pass + aging note.
        XCTAssertEqual(result.deviceSupported, .pass)
        XCTAssertEqual(result.supportOutcome, .aging(highestMajor: 18))
    }

    func testIOS18_7_8OnXSFails() throws {
        let result = try evaluate(.ios, "18.7.8", on: iPhoneXS, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.patchOutcome, .updateAvailable)
        XCTAssertFalse(result.exploited)
        XCTAssertEqual(result.osPatchedTier, .amber)
        XCTAssertEqual(result.effectiveMinimum, OSVersion(18, 7, 10))
    }

    func testIOS18_7_8OnIPhone11Passes() throws {
        let result = try evaluate(.ios, "18.7.8", on: iPhone11, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .pass)
        // The device-specific 18.7.9/18.7.10 releases do not list iPhone12,1.
        XCTAssertEqual(result.feedTarget, OSVersion(18, 7, 8))
        XCTAssertEqual(result.bundledMinimum, OSVersion(18, 7, 8))
        XCTAssertEqual(result.deviceSupported, .pass)
        XCTAssertEqual(result.supportOutcome, .current, "iPhone 11 can run iOS 27")
    }

    func testIPhoneXIsUnsupported() throws {
        let result = try evaluate(.ios, "16.7.12", on: iPhoneX, feed: iosFeed())
        XCTAssertEqual(result.deviceSupported, .fail)
        XCTAssertEqual(result.supportOutcome, .unsupported)
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.patchOutcome, .osLineUnsupported)
    }

    func testIPhoneXIsUnsupportedWithoutAFeed() throws {
        let result = try evaluate(.ios, "16.7.12", on: iPhoneX, feed: nil)
        XCTAssertEqual(result.deviceSupported, .fail)
        XCTAssertEqual(result.supportOutcome, .unsupported)
    }

    // MARK: macOS

    func testMacOS26_5_1OnBensBoardIDFailsExploited() throws {
        let result = try evaluate(.mac, "26.5.1", on: bensMac, feed: macFeed())
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertTrue(result.exploited)
        XCTAssertEqual(result.patchOutcome, .updateExploited)
        XCTAssertEqual(result.osPatchedTier, .red)
        XCTAssertEqual(result.feedTarget, OSVersion(26, 7, 1))
        XCTAssertEqual(result.deviceSupported, .pass)
        XCTAssertEqual(result.supportOutcome, .current)
    }

    func testMacOS15_8_1Passes() throws {
        let result = try evaluate(.mac, "15.8.1", on: macBookAir2020, feed: macFeed())
        XCTAssertEqual(result.osPatched, .pass)
        XCTAssertEqual(result.feedTarget, OSVersion(15, 8, 1))
        XCTAssertEqual(result.deviceSupported, .pass)
        XCTAssertEqual(result.supportOutcome, .aging(highestMajor: 15))
    }

    func testMacOS15_8FailsExploited() throws {
        let result = try evaluate(.mac, "15.8", on: macBookAir2020, feed: macFeed())
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.osPatchedTier, .red)
    }

    func testMacOS14_8_9Passes() throws {
        let result = try evaluate(.mac, "14.8.9", on: macBookAir2018, feed: macFeed())
        XCTAssertEqual(result.osPatched, .pass)
        XCTAssertEqual(result.effectiveMinimum, OSVersion(14, 8, 9))
        XCTAssertEqual(result.supportOutcome, .aging(highestMajor: 14))
    }

    func testMacOS13IsUnsupported() throws {
        let result = try evaluate(.mac, "13.7.8", on: macBookPro2016, feed: macFeed())
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.patchOutcome, .osLineUnsupported)
        XCTAssertEqual(result.deviceSupported, .fail, "MacBookPro14,1 tops out at macOS 13")
        XCTAssertEqual(result.supportOutcome, .unsupported)
    }

    func testMacOS13OnAModelThatCanUpgradeIsOSLineOnly() throws {
        let result = try evaluate(.mac, "13.7.8", on: bensMac, feed: macFeed())
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.patchOutcome, .osLineUnsupported)
        XCTAssertEqual(result.deviceSupported, .pass)
    }

    func testMacOS13IsUnsupportedWithoutAFeed() throws {
        let result = try evaluate(.mac, "13.6", on: macBookPro2016, feed: nil)
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.patchOutcome, .osLineUnsupported)
        XCTAssertEqual(result.deviceSupported, .unknown)
    }

    // MARK: Raise-only

    func testRollbackFeedRejectedCacheKept() async throws {
        let directory = try VersionFixtures.temporaryDirectory()
        let clock = TestClock(VersionFixtures.now)
        let transport = FakeFeedTransport([
            .ok(try VersionFixtures.data(VersionFixtures.iosToday), etag: "W/\"good\""),
            .ok(try VersionFixtures.data(VersionFixtures.iosRollback), etag: "W/\"rollback\""),
        ])
        let store = FeedStore(platform: .ios, transport: transport, directory: directory, clock: clock.clock)
        let first = await store.refresh()
        XCTAssertEqual(first, .updated)
        clock.advance(seconds: FeedStore.minimumInterval)
        let second = await store.refresh()
        XCTAssertEqual(second, .rejectedRollback)

        let kept = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertEqual(kept.feed.osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 1), "cache kept")
        // And the evaluator, fed the kept cache, still requires 26.7.1.
        let result = try evaluate(.ios, "26.7", on: iPhone15, feed: kept, now: clock.now)
        XCTAssertEqual(result.osPatched, .fail)
    }

    func testRollbackRejectedAgainstBundledTableEvenWithoutCache() throws {
        let lowered = FeedStore.loweredMajors(
            new: try VersionFixtures.feed(VersionFixtures.macRollback), baseline: nil, floors: [:],
            bundled: .current, platform: .mac)
        XCTAssertEqual(Set(lowered), [27, 26, 15])
    }

    func testFeedRaisingAMinimumIsAccepted() async throws {
        let directory = try VersionFixtures.temporaryDirectory()
        let clock = TestClock(VersionFixtures.now)
        let transport = FakeFeedTransport([
            .ok(try VersionFixtures.data(VersionFixtures.iosToday), etag: "a"),
            .ok(try VersionFixtures.data(VersionFixtures.iosRaise), etag: "b"),
        ])
        let store = FeedStore(platform: .ios, transport: transport, directory: directory, clock: clock.clock)
        let first = await store.refresh()
        XCTAssertEqual(first, .updated)
        clock.advance(days: 7)
        let second = await store.refresh()
        XCTAssertEqual(second, .updated)

        let state = try await XCTUnwrapAsync(await store.currentFeed())
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: state, now: clock.now)
        XCTAssertEqual(result.feedTarget, OSVersion(26, 7, 2))
        XCTAssertEqual(result.effectiveMinimum, OSVersion(26, 7, 2))
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.osPatchedTier, .red, "26.7.2 fixes an exploited CVE in the raise fixture")
        XCTAssertEqual(result.minimumsToRemember[26], OSVersion(26, 7, 2))
    }

    func testCachedMinimumIsAFloor() throws {
        // lastGoodCachedMin 26.7.2 beats a feed that only knows 26.7.1.
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: iosFeed(), cached: [26: OSVersion(26, 7, 2)])
        XCTAssertEqual(result.effectiveMinimum, OSVersion(26, 7, 2))
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.minimumsToRemember[26], OSVersion(26, 7, 2), "never lowered")
    }

    func testMinimumsToRememberRaisesFromFeed() throws {
        let result = try evaluate(.ios, "27.0.1", on: iPhone16Pro, feed: iosFeed(), cached: [27: OSVersion(27, 0)])
        XCTAssertEqual(result.minimumsToRemember[27], OSVersion(27, 0, 1))
    }

    // MARK: Freshness

    func testStale8DaysShowsLastChecked() throws {
        let fetched = VersionFixtures.now.addingTimeInterval(-8 * 86_400)
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: VersionFixtures.state(VersionFixtures.iosToday, fetchedAt: fetched))
        XCTAssertEqual(result.freshness, .aging(ageDays: 8))
        XCTAssertEqual(result.lastCheckedDays, 8)
        XCTAssertEqual(result.osPatched, .pass, "7–30 days is still normal")
    }

    func testFreshnessBoundaries() {
        let now = VersionFixtures.now
        func ago(_ days: Double) -> FeedFreshness { .of(fetchedAt: now.addingTimeInterval(-days * 86_400), now: now) }
        XCTAssertEqual(ago(6.9), .fresh(ageDays: 6))
        XCTAssertEqual(ago(7), .aging(ageDays: 7))
        XCTAssertEqual(ago(30.9), .aging(ageDays: 30))
        XCTAssertEqual(ago(31), .stale(ageDays: 31))
        XCTAssertEqual(FeedFreshness.of(fetchedAt: nil, now: now), .never)
        XCTAssertFalse(FeedFreshness.of(fetchedAt: now.addingTimeInterval(3 * 86_400), now: now).isUsable,
                       "a fetch date days in the future is not trusted")
        XCTAssertEqual(ago(0).feedFreshStatus, .pass)
        XCTAssertEqual(ago(10).feedFreshStatus, .unknown)
        XCTAssertEqual(ago(40).feedFreshStatus, .fail)
    }

    func testStalledUpstreamAgesFromLastCheck() throws {
        // SOFA stopped regenerating: we still fetch (or get a 304) every 6 h, but its LastCheck is
        // 40 days old. Stale data is unknown, never pass (H7).
        var feed = try VersionFixtures.feed(VersionFixtures.iosToday)
        feed.lastCheck = VersionFixtures.now.addingTimeInterval(-40 * 86_400)
        let state = FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network)
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: state)
        XCTAssertEqual(result.freshness, .stale(ageDays: 40))
        XCTAssertEqual(result.osPatched, .unknown)
        XCTAssertEqual(result.patchOutcome, .cantConfirm)
        XCTAssertTrue(result.minimumsToRemember.isEmpty)

        // A LastCheck after our fetch (clock skew) never makes the data look newer than the fetch.
        feed.lastCheck = VersionFixtures.now.addingTimeInterval(5 * 86_400)
        XCTAssertEqual(FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network).dataDate, VersionFixtures.now)
        feed.lastCheck = nil
        XCTAssertEqual(FeedFreshness.of(FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network),
                                        now: VersionFixtures.now), .fresh(ageDays: 0))
    }

    func testStale31DaysAboveMinimumIsUnknown() throws {
        let fetched = VersionFixtures.now.addingTimeInterval(-31 * 86_400)
        let stale = try VersionFixtures.state(VersionFixtures.iosStale, fetchedAt: fetched)
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: stale)
        XCTAssertEqual(result.freshness, .stale(ageDays: 31))
        XCTAssertEqual(result.osPatched, .unknown)
        XCTAssertEqual(result.patchOutcome, .cantConfirm)
        XCTAssertTrue(result.minimumsToRemember.isEmpty, "a stale feed never moves the floors")
    }

    func testStale31DaysTodayFeedAboveMinimumIsUnknown() throws {
        // Even a feed that says "pass" can't confirm once it is over 30 days old (H7).
        let fetched = VersionFixtures.now.addingTimeInterval(-31 * 86_400)
        let result = try evaluate(.mac, "27.0.1", on: bensMac, feed: VersionFixtures.state(VersionFixtures.macToday, fetchedAt: fetched))
        XCTAssertEqual(result.osPatched, .unknown)
    }

    func testStale31DaysBelowBundledMinimumFails() throws {
        let fetched = VersionFixtures.now.addingTimeInterval(-31 * 86_400)
        let stale = try VersionFixtures.state(VersionFixtures.macStale, fetchedAt: fetched)
        let result = try evaluate(.mac, "26.5.1", on: bensMac, feed: stale)
        XCTAssertEqual(result.osPatched, .fail, "below the bundled minimum is still true")
        XCTAssertEqual(result.patchOutcome, .updateExploited)
        XCTAssertEqual(result.osPatchedTier, .red)
    }

    func testNoFeedEverUsesBundledTableOnly() throws {
        let above = try evaluate(.ios, "27.0.1", on: iPhone16Pro, feed: nil)
        XCTAssertEqual(above.freshness, .never)
        XCTAssertNil(above.feedTarget)
        XCTAssertEqual(above.effectiveMinimum, OSVersion(27, 0, 1))
        XCTAssertEqual(above.osPatched, .unknown, "never fetched → can't confirm, never green")
        XCTAssertEqual(above.patchOutcome, .cantConfirm)
        XCTAssertEqual(above.deviceSupported, .pass, "the bundled table knows iPhone17,1")

        let below = try evaluate(.ios, "26.5.1", on: iPhone15, feed: nil)
        XCTAssertEqual(below.osPatched, .fail)
        XCTAssertEqual(below.patchOutcome, .updateExploited, "bundled exploitedUnpatchedBelow 26.7.1")

        let xs = try evaluate(.ios, "18.7.9", on: iPhoneXS, feed: nil)
        XCTAssertEqual(xs.osPatched, .fail)
        XCTAssertEqual(xs.effectiveMinimum, OSVersion(18, 7, 10))
        XCTAssertEqual(xs.supportOutcome, .aging(highestMajor: 18))

        let mac = try evaluate(.mac, "15.8", on: macBookAir2020, feed: nil)
        XCTAssertEqual(mac.osPatched, .fail)
        XCTAssertEqual(mac.osPatchedTier, .red, "bundled exploitedUnpatchedBelow 15.8.1")
    }

    func testBundledSnapshotEvaluatesLikeTheLiveFeed() throws {
        let snapshot = try XCTUnwrap(FeedStore.bundledSnapshot(for: .ios))
        XCTAssertEqual(snapshot.origin, .bundledSnapshot)
        let result = try evaluate(.ios, "18.7.10", on: iPhoneXS, feed: snapshot, now: FeedStore.snapshotDate.date.addingTimeInterval(3600))
        XCTAssertEqual(result.osPatched, .pass)
        XCTAssertEqual(result.supportOutcome, .aging(highestMajor: 18))
        let mac = try XCTUnwrap(FeedStore.bundledSnapshot(for: .mac))
        let macResult = try evaluate(.mac, "26.5.1", on: bensMac, feed: mac, now: FeedStore.snapshotDate.date.addingTimeInterval(3600))
        XCTAssertEqual(macResult.patchOutcome, .updateExploited)
    }

    // MARK: Defensive feed shapes (§5.2: CVEs as int/map/array; Build null)

    func inlineFeed(cves: String, build: String = "\"23H6030\"", exploitedList: String = "[]") -> Data {
        VersionFixtures.json("""
        {"OSVersions":[{"OSVersion":"26","Latest":{"ProductVersion":"26.7.1","Build":\(build),"CVEs":3,
          "ActivelyExploitedCVEs":\(exploitedList),"DeviceScope":"universal","SupportedDevices":["iPhone15,4"]},
          "SecurityReleases":[{"ProductVersion":"26.7.1","Build":\(build),"CVEs":\(cves),
          "ActivelyExploitedCVEs":\(exploitedList),"DeviceScope":"universal","SupportedDevices":["iPhone15,4"]}]}]}
        """)
    }

    func testCVEsAsInt() throws {
        let feed = try XCTUnwrap(SOFAFeed.decode(inlineFeed(cves: "7", exploitedList: #"["CVE-2026-86950"]"#)))
        XCTAssertEqual(feed.osVersion(major: 26)?.securityReleases.first?.cves, .count(7))
        let result = try evaluate(.ios, "26.5.1", on: iPhone15, feed: FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network))
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertTrue(result.exploited)
    }

    func testCVEsAsMapMarksExploited() throws {
        // No ActivelyExploitedCVEs list; the map's ActivelyExploited flag is enough.
        let feed = try XCTUnwrap(SOFAFeed.decode(inlineFeed(cves: #"{"CVE-2026-1":{"ActivelyExploited":true,"InKEV":true},"CVE-2026-2":{"ActivelyExploited":false}}"#)))
        let release = try XCTUnwrap(feed.osVersion(major: 26)?.securityReleases.first)
        XCTAssertEqual(release.cves.count, 2)
        XCTAssertEqual(release.activelyExploitedCVEs, ["CVE-2026-1"])
        XCTAssertTrue(VersionEvaluator.exploitedAbove(in: feed, platform: .ios, version: OSVersion(26, 6), device: iPhone15))
    }

    func testCVEsAsArray() throws {
        let feed = try XCTUnwrap(SOFAFeed.decode(inlineFeed(cves: #"["CVE-2026-1","CVE-2026-2","CVE-2026-3"]"#)))
        let release = try XCTUnwrap(feed.osVersion(major: 26)?.securityReleases.first)
        XCTAssertEqual(release.cves, .ids(["CVE-2026-1", "CVE-2026-2", "CVE-2026-3"]))
        XCTAssertFalse(release.fixesActivelyExploited)
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network))
        XCTAssertEqual(result.osPatched, .pass)
    }

    func testCVEsZeroDoesNotMeanPatched() throws {
        let feed = try XCTUnwrap(SOFAFeed.decode(inlineFeed(cves: "0")))
        let result = try evaluate(.ios, "26.7", on: iPhone15, feed: FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network))
        XCTAssertEqual(result.osPatched, .fail)
    }

    func testBuildNull() throws {
        let feed = try XCTUnwrap(SOFAFeed.decode(inlineFeed(cves: "1", build: "null")))
        XCTAssertNil(feed.osVersion(major: 26)?.securityReleases.first?.build)
        XCTAssertNil(feed.osVersion(major: 26)?.latest?.build)
        let result = try evaluate(.ios, "26.7.1", on: iPhone15, feed: FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network))
        XCTAssertEqual(result.osPatched, .pass)
    }

    // MARK: Other edges

    func testNewMajorFromFeedIsUsed() throws {
        let feed = try XCTUnwrap(SOFAFeed.decode(VersionFixtures.json("""
        {"OSVersions":[{"OSVersion":"28","SecurityReleases":[{"ProductVersion":"28.0.1","DeviceScope":"universal","SupportedDevices":["iPhone17,1"]}]},
                       {"OSVersion":"27","SecurityReleases":[{"ProductVersion":"27.0.1","DeviceScope":"universal","SupportedDevices":["iPhone17,1"]}]}]}
        """)))
        let state = FeedState(feed: feed, fetchedAt: VersionFixtures.now, origin: .network)
        let below = try evaluate(.ios, "28.0", on: iPhone16Pro, feed: state)
        XCTAssertEqual(below.osPatched, .fail)
        let at = try evaluate(.ios, "28.0.1", on: iPhone16Pro, feed: state)
        XCTAssertEqual(at.osPatched, .pass)
        // 27-only devices are now "aging" once 28 exists.
        let support = try evaluate(.ios, "27.0.1", on: DeviceIdentifier(modelIdentifier: "iPhone12,1"), feed: state)
        XCTAssertEqual(support.supportOutcome, .aging(highestMajor: 27))
    }

    func testUnknownNewMajorWithoutFeedIsUnknown() throws {
        let result = try evaluate(.ios, "28.0", on: iPhone16Pro, feed: iosFeed())
        XCTAssertEqual(result.osPatched, .unknown)
        XCTAssertEqual(result.patchOutcome, .cantConfirm)
    }

    func testUnknownModelStillGetsUniversalTarget() throws {
        // e.g. a Simulator without SIMULATOR_MODEL_IDENTIFIER.
        let unknown = DeviceIdentifier(modelIdentifier: nil)
        let result = try evaluate(.ios, "26.7", on: unknown, feed: iosFeed())
        XCTAssertEqual(result.feedTarget, OSVersion(26, 7, 1))
        XCTAssertEqual(result.osPatched, .fail)
        XCTAssertEqual(result.deviceSupported, .pass, "running a patched major")
    }

    func testCheckResultsAreMeasuredAndAllowlisted() throws {
        let result = try evaluate(.ios, "26.5.1", on: iPhone15, feed: iosFeed())
        let id = UUID()
        let day = DateDay(VersionFixtures.now)
        let results = result.checkResults(deviceID: id, checkedOn: day, catalogVersion: 1)
        XCTAssertEqual(results.map(\.checkID), [.osPatched, .deviceSupported])
        XCTAssertEqual(results.map(\.status), [.fail, .pass])
        XCTAssertTrue(results.allSatisfy { $0.source == .measured && $0.deviceID == id && $0.checkedOn == day })
        XCTAssertNoThrow(try validateForSink(device: DeviceInfo(deviceID: id, platform: .ios, enrolledOn: day,
                                                                catalogVersion: 1, appBuild: 1, lastReport: day),
                                             results: results))
    }
}

/// `XCTUnwrap` for an already-awaited optional (keeps call sites short in async tests).
func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
