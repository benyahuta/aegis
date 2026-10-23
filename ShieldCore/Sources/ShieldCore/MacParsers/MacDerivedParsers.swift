// Pure mappings for the Mac checks that are not single-tool parses (SPEC §6.2):
// `remote_access_off` (loopback probes), `os_patched` and `device_supported` (VersionEvaluator).

import Foundation

/// One loopback TCP probe result.
public enum PortProbeResult: String, Sendable, Hashable, CaseIterable {
    /// The connection was accepted: something is listening.
    case open
    /// Refused (RST): nothing is listening.
    case closed
    /// Timed out (300 ms) or failed for another reason: can't tell.
    case indeterminate
}

public enum MacDerivedParsers {
    /// §6.2: TCP to 127.0.0.1 on 22 (Remote Login), 5900 (Screen Sharing), 445 (SMB), 548 (AFP).
    public static let remoteAccessPorts: [UInt16] = [22, 5900, 445, 548]
    public static let screenSharingPort: UInt16 = 5900

    /// Any accepted → fail (yellow; red when 5900 is open and the Mac is unpatched for
    /// CVE-2026-65400). All four refused → pass. Otherwise (a timeout or missing port) → unknown.
    public static func remoteAccess(
        _ probes: [UInt16: PortProbeResult],
        screenSharingExploitUnpatched: Bool
    ) -> MacCheckOutcome {
        let id = CheckID.remoteAccessOff
        let results = remoteAccessPorts.map { probes[$0] }
        if results.contains(.open) {
            let red = probes[screenSharingPort] == .open && screenSharingExploitUnpatched
            return .fail(id, tier: red ? .red : .yellow)
        }
        if results.allSatisfy({ $0 == .closed }) { return .pass(id) }
        return .unknown(id, .unparseable)
    }

    /// `os_patched`: red when actively exploited, otherwise amber. No assessment → unknown.
    public static func osPatched(_ assessment: MacVersionAssessment?) -> MacCheckOutcome {
        let id = CheckID.osPatched
        guard let assessment else { return .unknown(id, .noFeed) }
        switch assessment.osPatched {
        case .pass: return .pass(id)
        case .fail: return .fail(id, tier: assessment.activelyExploited ? .red : .amber)
        case .unknown: return .unknown(id, .noFeed)
        }
    }

    /// `device_supported`: §5.2 step 6. An aging (but patched) Mac passes with an `agingDevice` note.
    public static func deviceSupported(_ assessment: MacVersionAssessment?) -> MacCheckOutcome {
        let id = CheckID.deviceSupported
        guard let assessment else { return .unknown(id, .noFeed) }
        switch assessment.deviceSupported {
        case .pass:
            return assessment.agingDevice
                ? MacCheckOutcome(checkID: id, status: .pass, note: .agingDevice)
                : .pass(id)
        case .fail: return .fail(id)
        case .unknown: return .unknown(id, .noFeed)
        }
    }
}
