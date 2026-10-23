// The local result of one Mac check (SPEC §6.2). Only `checkID` + `status` ever leave the device,
// through `checkResult(...)` (§8.2, H5). `note` and `tierOverride` are local context for the
// StatusEngine and the UI and are never synced.

import Foundation

/// Why a check ended up with its status. Local only; safe to log as `.public` (enum raw value).
public enum MacCheckNote: String, CaseIterable, Sendable, Hashable {
    /// The tool or data was read and parsed cleanly; the status is the real answer.
    case measured = "measured"
    /// Non-zero / unexpected exit, launch failure, refused invocation or killed by a signal.
    case toolFailed = "tool_failed"
    /// The tool hit the 10 s limit.
    case timedOut = "timed_out"
    /// Output or data was present but did not match any known shape.
    case unparseable = "unparseable"
    /// A file or preference domain could not be read, or a key the answer depends on is missing.
    case dataUnavailable = "data_unavailable"
    /// The answer needs the version feed (or the VersionEvaluator) and none is available.
    case noFeed = "no_feed"
    /// `mdm_unexpected`: MDM is present but Ben marked it expected on his own Mac.
    case expectedByOwner = "expected_by_owner"
    /// `device_supported`: still patched, but not on the newest major (amber note, Ben only, §5.2 step 6).
    case agingDevice = "aging_device"
    /// Injected by `-FSDemoState` (§13.2). Never produced by a real check.
    case demo = "demo"
}

public struct MacCheckOutcome: Sendable, Hashable {
    public var checkID: CheckID
    public var status: Status
    public var note: MacCheckNote
    /// Set only when the §6.2 tier depends on context: `os_patched` (red if actively exploited,
    /// otherwise amber) and `remote_access_off` (red if Screen Sharing is open on a Mac that is
    /// unpatched for CVE-2026-65400, otherwise yellow). nil means "use the catalog tier".
    public var tierOverride: Tier?

    public init(checkID: CheckID, status: Status, note: MacCheckNote, tierOverride: Tier? = nil) {
        self.checkID = checkID
        self.status = status
        self.note = note
        self.tierOverride = tierOverride
    }

    static func pass(_ id: CheckID) -> MacCheckOutcome {
        MacCheckOutcome(checkID: id, status: .pass, note: .measured)
    }

    static func fail(_ id: CheckID, tier: Tier? = nil) -> MacCheckOutcome {
        MacCheckOutcome(checkID: id, status: .fail, note: .measured, tierOverride: tier)
    }

    /// H7: every "can't tell" path goes through here, so it can never be `.pass`.
    static func unknown(_ id: CheckID, _ note: MacCheckNote) -> MacCheckOutcome {
        MacCheckOutcome(checkID: id, status: .unknown, note: note)
    }

    /// The synced form: exactly the §8.2 fields. Mac checks are always `.measured`.
    public func checkResult(deviceID: UUID, checkedOn: DateDay, catalogVersion: Int) -> CheckResult {
        CheckResult(
            deviceID: deviceID,
            checkID: checkID,
            status: status,
            source: .measured,
            checkedOn: checkedOn,
            catalogVersion: catalogVersion
        )
    }
}
