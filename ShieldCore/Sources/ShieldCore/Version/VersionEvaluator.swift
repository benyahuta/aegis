// "Am I patched?" (SPEC §5.2). Pure and synchronous: every input is passed in, including "now".
//
// Algorithm (§5.2):
//   1. bundledMin[platform][major] from BundledMinimums.
//   2. feedTarget = highest ProductVersion in OSVersions[major].SecurityReleases whose SupportedDevices
//      contains this identifier, or whose DeviceScope is "universal" and the major's device list includes it.
//   3. Effective minimum = max(bundledMin, lastGoodCachedMin, feedTarget) — raise-only.
//      (Rejecting a whole feed that would lower a minimum happens in FeedStore before it gets here.)
//   4. Version comparison only, never CVE presence. Actively exploited = a release above this version
//      with ActivelyExploitedCVEs, or a bundled exploitedUnpatchedBelow on this major.
//   5. Freshness from the age of the last good feed (the older of our fetch and SOFA's LastCheck): < 7 days normal; 7–30 days normal + "Last checked
//      N days ago"; > 30 days or never: below the minimum floor → fail (still true), else unknown.
//   6. Device support: in no patched major → fail; highest major not current but still patched →
//      pass + a local "aging" note for Ben.
//
// H7: missing or stale data is unknown, never pass. Nothing here is synced except the two Status values.

import Foundation

// MARK: - Feed state and freshness

/// The last good feed and when it was fetched (or confirmed with a 304).
public struct FeedState: Sendable, Hashable {
    public enum Origin: String, Sendable, Hashable {
        /// Fetched (or revalidated) from the network this session.
        case network
        /// Loaded from the Application Support cache.
        case cache
        /// The snapshot compiled into the app (last resort). `fetchedAt` is the snapshot date.
        case bundledSnapshot
    }

    public var feed: SOFAFeed
    public var fetchedAt: Date
    public var origin: Origin

    public init(feed: SOFAFeed, fetchedAt: Date, origin: Origin) {
        self.feed = feed
        self.fetchedAt = fetchedAt
        self.origin = origin
    }

    /// The date the data is known good as of: our fetch (or 304) time, or SOFA's own `LastCheck`
    /// when that is older. A stalled upstream pipeline keeps answering 200/304 with the same old
    /// body, so our fetch time alone would call it fresh forever (§5.2 step 5, H7). A `LastCheck`
    /// later than our fetch (clock skew) is ignored.
    public var dataDate: Date {
        guard let lastCheck = feed.lastCheck else { return fetchedAt }
        return min(fetchedAt, lastCheck)
    }
}

public enum FeedFreshness: Sendable, Hashable {
    /// Under 7 days old.
    case fresh(ageDays: Int)
    /// 7–30 days old: still used, plus "Last checked N days ago".
    case aging(ageDays: Int)
    /// Over 30 days old (or dated in the future by more than a day, which is not trusted).
    case stale(ageDays: Int)
    /// No feed has ever been fetched.
    case never

    public static let agingAfterDays = 7
    public static let staleAfterDays = 30

    public static func of(fetchedAt: Date?, now: Date) -> FeedFreshness {
        guard let fetchedAt else { return .never }
        let seconds = now.timeIntervalSince(fetchedAt)
        if seconds < -86_400 { return .stale(ageDays: Int((seconds / 86_400).rounded(.towardZero))) }
        let days = max(0, Int((seconds / 86_400).rounded(.down)))
        if days < agingAfterDays { return .fresh(ageDays: days) }
        if days <= staleAfterDays { return .aging(ageDays: days) }
        return .stale(ageDays: days)
    }

    /// Freshness of `state`, aged from `FeedState.dataDate` (the older of our fetch and SOFA's
    /// `LastCheck`).
    public static func of(_ state: FeedState?, now: Date) -> FeedFreshness {
        of(fetchedAt: state?.dataDate, now: now)
    }

    /// Fresh or aging: the feed may decide pass/fail.
    public var isUsable: Bool {
        switch self {
        case .fresh, .aging: true
        case .stale, .never: false
        }
    }

    /// N for "Last checked N days ago"; only set when 7–30 days old.
    public var lastCheckedDays: Int? {
        if case .aging(let days) = self { return days }
        return nil
    }

    /// `LocalInfoID.feedFresh` (§6.5): pass when fresh, unknown when aging, fail when stale or never.
    public var feedFreshStatus: Status {
        switch self {
        case .fresh: .pass
        case .aging: .unknown
        case .stale, .never: .fail
        }
    }
}

// MARK: - Result

public struct VersionEvaluation: Sendable, Hashable {
    public enum PatchOutcome: String, Sendable, Hashable {
        /// "Your iPhone/Mac has the latest safety fixes."
        case patched
        /// "An update with safety fixes is ready."
        case updateAvailable
        /// "Please update … today. Apple fixed a problem that criminals are already using."
        case updateExploited
        /// This OS line gets no fixes any more (e.g. macOS 13); the device must move to a newer major.
        case osLineUnsupported
        /// "Can't confirm. Check Software Update."
        case cantConfirm
    }

    public enum SupportOutcome: Sendable, Hashable {
        /// Runs the newest major.
        case current
        /// Still patched, but its newest major is not the current one. Local amber note for Ben only.
        case aging(highestMajor: Int)
        /// Apple no longer ships fixes for this model ("replace").
        case unsupported
        /// Not enough data.
        case unknown
    }

    /// `os_patched`.
    public var osPatched: Status
    /// Tier of `os_patched` when it fails: red if exploited, otherwise amber (§6.1/§6.2).
    public var osPatchedTier: Tier
    public var patchOutcome: PatchOutcome
    /// An actively exploited bug is fixed in a release above this device's version.
    public var exploited: Bool

    /// `device_supported` (tier amber on fail).
    public var deviceSupported: Status
    public var supportOutcome: SupportOutcome

    public var freshness: FeedFreshness
    /// N for "Last checked N days ago" (7–30 days), else nil.
    public var lastCheckedDays: Int? { freshness.lastCheckedDays }

    /// The running version and the minimums that decided the result. Local only (§12.2).
    public var osVersion: OSVersion
    public var bundledMinimum: OSVersion?
    public var cachedMinimum: OSVersion?
    public var feedTarget: OSVersion?
    public var effectiveMinimum: OSVersion?

    /// `cachedMinimums` raised by this evaluation. Persist it (`FeedStore.raiseMinimumFloors`) so the
    /// next evaluation can never accept a lower minimum (raise-only).
    public var minimumsToRemember: [Int: OSVersion]

    /// The two measured results this evaluator owns, ready for a `ResultSink`.
    public func checkResults(deviceID: UUID, checkedOn: DateDay, catalogVersion: Int) -> [CheckResult] {
        [
            CheckResult(deviceID: deviceID, checkID: .osPatched, status: osPatched, source: .measured,
                        checkedOn: checkedOn, catalogVersion: catalogVersion),
            CheckResult(deviceID: deviceID, checkID: .deviceSupported, status: deviceSupported, source: .measured,
                        checkedOn: checkedOn, catalogVersion: catalogVersion),
        ]
    }
}

// MARK: - Evaluator

public struct VersionEvaluator: Sendable {
    public struct Input: Sendable, Hashable {
        public var platform: Platform
        public var osVersion: OSVersion
        public var device: DeviceIdentifier
        /// The last good feed (already accepted by FeedStore's raise-only check), if any.
        public var feed: FeedState?
        /// Last good per-major minimums for this device (`lastGoodCachedMin`).
        public var cachedMinimums: [Int: OSVersion]
        public var now: Date

        public init(
            platform: Platform,
            osVersion: OSVersion,
            device: DeviceIdentifier,
            feed: FeedState?,
            cachedMinimums: [Int: OSVersion] = [:],
            now: Date
        ) {
            self.platform = platform
            self.osVersion = osVersion
            self.device = device
            self.feed = feed
            self.cachedMinimums = cachedMinimums
            self.now = now
        }

        /// This device, now.
        public static func current(feed: FeedState?, cachedMinimums: [Int: OSVersion] = [:], clock: Clock = .system) -> Input {
            Input(platform: .current, osVersion: .running, device: .current, feed: feed,
                  cachedMinimums: cachedMinimums, now: clock.now())
        }
    }

    public let bundled: BundledMinimums

    public init(bundled: BundledMinimums = .current) {
        self.bundled = bundled
    }

    public func evaluate(_ input: Input) -> VersionEvaluation {
        let platform = input.platform
        let version = input.osVersion
        let major = version.major
        let device = input.device
        let freshness = FeedFreshness.of(input.feed, now: input.now)
        let feed = input.feed?.feed

        let bundledMin = bundled.minimum(platform: platform, major: major, device: device)
        let cachedMin = input.cachedMinimums[major]
        let feedTarget = feed.flatMap { VersionEvaluator.target(in: $0, platform: platform, major: major, device: device, runningMajor: major) }

        // Step 3: raise-only. A stale feed's target does not count (it can't be confirmed), but the
        // floors (bundled + last good cached) still do.
        let floor = [bundledMin, cachedMin].compactMap { $0 }.max()
        let effective = freshness.isUsable ? [floor, feedTarget].compactMap { $0 }.max() : floor

        // Step 4: exploited. A release above us that fixed an exploited bug is still true when stale.
        let exploited = bundled.knownExploited(platform: platform, version: version)
            || (feed.map { VersionEvaluator.exploitedAbove(in: $0, platform: platform, version: version, device: device) } ?? false)

        let (status, outcome) = VersionEvaluator.patchDecision(
            version: version,
            lineState: lineState(platform: platform, major: major, feed: feed, feedTarget: feedTarget, cachedMin: cachedMin),
            freshness: freshness,
            floor: floor,
            effective: effective,
            exploited: exploited
        )

        var remembered = input.cachedMinimums
        if freshness.isUsable, let effective, outcome != .osLineUnsupported {
            remembered[major] = max(effective, remembered[major] ?? effective)
        }

        let (supportStatus, support) = deviceSupport(platform: platform, device: device, runningMajor: major, feed: feed)

        let evaluation = VersionEvaluation(
            osPatched: status,
            osPatchedTier: outcome == .updateExploited ? .red : .amber,
            patchOutcome: outcome,
            exploited: exploited && outcome != .patched,
            deviceSupported: supportStatus,
            supportOutcome: support,
            freshness: freshness,
            osVersion: version,
            bundledMinimum: bundledMin,
            cachedMinimum: cachedMin,
            feedTarget: feedTarget,
            effectiveMinimum: effective,
            minimumsToRemember: remembered
        )
        Log.version.info("""
            os_patched=\(status.rawValue, privacy: .public) outcome=\(outcome.rawValue, privacy: .public) \
            device_supported=\(supportStatus.rawValue, privacy: .public) version=\(version.description, privacy: .private) \
            min=\(effective?.description ?? "-", privacy: .private)
            """)
        return evaluation
    }

    // MARK: Step 1/3/5: line state and the pass/fail decision

    enum LineState: Equatable {
        /// Bundled (or the feed, for a major newer than the table) patches this line.
        case patched
        /// Older than every patched major.
        case unsupported
        /// Newer than the table (or an unknown gap) and the feed doesn't cover it.
        case unknown
    }

    func lineState(platform: Platform, major: Int, feed: SOFAFeed?, feedTarget: OSVersion?, cachedMin: OSVersion?) -> LineState {
        if bundled.lines[platform]?[major] != nil { return .patched }
        guard let oldest = bundled.oldestPatchedMajor(for: platform), let newest = bundled.currentMajor(for: platform) else {
            return feedTarget != nil || cachedMin != nil ? .patched : .unknown
        }
        if major < oldest { return .unsupported }
        if major > newest, feedTarget != nil || cachedMin != nil { return .patched }
        return .unknown
    }

    static func patchDecision(
        version: OSVersion,
        lineState: LineState,
        freshness: FeedFreshness,
        floor: OSVersion?,
        effective: OSVersion?,
        exploited: Bool
    ) -> (Status, VersionEvaluation.PatchOutcome) {
        let failing: VersionEvaluation.PatchOutcome = exploited ? .updateExploited : .updateAvailable
        switch lineState {
        case .unsupported:
            // True whatever the feed says: this major gets no more fixes.
            return (.fail, .osLineUnsupported)
        case .unknown, .patched:
            if freshness.isUsable {
                guard let effective else { return (.unknown, .cantConfirm) }
                return version >= effective ? (.pass, .patched) : (.fail, failing)
            }
            // Stale or never fetched: being below a raise-only floor is still true; anything else
            // can't be confirmed (H7).
            if let floor, version < floor { return (.fail, failing) }
            return (.unknown, .cantConfirm)
        }
    }

    // MARK: Step 2: feed target

    /// True when `device` belongs to `major` in `feed` ("the major's device list includes it").
    static func deviceIsInMajor(feed: SOFAFeed, platform: Platform, major: Int, device: DeviceIdentifier, runningMajor: Int?) -> Bool {
        if major == runningMajor { return true }
        guard let line = feed.osVersion(major: major) else { return false }
        let list = line.deviceList
        if device.feedIdentifiers.contains(where: list.contains) { return true }
        if platform == .mac, let majors = macModelMajors(feed: feed, device: device), majors.contains(major) { return true }
        return false
    }

    /// The majors a Mac model can run, from `Models[hw.model]` (or via `Devices[boardID].DeviceID`).
    static func macModelMajors(feed: SOFAFeed, device: DeviceIdentifier) -> [Int]? {
        if let model = device.modelIdentifier, let entry = feed.models[model] { return entry.osVersions }
        if let board = device.boardID, let model = feed.devices[board]?.deviceID, let entry = feed.models[model] {
            return entry.osVersions
        }
        return nil
    }

    /// Releases of `major` that apply to `device`. `targetOnly` limits them to the releases that
    /// may set `feedTarget` (`SOFAOSVersion.targetReleases`).
    static func applicableReleases(feed: SOFAFeed, platform: Platform, major: Int, device: DeviceIdentifier, runningMajor: Int?,
                                   targetOnly: Bool = false) -> [SOFARelease] {
        guard let line = feed.osVersion(major: major) else { return [] }
        let inMajor = deviceIsInMajor(feed: feed, platform: platform, major: major, device: device, runningMajor: runningMajor)
        let ids = device.feedIdentifiers
        return (targetOnly ? line.targetReleases : line.allReleases).filter { release in
            if ids.contains(where: release.supportedDevices.contains) { return true }
            switch release.deviceScope {
            case .universal:
                return inMajor
            case .unspecified:
                // No scope and no list (e.g. old v1-style entries): treat like universal.
                return release.supportedDevices.isEmpty && inMajor
            case .deviceSpecific, .other:
                return false
            }
        }
    }

    /// §5.2 step 2: the highest applicable `SecurityReleases` version (`Latest` only for a line
    /// with no `SecurityReleases`). nil when the feed has nothing for this device on this major.
    public static func target(in feed: SOFAFeed, platform: Platform, major: Int, device: DeviceIdentifier, runningMajor: Int?) -> OSVersion? {
        applicableReleases(feed: feed, platform: platform, major: major, device: device, runningMajor: runningMajor, targetOnly: true)
            .map(\.productVersion)
            .max()
    }

    /// §5.2 step 4, feed half: a release above `version` on its major, for this device, that fixes an
    /// actively exploited CVE.
    public static func exploitedAbove(in feed: SOFAFeed, platform: Platform, version: OSVersion, device: DeviceIdentifier) -> Bool {
        applicableReleases(feed: feed, platform: platform, major: version.major, device: device, runningMajor: version.major)
            .contains { $0.productVersion > version && $0.fixesActivelyExploited }
    }

    // MARK: Step 6: device support

    /// Patched majors: the bundled table, plus any feed major newer than the table (minimums only rise).
    func patchedMajors(platform: Platform, feed: SOFAFeed?) -> Set<Int> {
        var majors = Set(bundled.majors(for: platform))
        if let feed, let newest = bundled.currentMajor(for: platform) {
            for line in feed.osVersions where line.major > newest && !line.allReleases.isEmpty {
                majors.insert(line.major)
            }
        }
        return majors
    }

    func deviceSupport(platform: Platform, device: DeviceIdentifier, runningMajor: Int, feed: SOFAFeed?) -> (Status, VersionEvaluation.SupportOutcome) {
        let patched = patchedMajors(platform: platform, feed: feed)
        guard let current = patched.max() else { return (.unknown, .unknown) }

        // What we know this model can run, best source first.
        var supported: Set<Int>?
        var fromRunningOnly = false
        if let feed, VersionEvaluator.feedKnows(feed: feed, platform: platform, device: device) {
            supported = Set(feed.majors.filter {
                VersionEvaluator.deviceIsInMajor(feed: feed, platform: platform, major: $0, device: device, runningMajor: nil)
            }).intersection(patched)
        } else {
            switch bundled.deviceKnowledge(platform: platform, device: device) {
            case .unsupported:
                return (.fail, .unsupported)
            case .supported(let highest):
                supported = Set(patched.filter { $0 <= highest })
            case .unknown:
                supported = nil
            }
        }
        // A device running a patched major is supported at least on that major.
        if patched.contains(runningMajor) {
            if supported == nil { fromRunningOnly = true }
            supported = (supported ?? []).union([runningMajor])
        }

        guard let supported else { return (.unknown, .unknown) }
        guard let highest = supported.max() else { return (.fail, .unsupported) }
        if highest >= current || fromRunningOnly { return (.pass, .current) }
        return (.pass, .aging(highestMajor: highest))
    }

    /// True when the feed lists this model anywhere (so its silence about a major means "not supported").
    static func feedKnows(feed: SOFAFeed, platform: Platform, device: DeviceIdentifier) -> Bool {
        let ids = device.feedIdentifiers
        guard !ids.isEmpty else { return false }
        if ids.contains(where: { feed.devices[$0] != nil }) { return true }
        if platform == .mac, macModelMajors(feed: feed, device: device) != nil { return true }
        return feed.osVersions.contains { line in ids.contains(where: line.deviceList.contains) }
    }
}
