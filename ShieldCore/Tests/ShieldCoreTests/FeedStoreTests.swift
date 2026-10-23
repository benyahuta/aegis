import Foundation
import XCTest
@testable import ShieldCore

/// FeedStore: ETag, 6 h throttle, Application Support cache, raise-only, bundled snapshot fallback.
final class FeedStoreTests: XCTestCase {
    var directory: URL!
    var clock: TestClock!

    override func setUpWithError() throws {
        directory = try VersionFixtures.temporaryDirectory()
        clock = TestClock(VersionFixtures.now)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func makeStore(_ transport: FakeFeedTransport, platform: Platform = .ios,
                   snapshot: (@Sendable () -> FeedState?)? = nil) -> FeedStore {
        FeedStore(platform: platform, transport: transport, directory: directory, clock: clock.clock,
                  appVersion: "1.2", snapshot: snapshot)
    }

    func today(_ platform: Platform = .ios) throws -> Data {
        try VersionFixtures.data(platform == .ios ? VersionFixtures.iosToday : VersionFixtures.macToday)
    }

    // MARK: Request shape

    func testFirstFetchRequestShape() async throws {
        let transport = FakeFeedTransport([.ok(try today(), etag: #"W/"efad""#)])
        let store = makeStore(transport)
        let outcome = await store.refresh()
        XCTAssertEqual(outcome, .updated)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://sofafeed.macadmins.io/v2/ios_data_feed.json")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"),
                       "FamilyShield/1.2 (+https://github.com/benyahuta/aegis)")
        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"), "no ETag before anything is cached")
    }

    func testMacURL() {
        XCTAssertEqual(FeedStore.feedURL(for: .mac).absoluteString, "https://sofafeed.macadmins.io/v2/macos_data_feed.json")
    }

    // MARK: Throttle + ETag

    func testThrottleAndConditionalRequest() async throws {
        let transport = FakeFeedTransport([.ok(try today(), etag: #"W/"one""#), .status(304)])
        let store = makeStore(transport)
        var outcome = await store.refresh()
        XCTAssertEqual(outcome, .updated)

        clock.advance(seconds: 6 * 3600 - 1)
        outcome = await store.refresh()
        XCTAssertEqual(outcome, .throttled)
        XCTAssertEqual(transport.requestCount, 1, "at most one fetch per 6 h")

        clock.advance(seconds: 1)
        outcome = await store.refresh()
        XCTAssertEqual(outcome, .notModified)
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "If-None-Match"), #"W/"one""#)

        let state = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertEqual(state.fetchedAt, clock.now, "a 304 renews the last good feed's age")
    }

    func testFailedAttemptsAlsoThrottle() async throws {
        let transport = FakeFeedTransport([.failure])
        let store = makeStore(transport)
        var outcome = await store.refresh()
        XCTAssertEqual(outcome, .networkFailed)
        clock.advance(seconds: 3600)
        outcome = await store.refresh()
        XCTAssertEqual(outcome, .throttled)
        outcome = await store.refresh(force: true)
        XCTAssertEqual(outcome, .networkFailed)
        XCTAssertEqual(transport.requestCount, 2)
    }

    func testThrottleSurvivesRelaunch() async throws {
        let first = makeStore(FakeFeedTransport([.ok(try today(), etag: "e")]))
        _ = await first.refresh()
        clock.advance(seconds: 60)
        let transport = FakeFeedTransport([.ok(try today(), etag: "e")])
        let relaunched = makeStore(transport)
        let outcome = await relaunched.refresh()
        XCTAssertEqual(outcome, .throttled)
        XCTAssertEqual(transport.requestCount, 0)
    }

    // MARK: Cache

    func testCachePersistsAcrossInstances() async throws {
        let store = makeStore(FakeFeedTransport([.ok(try today(), etag: "e1")]))
        _ = await store.refresh()

        let fileURL = directory.appendingPathComponent("ios_v2.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reopened = makeStore(FakeFeedTransport(), snapshot: { nil })
        let state = try await XCTUnwrapAsync(await reopened.currentFeed())
        XCTAssertEqual(state.origin, .cache)
        XCTAssertEqual(state.fetchedAt, VersionFixtures.now)
        XCTAssertEqual(state.feed.osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 1))
    }

    func testCorruptCacheFallsBackToSnapshotAndDropsETag() async throws {
        let store = makeStore(FakeFeedTransport([.ok(try today(), etag: "e1")]))
        _ = await store.refresh()
        try Data("{\"OSVer".utf8).write(to: directory.appendingPathComponent("ios_v2.json"))

        clock.advance(days: 1)
        let transport = FakeFeedTransport([.ok(try today(), etag: "e2")])
        let reopened = makeStore(transport)
        let fallback = try await XCTUnwrapAsync(await reopened.currentFeed())
        XCTAssertEqual(fallback.origin, .bundledSnapshot)
        let outcome = await reopened.refresh()
        XCTAssertEqual(outcome, .updated)
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testNoCacheUsesBundledSnapshot() async throws {
        let store = makeStore(FakeFeedTransport())
        let state = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertEqual(state.origin, .bundledSnapshot)
        XCTAssertEqual(state.fetchedAt, FeedStore.snapshotDate.date)
        let cached = await store.cachedFeed()
        XCTAssertNil(cached)
    }

    func testNoCacheAndNoSnapshotIsNil() async {
        let store = makeStore(FakeFeedTransport(), snapshot: { nil })
        let state = await store.currentFeed()
        XCTAssertNil(state)
    }

    func testMacStoreUsesMacSnapshotAndFile() async throws {
        let store = makeStore(FakeFeedTransport([.ok(try today(.mac), etag: nil)]), platform: .mac)
        let snapshot = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertFalse(snapshot.feed.models.isEmpty)
        let outcome = await store.refresh()
        XCTAssertEqual(outcome, .updated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("macos_v2.json").path))
    }

    // MARK: Failures keep the cache

    func testDecodeFailureIsIgnored() async throws {
        let good = try today()
        let transport = FakeFeedTransport([.ok(good, etag: "e1"), .ok(good.prefix(5000), etag: "e2")])
        let store = makeStore(transport)
        _ = await store.refresh()
        clock.advance(days: 1)
        let outcome = await store.refresh()
        XCTAssertEqual(outcome, .decodeFailed)
        let state = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertEqual(state.fetchedAt, VersionFixtures.now, "the failed fetch did not renew the age")
        XCTAssertEqual(state.origin, .network)
    }

    func testHTTPErrorsAreIgnored() async throws {
        let transport = FakeFeedTransport([.status(500), .status(304)])
        let store = makeStore(transport)
        var outcome = await store.refresh()
        XCTAssertEqual(outcome, .httpError)
        outcome = await store.refresh(force: true)
        XCTAssertEqual(outcome, .httpError, "a 304 with nothing cached is useless")
        let cached = await store.cachedFeed()
        XCTAssertNil(cached)
    }

    func testRollbackRejectedKeepsCacheAndETag() async throws {
        let transport = FakeFeedTransport([
            .ok(try today(), etag: "good"),
            .ok(try VersionFixtures.data(VersionFixtures.iosRollback), etag: "bad"),
            .status(304),
        ])
        let store = makeStore(transport)
        _ = await store.refresh()
        clock.advance(days: 1)
        let rejected = await store.refresh()
        XCTAssertEqual(rejected, .rejectedRollback)
        clock.advance(days: 1)
        _ = await store.refresh()
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "If-None-Match"), "good")
        let state = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertEqual(state.feed.osVersion(major: 27)?.highestVersion, OSVersion(27, 0, 1))
    }

    func testRollbackAgainstStoredFloorsOnly() async throws {
        // A custom table with no bundled lines, so only the stored floor can catch the rollback.
        let empty = BundledMinimums(asOf: FeedStore.snapshotDate, lines: [:], exploitedUnpatchedBelow: [:])
        let transport = FakeFeedTransport([.ok(try today(), etag: nil)])
        let store = FeedStore(platform: .ios, transport: transport, directory: directory, clock: clock.clock,
                              appVersion: "1.0", bundled: empty, snapshot: { nil })
        await store.raiseMinimumFloors([26: OSVersion(26, 7, 2)])
        let outcome = await store.refresh()
        XCTAssertEqual(outcome, .rejectedRollback)
    }

    func testLoweredMajorsIgnoresDroppedMajors() throws {
        let today = try VersionFixtures.feed(VersionFixtures.macToday)
        var dropped = today
        dropped.osVersions.removeAll { $0.major <= 13 }
        XCTAssertTrue(FeedStore.loweredMajors(new: dropped, baseline: today, floors: [:], bundled: .current, platform: .mac).isEmpty)
        XCTAssertEqual(FeedStore.loweredMajors(new: try VersionFixtures.feed(VersionFixtures.iosStale), baseline: nil,
                                               floors: [:], bundled: .current, platform: .ios), [27, 26])
    }

    // MARK: Floors

    func testFloorsOnlyRiseAndPersist() async throws {
        let store = makeStore(FakeFeedTransport())
        await store.raiseMinimumFloors([26: OSVersion(26, 7, 1), 18: OSVersion(18, 7, 10)])
        await store.raiseMinimumFloors([26: OSVersion(26, 5), 18: OSVersion(18, 7, 11), 27: OSVersion(26, 1)])
        let floors = await store.minimumFloors()
        XCTAssertEqual(floors, [26: OSVersion(26, 7, 1), 18: OSVersion(18, 7, 11)], "lower values and mismatched majors are ignored")

        let reopened = makeStore(FakeFeedTransport())
        let persisted = await reopened.minimumFloors()
        XCTAssertEqual(persisted, floors)
    }

    func testEndToEndWithEvaluator() async throws {
        let store = makeStore(FakeFeedTransport([.ok(try today(), etag: "e")]))
        _ = await store.refresh()
        let feed = await store.currentFeed()
        let floors = await store.minimumFloors()
        let result = VersionEvaluator().evaluate(.init(
            platform: .ios, osVersion: OSVersion(26, 7, 1), device: DeviceIdentifier(modelIdentifier: "iPhone15,4"),
            feed: feed, cachedMinimums: floors, now: clock.now))
        XCTAssertEqual(result.osPatched, .pass)
        await store.raiseMinimumFloors(result.minimumsToRemember)
        let raised = await store.minimumFloors()
        XCTAssertEqual(raised[26], OSVersion(26, 7, 1))
    }

    // MARK: Review regressions

    func testFailedCacheWriteDoesNotPersistTheNewETagOrAge() async throws {
        let transport = FakeFeedTransport([.ok(try today(), etag: "A")])
        let store = makeStore(transport, snapshot: { nil })
        _ = await store.refresh()
        // Lock the body file so the next cache write fails while the small metadata write succeeds.
        let fileURL = directory.appendingPathComponent("ios_v2.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fileURL.path) }

        clock.advance(seconds: 7 * 3600)
        transport.enqueue(.ok(try VersionFixtures.data(VersionFixtures.iosRaise), etag: "B"))
        let outcome = await store.refresh()
        XCTAssertEqual(outcome, .updated)
        let inSession = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertEqual(inSession.feed.osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 2), "still used this session")

        // Relaunch: the old body keeps its own age, and the next refresh asks for a full body
        // (a 304 against "B" would otherwise renew the old body as fresh).
        clock.advance(seconds: 7 * 3600)
        let next = FakeFeedTransport([.ok(try VersionFixtures.data(VersionFixtures.iosRaise), etag: "B")])
        let relaunched = makeStore(next, snapshot: { nil })
        let reloaded = try await XCTUnwrapAsync(await relaunched.currentFeed())
        XCTAssertEqual(reloaded.feed.osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 1))
        XCTAssertEqual(reloaded.fetchedAt, VersionFixtures.now, "the old body is not dated by the failed write")
        _ = await relaunched.refresh()
        XCTAssertEqual(next.requestCount, 1)
        XCTAssertNil(next.requests.first?.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testNewerSnapshotBeatsAnOlderCache() async throws {
        // Cache fetched on day 0; a new build's snapshot is dated day 34; offline on day 38.
        var newer = try VersionFixtures.feed(VersionFixtures.iosToday)
        let snapshotDate = VersionFixtures.now.addingTimeInterval(34 * 86_400)
        newer.lastCheck = snapshotDate
        let snapshot = FeedState(feed: newer, fetchedAt: snapshotDate, origin: .bundledSnapshot)
        let store = makeStore(FakeFeedTransport([.ok(try today(), etag: "e"), .failure]), snapshot: { snapshot })
        _ = await store.refresh()

        clock.advance(days: 38)
        let outcome = await store.refresh()
        XCTAssertEqual(outcome, .networkFailed)
        let best = try await XCTUnwrapAsync(await store.currentFeed())
        XCTAssertEqual(best.origin, .bundledSnapshot)
        XCTAssertEqual(FeedFreshness.of(best, now: clock.now), .fresh(ageDays: 4))
        let result = VersionEvaluator().evaluate(.init(
            platform: .ios, osVersion: OSVersion(26, 7, 1), device: DeviceIdentifier(modelIdentifier: "iPhone15,4"),
            feed: best, now: clock.now))
        XCTAssertEqual(result.osPatched, .pass)
    }

    func testNewerBuildResetsAnOvershootCacheAndFloors() async throws {
        // Build A accepts a feed whose 26 line is higher (here: 26.7.2) and remembers it as a floor.
        let overshoot = try VersionFixtures.data(VersionFixtures.iosRaise)
        let buildA = makeStore(FakeFeedTransport([.ok(overshoot, etag: "high"), .ok(try today(), etag: "fixed")]))
        let r14754 = await buildA.refresh()
        XCTAssertEqual(r14754, .updated)
        await buildA.raiseMinimumFloors([26: OSVersion(26, 7, 2)])
        clock.advance(seconds: 7 * 3600)
        let r14919 = await buildA.refresh()
        XCTAssertEqual(r14919, .rejectedRollback, "feeds may never lower")

        // Build B ships a newer trusted table: trusted code may lower.
        let current = BundledMinimums.current
        let newerTable = BundledMinimums(asOf: DateDay(year: 2026, month: 10, day: 30)!, lines: current.lines,
                                         exploitedUnpatchedBelow: current.exploitedUnpatchedBelow)
        let fixed = try VersionFixtures.feed(VersionFixtures.iosToday)
        let snapshot = FeedState(feed: fixed, fetchedAt: VersionFixtures.fetchedAt, origin: .bundledSnapshot)
        clock.advance(seconds: 7 * 3600)
        let transport = FakeFeedTransport([.ok(try today(), etag: "fixed")])
        let buildB = FeedStore(platform: .ios, transport: transport, directory: directory, clock: clock.clock,
                               appVersion: "1.3", bundled: newerTable, snapshot: { snapshot })
        let floors = await buildB.minimumFloors()
        XCTAssertTrue(floors.isEmpty)
        let cachedFeed = await buildB.cachedFeed()
        XCTAssertNil(cachedFeed)
        let r16016 = await buildB.refresh()
        XCTAssertEqual(r16016, .updated)
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "If-None-Match"))
        await buildB.raiseMinimumFloors([26: OSVersion(26, 7, 1)])

        // Relaunching the same build keeps what it vetted.
        let again = FeedStore(platform: .ios, transport: FakeFeedTransport(), directory: directory, clock: clock.clock,
                              appVersion: "1.3", bundled: newerTable, snapshot: { snapshot })
        let kept = await again.minimumFloors()
        XCTAssertEqual(kept, [26: OSVersion(26, 7, 1)])
        let state = try await XCTUnwrapAsync(await again.cachedFeed())
        XCTAssertEqual(state.feed.osVersion(major: 26)?.highestVersion, OSVersion(26, 7, 1))
    }

    func testLatestAloneDoesNotRaiseTheRollbackBaseline() throws {
        // A `Latest` that points at a wrong (higher) build must not hold every later feed to it.
        let good = SOFAOSVersion(major: 26, securityReleases: [SOFARelease(productVersion: OSVersion(26, 7, 1))])
        var bad = good
        bad.latest = SOFARelease(productVersion: OSVersion(26, 70, 1))
        let empty = BundledMinimums(asOf: FeedStore.snapshotDate, lines: [:], exploitedUnpatchedBelow: [:])
        XCTAssertTrue(FeedStore.loweredMajors(new: SOFAFeed(osVersions: [good]), baseline: SOFAFeed(osVersions: [bad]),
                                              floors: [:], bundled: empty, platform: .ios).isEmpty)
        let lower = SOFAOSVersion(major: 26, securityReleases: [SOFARelease(productVersion: OSVersion(26, 7))])
        XCTAssertEqual(FeedStore.loweredMajors(new: SOFAFeed(osVersions: [lower]), baseline: SOFAFeed(osVersions: [good]),
                                               floors: [:], bundled: empty, platform: .ios), [26])
        let latestOnly = SOFAOSVersion(major: 27, latest: SOFARelease(productVersion: OSVersion(27, 0, 1)), securityReleases: [])
        XCTAssertEqual(latestOnly.highestSecurityVersion, OSVersion(27, 0, 1), "a line with only Latest still has a baseline")
    }

    func testOversizedBodyIsCancelledOnTheWire() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OversizedFeedProtocol.self]
        let transport = URLSessionFeedTransport(timeout: 5, maximumBytes: 64 * 1024, configuration: configuration)
        let request = URLRequest(url: FeedStore.feedURL(for: .ios))
        do {
            _ = try await transport.fetch(request)
            XCTFail("an oversized body must throw")
        } catch FeedTransportError.tooLarge {
        } catch {
            XCTFail("unexpected \(error)")
        }
        OversizedFeedProtocol.announceLength = true
        defer { OversizedFeedProtocol.announceLength = false }
        do {
            _ = try await transport.fetch(request)
            XCTFail("an announced oversized body must throw")
        } catch FeedTransportError.tooLarge {
        } catch {
            XCTFail("unexpected \(error)")
        }

        let store = FeedStore(platform: .ios, transport: transport, directory: directory, clock: clock.clock,
                              appVersion: "1.0", snapshot: { nil })
        let r19227 = await store.refresh()
        XCTAssertEqual(r19227, .decodeFailed)
        let cached = await store.cachedFeed()
        XCTAssertNil(cached)
    }
}

/// Serves a 200 whose body is far larger than the transport's cap, in chunks.
final class OversizedFeedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var announceLength = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let total = 4 * 1024 * 1024
        var headers = ["Content-Type": "application/json"]
        if OversizedFeedProtocol.announceLength { headers["Content-Length"] = "\(total)" }
        let url = request.url ?? URL(fileURLWithPath: "/")
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let chunk = Data(repeating: 0x20, count: 64 * 1024)
        for _ in 0..<(total / chunk.count) { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
