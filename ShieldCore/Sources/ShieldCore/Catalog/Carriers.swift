// Phone companies for the `carrier_lock` self-check (SPEC §6.3). The person's pick is stored
// locally only and never synced (§12.2 "carrier"). Paths were checked against each carrier's
// help pages on 2026-10-22 (docs/verified/accounts-money-gov.md) and re-audited on 2026-10-23
// (docs/verified/AUDITED.md: Verizon, T-Mobile, AT&T, UScellular wording); the card always says
// "Menu names may differ a little."

import Foundation

public enum Carrier: String, CaseIterable, Codable, Sendable, Hashable {
    case verizon
    case att
    case tmobile
    case visible
    case mint
    case cricket
    /// Now part of T-Mobile; migrated accounts use the T-Mobile steps.
    case uscellular
    /// "Ask Ben."
    case other

    public var nameKey: String { "carrier.\(rawValue).name" }

    /// Step string keys, in order.
    public var stepKeys: [String] {
        (1...stepCount).map { "carrier.\(rawValue).step.\($0)" }
    }

    private var stepCount: Int {
        switch self {
        case .verizon, .att, .tmobile, .visible, .uscellular: 2
        case .mint, .cricket, .other: 1
        }
    }
}
