// SHARED CONTRACT (scaffold). Every builder depends on this file.
// `Tier` is computed on the device from CheckID plus context and is NEVER synced (SPEC §5.1).

import Foundation

/// How urgent a failing check is. The raw value is the catalog.json `tier` string.
///
/// Red means ONLY: an actively exploited bug whose fix is out, MDM you don't expect,
/// no passcode, or Gatekeeper/SIP off (§5.1). Firewall is never red (§6.2).
public enum Tier: String, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case red
    case amber
    case yellow
    case info

    /// Higher is more urgent: red 3, amber 2, yellow 1, info 0.
    public var urgency: Int {
        switch self {
        case .red: 3
        case .amber: 2
        case .yellow: 1
        case .info: 0
        }
    }

    /// Ordered by urgency, so `max()` gives the most urgent tier.
    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.urgency < rhs.urgency }
}
