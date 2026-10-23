// CheckCatalog: the compiled check catalog (SPEC §5.1, §6). Loaded from the bundled
// `catalog.json`; nothing is ever downloaded (H6). Copy lives in `Strings/Localizable.xcstrings`
// and is referenced here only by key.
//
// JSON shape (one entry per CheckID, in display order):
//   { "id", "priority", "tier", "urgentTier"?, "audience", "platforms": ["ios","mac"],
//     "sameAs"?, "byPlatform": { "<platform>": { "kind", "titleKey", "whyKey", "passKey",
//     "failKey", "failUrgentKey"?, "unknownKey"?, "noteKeys", "stepsByOSMajor" { "18": [...] },
//     "deepLink", "supportURL", "paceGroup", "callBen", "answerStyle" } } }
//
// Per-platform blocks exist because the same wire ID can be measured on one platform and
// self-reported on the other (`auto_updates`, `find_my`), with different copy and steps.

import Foundation

/// Spec priority (§15).
public enum Priority: String, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"

    private var rank: Int {
        switch self {
        case .p0: 0
        case .p1: 1
        case .p2: 2
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rank < rhs.rank }
}

/// How a check gets its status on one platform.
public enum CheckKind: String, CaseIterable, Codable, Sendable, Hashable {
    /// Measured by the app (§6.1, §6.2). Source `.measured`.
    case measured
    /// Guided self-check answered by the person (§6.3). Source `.selfReported`.
    case selfCheck
    /// §6.4 online-account category rollup, computed from service steps. Source `.selfReported`.
    case accountRollup
    /// "Check yourself" link only (§6.2 `lockdown`, `adp`; §6.3 `advanced_data_protection`).
    /// Never fails, never counts, never synced.
    case optional
}

/// Who sees the item.
public enum Audience: String, CaseIterable, Codable, Sendable, Hashable {
    /// The family member sees it on Home.
    case family
    /// Ben's dashboard only (§6.1 `app_build_fresh`, §6.2 `beta_catalog`, `persistence_new_item`,
    /// `chrome_ext_forced`). Never shown to the relative.
    case ben
}

/// Which answer buttons a self-check shows (§6.3).
public enum AnswerStyle: String, CaseIterable, Codable, Sendable, Hashable {
    /// [I did it] / [Not sure] / [Not now].
    case standard
    /// `family_code_word`: [We have one] / [Not yet].
    case codeWord
}

/// One check on one platform.
public struct CheckVariant: Sendable, Hashable {
    public let kind: CheckKind
    public let titleKey: String
    public let whyKey: String
    public let passKey: String
    public let failKey: String
    /// Fail copy when the context escalates to `urgentTier` (e.g. an actively exploited bug).
    public let failUrgentKey: String?
    /// Copy for a measured `unknown` (e.g. "Can't confirm. Check Software Update.").
    public let unknownKey: String?
    public let noteKeys: [String]
    /// Step string keys per OS major ("18", "26", "27" on iOS; "14", "15", "26", "27" on the Mac).
    public let stepsByOSMajor: [Int: [String]]
    public let deepLink: DeepLink?
    /// Apple or other official page (https only). Opened in Safari.
    public let supportURL: URL?
    /// §5.4 pace group (1, 2, 3) or nil when not paced (measured checks).
    public let paceGroup: Int?
    /// H9: the main action is **Call Ben**.
    public let callBen: Bool
    public let answerStyle: AnswerStyle

    public var source: Source {
        kind == .measured ? .measured : .selfReported
    }

    /// The steps for `major`: the exact major, else the highest listed major below it, else the
    /// lowest listed major (an older OS than any listed gets the oldest wording).
    public func steps(forOSMajor major: Int) -> [String] {
        let majors = stepsByOSMajor.keys.sorted()
        guard !majors.isEmpty else { return [] }
        if let exact = stepsByOSMajor[major] { return exact }
        if let below = majors.last(where: { $0 < major }) { return stepsByOSMajor[below] ?? [] }
        return stepsByOSMajor[majors[0]] ?? []
    }

    /// The answer buttons, in display order, with their label keys.
    public var answerOptions: [(answer: SelfAnswer, labelKey: String)] {
        switch answerStyle {
        case .standard:
            [(.didIt, "answer.didIt"), (.notSure, "answer.notSure"), (.notNow, "answer.notNow")]
        case .codeWord:
            [(.didIt, "answer.codeWord.haveOne"), (.notNow, "answer.codeWord.notYet")]
        }
    }

    /// Every string key this variant references (for lint tests).
    public var allStringKeys: [String] {
        var keys = [titleKey, whyKey, passKey, failKey] + noteKeys
        if let failUrgentKey { keys.append(failUrgentKey) }
        if let unknownKey { keys.append(unknownKey) }
        for major in stepsByOSMajor.keys.sorted() { keys += stepsByOSMajor[major] ?? [] }
        keys += answerOptions.map(\.labelKey)
        return keys
    }
}

/// One catalog entry (one `CheckID`).
public struct CatalogEntry: Sendable, Hashable, Identifiable {
    public let id: CheckID
    public let priority: Priority
    /// Tier on fail (§6 "Tier on fail").
    public let tier: Tier
    /// Tier when the context escalates (only `os_patched` and `remote_access_off`).
    public let urgentTier: Tier?
    public let audience: Audience
    /// Platforms in catalog order.
    public let platforms: [Platform]
    public let variants: [Platform: CheckVariant]
    /// When both are visible, this entry is hidden in favour of `sameAs` (§6.2 `adp` and
    /// §6.3 `advanced_data_protection` are the same Apple feature).
    public let sameAs: CheckID?
    /// Position in catalog.json (display order tiebreaker).
    public let order: Int

    public func variant(for platform: Platform) -> CheckVariant? { variants[platform] }

    /// The tier for a failing result, given whether the context escalates it.
    public func effectiveTier(urgent: Bool) -> Tier {
        urgent ? (urgentTier ?? tier) : tier
    }
}

public enum CatalogError: Error, Sendable, Equatable {
    case missingResource
    case invalidJSON(String)
}

/// The compiled check catalog.
public struct CheckCatalog: Sendable {
    /// Written into `CheckResult.catalogVersion` and `DeviceInfo.catalogVersion`.
    public let version: Int
    /// Entries in catalog order.
    public let entries: [CatalogEntry]
    /// IDs in the JSON that are not `CheckID` cases (dropped; lint must keep this empty).
    public let unknownIDs: [String]
    /// IDs that appeared more than once (later copies dropped; lint must keep this empty).
    public let duplicateIDs: [String]

    private let index: [CheckID: Int]

    public init(version: Int, entries: [CatalogEntry], unknownIDs: [String] = [], duplicateIDs: [String] = []) {
        self.version = version
        self.entries = entries
        self.unknownIDs = unknownIDs
        self.duplicateIDs = duplicateIDs
        var index: [CheckID: Int] = [:]
        for (offset, entry) in entries.enumerated() where index[entry.id] == nil {
            index[entry.id] = offset
        }
        self.index = index
    }

    public subscript(id: CheckID) -> CatalogEntry? {
        index[id].map { entries[$0] }
    }

    public func variant(_ id: CheckID, platform: Platform) -> CheckVariant? {
        self[id]?.variant(for: platform)
    }

    /// Entries that exist on `platform`, in catalog order.
    public func entries(for platform: Platform) -> [CatalogEntry] {
        entries.filter { $0.variants[platform] != nil }
    }

    // MARK: Loading

    /// The resource name of the bundled catalog.
    public static let resourceName = "catalog"

    /// Loads the bundled `catalog.json`.
    public static func bundled() throws(CatalogError) -> CheckCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw .missingResource
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .missingResource
        }
        return try load(from: data)
    }

    /// The bundled catalog, or an empty one if it cannot be read (never crashes; every check
    /// then shows as "Can't check", which is grey, never green: H7).
    public static func bundledOrEmpty() -> CheckCatalog {
        do {
            return try bundled()
        } catch {
            Log.catalog.fault("catalog.load_failed")
            return CheckCatalog(version: 0, entries: [])
        }
    }

    /// The bundled catalog, loaded once.
    public static let shared: CheckCatalog = bundledOrEmpty()

    /// Decodes catalog JSON. Unknown or duplicate IDs are dropped and reported in
    /// `unknownIDs` / `duplicateIDs`; any structural error throws.
    public static func load(from data: Data) throws(CatalogError) -> CheckCatalog {
        let raw: RawCatalog
        do {
            raw = try JSONDecoder().decode(RawCatalog.self, from: data)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        var entries: [CatalogEntry] = []
        var unknown: [String] = []
        var duplicates: [String] = []
        var seen: Set<CheckID> = []
        for (order, rawEntry) in raw.checks.enumerated() {
            guard let id = CheckID.allowlisted(rawEntry.id) else {
                unknown.append(rawEntry.id)
                continue
            }
            guard seen.insert(id).inserted else {
                duplicates.append(rawEntry.id)
                continue
            }
            entries.append(try rawEntry.entry(id: id, order: order))
        }
        if !unknown.isEmpty {
            Log.catalog.error("catalog.unknown_ids count=\(unknown.count, privacy: .private)")
        }
        return CheckCatalog(version: raw.catalogVersion, entries: entries, unknownIDs: unknown, duplicateIDs: duplicates)
    }
}

// MARK: - Raw JSON

private struct RawCatalog: Decodable {
    let catalogVersion: Int
    let checks: [RawEntry]
}

private struct RawEntry: Decodable {
    let id: String
    let priority: Priority
    let tier: Tier
    let urgentTier: Tier?
    let audience: Audience?
    let platforms: [String]
    let byPlatform: [String: RawVariant]
    let sameAs: String?

    func entry(id: CheckID, order: Int) throws(CatalogError) -> CatalogEntry {
        var platforms: [Platform] = []
        for name in self.platforms {
            guard let platform = Platform(catalogName: name) else {
                throw .invalidJSON("\(self.id): unknown platform \(name)")
            }
            platforms.append(platform)
        }
        var variants: [Platform: CheckVariant] = [:]
        for (name, rawVariant) in byPlatform {
            guard let platform = Platform(catalogName: name) else {
                throw .invalidJSON("\(self.id): unknown platform \(name)")
            }
            variants[platform] = try rawVariant.variant(id: self.id)
        }
        guard Set(platforms) == Set(variants.keys), platforms.count == variants.count else {
            throw .invalidJSON("\(self.id): platforms and byPlatform differ")
        }
        var sameAsID: CheckID?
        if let sameAs {
            guard let target = CheckID.allowlisted(sameAs) else {
                throw .invalidJSON("\(self.id): unknown sameAs \(sameAs)")
            }
            sameAsID = target
        }
        return CatalogEntry(
            id: id, priority: priority, tier: tier, urgentTier: urgentTier,
            audience: audience ?? .family, platforms: platforms, variants: variants,
            sameAs: sameAsID, order: order
        )
    }
}

private struct RawVariant: Decodable {
    let kind: CheckKind
    let titleKey: String
    let whyKey: String
    let passKey: String
    let failKey: String
    let failUrgentKey: String?
    let unknownKey: String?
    let noteKeys: [String]?
    let stepsByOSMajor: [String: [String]]
    let deepLink: String?
    let supportURL: String?
    let paceGroup: Int?
    let callBen: Bool?
    let answerStyle: AnswerStyle?

    func variant(id: String) throws(CatalogError) -> CheckVariant {
        var steps: [Int: [String]] = [:]
        for (major, keys) in stepsByOSMajor {
            guard let value = Int(major), value > 0 else {
                throw .invalidJSON("\(id): bad OS major \(major)")
            }
            steps[value] = keys
        }
        var link: DeepLink?
        if let deepLink {
            guard let parsed = DeepLink(rawValue: deepLink) else {
                throw .invalidJSON("\(id): unknown deepLink \(deepLink)")
            }
            link = parsed
        }
        var support: URL?
        if let supportURL {
            // catalog.json is one of the three places URL constants may live (§12.4).
            guard let url = OfficialLinks.httpsURL(supportURL) else {
                throw .invalidJSON("\(id): supportURL must be https")
            }
            support = url
        }
        if let paceGroup, !(1...3).contains(paceGroup) {
            throw .invalidJSON("\(id): paceGroup must be 1...3")
        }
        return CheckVariant(
            kind: kind, titleKey: titleKey, whyKey: whyKey, passKey: passKey, failKey: failKey,
            failUrgentKey: failUrgentKey, unknownKey: unknownKey, noteKeys: noteKeys ?? [],
            stepsByOSMajor: steps, deepLink: link, supportURL: support, paceGroup: paceGroup,
            callBen: callBen ?? false, answerStyle: answerStyle ?? .standard
        )
    }
}

extension Platform {
    /// The catalog.json name ("ios" / "mac").
    public var catalogName: String {
        switch self {
        case .ios: "ios"
        case .mac: "mac"
        }
    }

    public init?(catalogName: String) {
        switch catalogName {
        case "ios": self = .ios
        case "mac": self = .mac
        default: return nil
        }
    }

    /// The running OS major version (e.g. 26).
    public static var currentOSMajor: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }
}
