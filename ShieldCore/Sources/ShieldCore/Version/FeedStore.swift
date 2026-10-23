// Fetches, vets and caches the SOFA v2 feed (SPEC §5.2 FeedStore, P0, direct SOFA).
//
//   - GET https://sofafeed.macadmins.io/v2/ios_data_feed.json (iOS) or .../macos_data_feed.json (Mac).
//   - Headers: User-Agent "FamilyShield/<version> (+<contact>)", If-None-Match "<etag>".
//   - Timeout 15 s. At most one fetch per 6 h (attempts count, success or not).
//   - Any decode failure → the fetch is ignored and the cache kept.
//   - Raise-only: a feed that would lower any major's minimum below the cached feed, the cached
//     floors or the bundled table is rejected as a whole; the cache is kept and `feed.rejected` is
//     logged privately.
//   - The last good copy lives in Application Support. The bundled snapshot is used when there is
//     no cache, or when it is newer than the cache (a fresh build on a long-offline device).
//   - Trusted code may lower, feeds may not: when the running build's bundled table is newer than the
//     one the cache and floors were vetted under, the cache and floors are reset to the new build's
//     table and snapshot, so one upstream overshoot can't pin minimums across app updates.
//
// The feed only ever carries version numbers, identifiers and booleans into the app (H6). Nothing
// fetched here is synced or shown as text.

import Foundation

// MARK: - Transport

/// The network seam. Production uses `URLSessionFeedTransport`; tests inject a fake.
public protocol FeedTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum FeedTransportError: Error, Sendable {
    case notHTTP
    /// The body is (or announces itself as) larger than the cap; the download was cancelled.
    case tooLarge
}

/// An ephemeral URLSession: no cookies, no shared URL cache (we do conditional requests ourselves).
/// The body is streamed and the download is cancelled as soon as it passes `maximumBytes`, so an
/// oversized response can't exhaust memory or data before the size check runs.
public struct URLSessionFeedTransport: FeedTransport {
    private let session: URLSession
    private let maximumBytes: Int

    public init(timeout: TimeInterval = FeedStore.timeout, maximumBytes: Int = FeedStore.maximumBodyBytes) {
        self.init(timeout: timeout, maximumBytes: maximumBytes, configuration: .ephemeral)
    }

    /// Tests pass a configuration with a stub `URLProtocol`.
    init(timeout: TimeInterval, maximumBytes: Int, configuration: URLSessionConfiguration) {
        self.maximumBytes = maximumBytes
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    public func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw FeedTransportError.notHTTP
        }
        if http.expectedContentLength > Int64(maximumBytes) {
            bytes.task.cancel()
            throw FeedTransportError.tooLarge
        }
        var data = Data()
        data.reserveCapacity(Int(min(max(http.expectedContentLength, 0), Int64(maximumBytes))))
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                bytes.task.cancel()
                throw FeedTransportError.tooLarge
            }
            data.append(byte)
        }
        return (data, http)
    }
}

// MARK: - Store

public actor FeedStore {
    /// What one `refresh` did.
    public enum RefreshOutcome: String, Sendable, Hashable {
        /// Skipped: the last attempt was under 6 h ago.
        case throttled
        /// 200 with a valid, non-rollback feed: cached.
        case updated
        /// 304: the cached feed is still current; its fetch time was renewed.
        case notModified
        /// Decoded but would lower a minimum: rejected as a whole, cache kept (`feed.rejected`).
        case rejectedRollback
        /// Body did not decode (truncated, wrong shape): ignored, cache kept.
        case decodeFailed
        /// Non-200/304 status, or a 304 with nothing cached: ignored.
        case httpError
        /// Transport error or timeout: ignored.
        case networkFailed
    }

    public static let timeout: TimeInterval = 15
    public static let minimumInterval: TimeInterval = 6 * 60 * 60
    /// Bodies larger than this are refused (the macOS v2 feed is ~320 KB).
    public static let maximumBodyBytes = 8 * 1024 * 1024
    /// Contact URL in the User-Agent, as SOFA asks of integrators (§5.2).
    public static let userAgentContact = "https://github.com/benyahuta/aegis"

    public static let feedHost = "sofafeed.macadmins.io"

    /// https://sofafeed.macadmins.io/v2/ios_data_feed.json or .../macos_data_feed.json.
    /// Built from components (the §12.4 lint forbids ad-hoc string URLs outside the catalog files).
    public static func feedURL(for platform: Platform) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = feedHost
        components.path = "/v2/\(fileStem(platform))_data_feed.json"
        // Always non-nil for these fixed parts; the fallback only exists so this can never trap.
        return components.url ?? URL(fileURLWithPath: "/dev/null")
    }

    public static func userAgent(appVersion: String) -> String {
        "FamilyShield/\(appVersion) (+\(userAgentContact))"
    }

    public nonisolated let platform: Platform
    private let transport: any FeedTransport
    private let directory: URL
    private let clock: Clock
    private let appVersion: String
    private let bundled: BundledMinimums
    private let snapshotLoader: @Sendable () -> FeedState?

    private var cachedState: FeedState?
    private var metadata: Metadata
    private var loaded = false

    /// - Parameters:
    ///   - directory: where the cache lives. Defaults to `FeedStore.defaultDirectory()`.
    ///   - snapshot: the last-resort feed. Defaults to the snapshot bundled in ShieldCore.
    public init(
        platform: Platform = .current,
        transport: any FeedTransport = URLSessionFeedTransport(),
        directory: URL? = nil,
        clock: Clock = .system,
        appVersion: String = FeedStore.bundleShortVersion(),
        bundled: BundledMinimums = .current,
        snapshot: (@Sendable () -> FeedState?)? = nil
    ) {
        self.platform = platform
        self.transport = transport
        self.directory = directory ?? FeedStore.defaultDirectory()
        self.clock = clock
        self.appVersion = appVersion
        self.bundled = bundled
        self.snapshotLoader = snapshot ?? { FeedStore.bundledSnapshot(for: platform) }
        self.metadata = Metadata()
    }

    // MARK: Reading

    /// The best feed available: whichever of the cached last good feed and the bundled snapshot has
    /// the newer data (`FeedState.dataDate`); the cache wins a tie. nil only if both are missing or
    /// unreadable.
    public func currentFeed() -> FeedState? {
        loadIfNeeded()
        let snapshot = snapshotLoader()
        guard let cachedState else { return snapshot }
        guard let snapshot, snapshot.dataDate > cachedState.dataDate else { return cachedState }
        return snapshot
    }

    /// The cached (network-sourced) feed only, without the snapshot fallback.
    public func cachedFeed() -> FeedState? {
        loadIfNeeded()
        return cachedState
    }

    /// When the last network attempt happened (for the 6 h throttle).
    public func lastAttempt() -> Date? {
        loadIfNeeded()
        return metadata.lastAttemptAt
    }

    /// The raise-only per-major floors for this device (`lastGoodCachedMin`).
    public func minimumFloors() -> [Int: OSVersion] {
        loadIfNeeded()
        var floors: [Int: OSVersion] = [:]
        for (key, value) in metadata.floors {
            if let major = Int(key), let version = OSVersion(value), version.major == major { floors[major] = version }
        }
        return floors
    }

    /// Merges `floors` into the stored floors, keeping the higher value per major. Never lowers.
    public func raiseMinimumFloors(_ floors: [Int: OSVersion]) {
        loadIfNeeded()
        var current = minimumFloors()
        var changed = false
        for (major, version) in floors where version.major == major {
            if let existing = current[major], existing >= version { continue }
            current[major] = version
            changed = true
        }
        guard changed else { return }
        metadata.floors = Dictionary(uniqueKeysWithValues: current.map { (String($0.key), $0.value.description) })
        saveMetadata()
    }

    // MARK: Refreshing

    /// Fetches the feed unless the last attempt was under 6 h ago. Never throws: every failure keeps
    /// the cache and is reported as an outcome.
    @discardableResult
    public func refresh(force: Bool = false) async -> RefreshOutcome {
        loadIfNeeded()
        let now = clock.now()
        if !force, let last = metadata.lastAttemptAt, now.timeIntervalSince(last) < FeedStore.minimumInterval,
           now.timeIntervalSince(last) >= 0 {
            return .throttled
        }
        metadata.lastAttemptAt = now
        saveMetadata()

        var request = URLRequest(url: FeedStore.feedURL(for: platform), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: FeedStore.timeout)
        request.httpMethod = "GET"
        request.setValue(FeedStore.userAgent(appVersion: appVersion), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if cachedState != nil, let etag = metadata.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.fetch(request)
        } catch FeedTransportError.tooLarge {
            Log.feed.notice("feed.decode_failed reason=too_large")
            return .decodeFailed
        } catch {
            Log.feed.notice("feed.network_failed")
            return .networkFailed
        }

        switch response.statusCode {
        case 304:
            guard var state = cachedState else {
                Log.feed.notice("feed.http_error status=304")
                return .httpError
            }
            state.fetchedAt = now
            state.origin = .network
            cachedState = state
            metadata.fetchedAt = now
            saveMetadata()
            Log.feed.info("feed.not_modified")
            return .notModified
        case 200:
            break
        default:
            Log.feed.notice("feed.http_error status=\(response.statusCode, privacy: .public)")
            return .httpError
        }

        guard data.count <= FeedStore.maximumBodyBytes, let feed = SOFAFeed.decode(data) else {
            Log.feed.notice("feed.decode_failed")
            return .decodeFailed
        }

        // Raise-only against both the cache and the bundled snapshot (whichever is higher per major).
        let floors = minimumFloors()
        var lowered = Set(FeedStore.loweredMajors(new: feed, baseline: cachedState?.feed, floors: floors,
                                                  bundled: bundled, platform: platform))
        if let snapshot = snapshotLoader()?.feed {
            lowered.formUnion(FeedStore.loweredMajors(new: feed, baseline: snapshot, floors: floors,
                                                      bundled: bundled, platform: platform))
        }
        if !lowered.isEmpty {
            Log.feed.notice("feed.rejected majors=\(lowered.sorted(by: >).map(String.init).joined(separator: ","), privacy: .private)")
            return .rejectedRollback
        }

        cachedState = FeedState(feed: feed, fetchedAt: now, origin: .network)
        do {
            try writeCache(data)
            metadata.fetchedAt = now
            metadata.etag = response.value(forHTTPHeaderField: "ETag")
        } catch {
            // Still use the good feed for this session. The metadata must keep describing the body
            // that is on disk: leave its fetch time alone and drop the ETag, so the next launch
            // ages the old body correctly and the next refresh asks for a full body (a 304 against
            // the new ETag would otherwise renew the old body as fresh).
            metadata.etag = nil
            Log.feed.error("feed.cache_write_failed")
        }
        saveMetadata()
        Log.feed.info("feed.updated")
        return .updated
    }

    // MARK: Raise-only

    /// Majors whose highest security release in `new` is below the baseline feed, the stored floors,
    /// or the bundled table's highest minimum. Non-empty → reject the whole feed (§5.2 step 3).
    /// A major that the new feed omits is not a lowering (SOFA drops old lines). `Latest` only counts
    /// for a major with no `SecurityReleases` (`highestSecurityVersion`), so a `Latest` pointing at a
    /// non-security or wrong build can't become the baseline every later feed is held to.
    public static func loweredMajors(
        new: SOFAFeed,
        baseline: SOFAFeed?,
        floors: [Int: OSVersion],
        bundled: BundledMinimums,
        platform: Platform
    ) -> [Int] {
        var lowered: [Int] = []
        for major in new.majors {
            guard let highest = new.osVersion(major: major)?.highestSecurityVersion else {
                lowered.append(major)
                continue
            }
            var floor: OSVersion?
            if let previous = baseline?.osVersion(major: major)?.highestSecurityVersion { floor = previous }
            if let stored = floors[major] { floor = max(floor ?? stored, stored) }
            if let table = bundled.highestMinimum(platform: platform, major: major) { floor = max(floor ?? table, table) }
            if let floor, highest < floor { lowered.append(major) }
        }
        return lowered.sorted(by: >)
    }

    // MARK: Files

    struct Metadata: Codable, Equatable {
        var etag: String?
        var fetchedAt: Date?
        var lastAttemptAt: Date?
        /// major (as a string) → version string.
        var floors: [String: String] = [:]
        /// `BundledMinimums.asOf` (YYYY-MM-DD) of the build that vetted the cache and floors.
        var bundledAsOf: String?
    }

    private var feedFileURL: URL { directory.appendingPathComponent("\(FeedStore.fileStem(platform))_v2.json") }
    private var metadataFileURL: URL { directory.appendingPathComponent("\(FeedStore.fileStem(platform))_v2.meta.json") }

    static func fileStem(_ platform: Platform) -> String {
        switch platform {
        case .ios: "ios"
        case .mac: "macos"
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: metadataFileURL),
           let decoded = try? FeedStore.decoder.decode(Metadata.self, from: data) {
            metadata = decoded
        }
        let vettedUnder = metadata.bundledAsOf.flatMap { DateDay(iso8601: $0) }
        if vettedUnder.map({ $0 < bundled.asOf }) ?? true {
            // A newer trusted build (or the first run of one that records this). Trusted code may
            // lower, feeds may not: drop the cache and the floors so the new build's table and
            // snapshot are the raise-only baseline again. The throttle stays.
            if vettedUnder != nil || !metadata.floors.isEmpty || metadata.fetchedAt != nil {
                Log.feed.notice("feed.rebaselined")
            }
            metadata.floors = [:]
            metadata.etag = nil
            metadata.fetchedAt = nil
            metadata.bundledAsOf = bundled.asOf.description
            try? FileManager.default.removeItem(at: feedFileURL)
            saveMetadata()
            return
        }
        if let fetchedAt = metadata.fetchedAt,
           let data = try? Data(contentsOf: feedFileURL),
           let feed = SOFAFeed.decode(data) {
            cachedState = FeedState(feed: feed, fetchedAt: fetchedAt, origin: .cache)
        } else {
            // A cache without a readable feed is no cache; drop the ETag so we get a full body.
            metadata.etag = nil
            metadata.fetchedAt = nil
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func writeCache(_ data: Data) throws {
        try ensureDirectory()
        try data.write(to: feedFileURL, options: [.atomic])
        FeedStore.excludeFromBackup(feedFileURL)
    }

    private func saveMetadata() {
        do {
            try ensureDirectory()
            let data = try FeedStore.encoder.encode(metadata)
            try data.write(to: metadataFileURL, options: [.atomic])
            FeedStore.excludeFromBackup(metadataFileURL)
        } catch {
            Log.feed.error("feed.metadata_write_failed")
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    // MARK: Defaults

    /// `Application Support/<FS_ID_PREFIX>/Feed`. Falls back to the temporary
    /// directory if Application Support can't be resolved (the app must never crash).
    public static func defaultDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(Log.subsystem, isDirectory: true)
            .appendingPathComponent("Feed", isDirectory: true)
    }

    /// `CFBundleShortVersionString` of the main bundle, or "1.0".
    public static func bundleShortVersion() -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let value, OSVersion(value) != nil else { return "1.0" }
        return value
    }

    /// The date the bundled snapshot was captured. Its freshness ages from here.
    public static let snapshotDate = DateDay(year: 2026, month: 10, day: 22)!

    /// The snapshot compiled into ShieldCore (`Version/snapshot/ios_min.json` / `mac_min.json`).
    public static func bundledSnapshot(for platform: Platform) -> FeedState? {
        let name = platform == .ios ? "ios_min" : "mac_min"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "snapshot")
                ?? Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let feed = SOFAFeed.decode(data)
        else {
            Log.feed.error("feed.snapshot_missing")
            return nil
        }
        return FeedState(feed: feed, fetchedAt: snapshotDate.date, origin: .bundledSnapshot)
    }
}
