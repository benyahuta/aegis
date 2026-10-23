// The narrow seam between the Mac checks and the Version module (SPEC §5.2).
//
// `os_patched`, `device_supported` and `xprotect_current` come from VersionEvaluator + FeedStore.
// The Mac checks depend only on `MacVersionAssessing`; MacVersionAdapter.swift maps a
// `VersionEvaluation` onto it (`FeedMacVersionAssessor`, and `BundledMacVersionAssessor` for
// "feed never fetched").

import Foundation

/// What the Mac knows about itself (§5.2 inputs). Local only: never logged, never synced (§12.2).
public struct MacDeviceIdentity: Sendable, Hashable {
    public var osMajor: Int
    public var osMinor: Int
    public var osPatch: Int
    /// `sysctlbyname("hw.target")`, e.g. "J704AP" (matches SOFA `SupportedDevices`).
    public var boardID: String?
    /// `sysctlbyname("hw.model")`, e.g. "Mac17,2" (key into SOFA `Models`).
    public var modelID: String?

    public init(osMajor: Int, osMinor: Int, osPatch: Int, boardID: String?, modelID: String?) {
        self.osMajor = osMajor
        self.osMinor = osMinor
        self.osPatch = osPatch
        self.boardID = boardID
        self.modelID = modelID
    }

    public init(_ version: OperatingSystemVersion, boardID: String?, modelID: String?) {
        self.init(osMajor: version.majorVersion, osMinor: version.minorVersion, osPatch: version.patchVersion,
                  boardID: boardID, modelID: modelID)
    }

    /// "26.5.1"-style string for comparisons (local only).
    public var versionString: String { "\(osMajor).\(osMinor).\(osPatch)" }
}

/// Everything the Mac checks need from the Version module.
public struct MacVersionAssessment: Sendable, Hashable {
    /// §5.2 verdict for `os_patched` (stale/no feed and above the bundled minimum → unknown).
    public var osPatched: Status
    /// True when a fix for an actively exploited bug is out and this Mac doesn't have it (red tier).
    public var activelyExploited: Bool
    /// The exploited CVE IDs this Mac is still exposed to. Local only (H5): used for the
    /// `remote_access_off` red rule (CVE-2026-65400) and never shown or synced.
    public var unpatchedExploitedCVEs: Set<String>
    /// §5.2 step 6.
    public var deviceSupported: Status
    /// Patched, but not on the newest major (local amber note for Ben).
    public var agingDevice: Bool
    /// The feed's current XProtect versions, or nil when there is no usable feed.
    public var xprotectFeed: XProtectFeedVersions?

    public init(
        osPatched: Status,
        activelyExploited: Bool,
        unpatchedExploitedCVEs: Set<String> = [],
        deviceSupported: Status,
        agingDevice: Bool = false,
        xprotectFeed: XProtectFeedVersions? = nil
    ) {
        self.osPatched = osPatched
        // An exploited flag only means something on a failing check.
        self.activelyExploited = osPatched == .fail && activelyExploited
        self.unpatchedExploitedCVEs = unpatchedExploitedCVEs
        self.deviceSupported = deviceSupported
        self.agingDevice = agingDevice
        self.xprotectFeed = xprotectFeed
    }

    /// CVE-2026-65400: macOS Screen Sharing authentication bypass (in KEV; research/version-feed.md).
    public static let screenSharingBypassCVE = "CVE-2026-65400"

    /// True when Screen Sharing being open is a known, exploited way in (§6.2 `remote_access_off` red rule).
    public var screenSharingExploitUnpatched: Bool {
        osPatched == .fail && unpatchedExploitedCVEs.contains(Self.screenSharingBypassCVE)
    }
}

/// Adapter seam for VersionEvaluator (§5.2). Implementations must follow H7: no feed / stale /
/// errors → `.unknown`, never `.pass`.
public protocol MacVersionAssessing: Sendable {
    func assess(_ identity: MacDeviceIdentity, now: Date) async -> MacVersionAssessment
}
