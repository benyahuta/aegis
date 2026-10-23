// VersionEvaluator → MacVersionAssessing (SPEC §5.2, §6.2).
//
// `FeedMacVersionAssessor` is what the Mac app uses: it refreshes the SOFA feed through FeedStore
// (6 h throttle, ETag, raise-only), evaluates this Mac with VersionEvaluator, persists the raised
// per-major floors, and maps the result onto `MacVersionAssessment`.
// `BundledMacVersionAssessor` is the same evaluator with no feed at all (§5.2 step 5, "never
// fetched"): below the bundled minimum → fail, otherwise unknown. Neither one ever turns missing or
// stale data into a pass (H7).
//
// Versions, model IDs and CVE IDs stay on this Mac (H5, §12.2): they are only used to pick
// pass/fail/unknown and a tier.

import Foundation

public enum MacVersionAdapter {
    /// The CVE behind the bundled `exploitedUnpatchedBelow` entries (§5.2 step 1).
    public static let bundledExploitedCVE = "CVE-2026-86950"

    /// The evaluator input for this Mac.
    public static func input(
        for identity: MacDeviceIdentity,
        feed: FeedState?,
        cachedMinimums: [Int: OSVersion],
        now: Date
    ) -> VersionEvaluator.Input {
        VersionEvaluator.Input(
            platform: .mac,
            osVersion: OSVersion(identity.osMajor, identity.osMinor, identity.osPatch),
            device: DeviceIdentifier(modelIdentifier: identity.modelID, boardID: identity.boardID),
            feed: feed,
            cachedMinimums: cachedMinimums,
            now: now
        )
    }

    /// Maps an evaluation (and the feed it was made from) onto what the Mac checks need.
    public static func assessment(
        from evaluation: VersionEvaluation,
        input: VersionEvaluator.Input,
        bundled: BundledMinimums = .current
    ) -> MacVersionAssessment {
        let failing = evaluation.osPatched == .fail
        let agingDevice: Bool
        if case .aging = evaluation.supportOutcome { agingDevice = true } else { agingDevice = false }
        return MacVersionAssessment(
            osPatched: evaluation.osPatched,
            // Same rule as VersionEvaluation.osPatchedTier: red only when a fix for an exploited bug
            // is out for this line (an unsupported line is amber).
            activelyExploited: evaluation.patchOutcome == .updateExploited,
            unpatchedExploitedCVEs: failing ? unpatchedExploitedCVEs(input: input, bundled: bundled) : [],
            deviceSupported: evaluation.deviceSupported,
            agingDevice: agingDevice,
            xprotectFeed: evaluation.freshness.isUsable ? xprotectFeed(input.feed?.feed) : nil
        )
    }

    /// One-shot evaluation (pure; no I/O).
    public static func assess(
        _ identity: MacDeviceIdentity,
        feed: FeedState?,
        cachedMinimums: [Int: OSVersion] = [:],
        now: Date,
        evaluator: VersionEvaluator = VersionEvaluator()
    ) -> (assessment: MacVersionAssessment, evaluation: VersionEvaluation) {
        let input = input(for: identity, feed: feed, cachedMinimums: cachedMinimums, now: now)
        let evaluation = evaluator.evaluate(input)
        return (assessment(from: evaluation, input: input, bundled: evaluator.bundled), evaluation)
    }

    /// Exploited CVEs fixed in a release above this Mac's version on its own major (§5.2 step 4),
    /// plus the bundled entry when it applies. Like `exploited`, a stale feed still counts: a
    /// release that already shipped stays true.
    static func unpatchedExploitedCVEs(input: VersionEvaluator.Input, bundled: BundledMinimums) -> Set<String> {
        var cves = Set<String>()
        if bundled.knownExploited(platform: .mac, version: input.osVersion) {
            cves.insert(bundledExploitedCVE)
        }
        if let feed = input.feed?.feed {
            let releases = VersionEvaluator.applicableReleases(
                feed: feed, platform: .mac, major: input.osVersion.major, device: input.device,
                runningMajor: input.osVersion.major
            )
            for release in releases where release.productVersion > input.osVersion {
                cves.formUnion(release.activelyExploitedCVEs)
            }
        }
        return cves
    }

    /// The feed's XProtect versions in the form `xprotect_current` compares against.
    static func xprotectFeed(_ feed: SOFAFeed?) -> XProtectFeedVersions? {
        guard let x = feed?.xProtect else { return nil }
        let config = x.plistConfigVersion.flatMap { $0.isEmpty ? nil : $0 }
        let payloads = x.xprotectVersion.flatMap { $0.isEmpty ? nil : $0 }
        guard config != nil || payloads != nil else { return nil }
        return XProtectFeedVersions(plistConfigData: config, payloads: payloads)
    }
}

/// The Mac app's assessor: FeedStore (macOS feed) + VersionEvaluator.
public struct FeedMacVersionAssessor: MacVersionAssessing {
    public let store: FeedStore
    public let evaluator: VersionEvaluator
    /// false skips the network refresh and uses the cache / bundled snapshot only.
    public let refreshFeed: Bool

    public init(store: FeedStore, evaluator: VersionEvaluator = VersionEvaluator(), refreshFeed: Bool = true) {
        self.store = store
        self.evaluator = evaluator
        self.refreshFeed = refreshFeed
    }

    public func assess(_ identity: MacDeviceIdentity, now: Date) async -> MacVersionAssessment {
        if refreshFeed {
            // Throttled to one attempt per 6 h; every failure keeps the cache.
            _ = await store.refresh()
        }
        let feed = await store.currentFeed()
        let floors = await store.minimumFloors()
        let result = MacVersionAdapter.assess(identity, feed: feed, cachedMinimums: floors, now: now, evaluator: evaluator)
        await store.raiseMinimumFloors(result.evaluation.minimumsToRemember)
        return result.assessment
    }
}

/// VersionEvaluator with no feed (§5.2 step 5, "never fetched"). Never reports `os_patched` pass.
public struct BundledMacVersionAssessor: MacVersionAssessing {
    public let evaluator: VersionEvaluator

    public init(evaluator: VersionEvaluator = VersionEvaluator()) {
        self.evaluator = evaluator
    }

    public func assess(_ identity: MacDeviceIdentity, now: Date) async -> MacVersionAssessment {
        MacVersionAdapter.assess(identity, feed: nil, now: now, evaluator: evaluator).assessment
    }

    public static func assessment(for identity: MacDeviceIdentity, now: Date = Clock.system.now()) -> MacVersionAssessment {
        MacVersionAdapter.assess(identity, feed: nil, now: now).assessment
    }
}
