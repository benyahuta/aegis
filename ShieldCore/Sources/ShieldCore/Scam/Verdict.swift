// SHARED CONTRACT (scaffold). Every builder depends on this file.
// The scam checker's answer (SPEC §1, §5.3, §10.1 screen 10). There is NEVER a "safe" verdict.
// Verdicts never leave the device and are never stored (§5.3 "Storage: none", §12.2).

import Foundation

public enum Verdict: String, CaseIterable, Sendable, Hashable, Comparable {
    /// Red octagon: "This looks like a scam."
    case danger
    /// Amber triangle: "Be careful."
    case beCareful
    /// Grey circle (never green): "We didn't find common warning signs. Still follow the rules below."
    case noCommonSignsFound

    /// Higher is more severe. Used for `final = max(rules, llm)` (§5.3).
    public var severity: Int {
        switch self {
        case .noCommonSignsFound: 0
        case .beCareful: 1
        case .danger: 2
        }
    }

    public static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.severity < rhs.severity }
}
