// SOFA v2 feed models (SPEC §5.2 FeedStore, research/version-feed.md §1).
//
// Defensive decoding rules:
//   - Unknown keys are ignored (we only read the handful of keys below).
//   - `CVEs` may be an Int (count), an object map {CVE-ID: {ActivelyExploited, ...}} or an array of IDs.
//   - `Build` may be null or "".
//   - Anything structurally wrong (truncated JSON, OSVersions missing, a version that does not
//     parse, a field with the wrong type) makes the whole decode fail: `SOFAFeed.decode` returns nil
//     and the fetch is ignored.
//
// H6: the feed only ever supplies numbers, model/board IDs and booleans to the app. URLs and text in
// the feed (SecurityInfo, UpdateSummary, MarketingName, InstallationApps) are deliberately not decoded,
// so they can never be shown to the family.

import Foundation

// MARK: - Feed

public struct SOFAFeed: Sendable, Hashable {
    /// `LastCheck`: when SOFA last checked Apple. Freshness ages from the older of this and our fetch
    /// time (`FeedState.dataDate`), so a stalled upstream pipeline degrades to unknown (H7).
    public var lastCheck: Date?
    /// `UpdateHash`. Informational.
    public var updateHash: String?
    /// `OSVersions`, in feed order (newest major first in practice; never relied on).
    public var osVersions: [SOFAOSVersion]
    /// `Devices`: iOS model identifier → {}; macOS board ID → {DeviceID: model identifier}.
    public var devices: [String: SOFADevice]
    /// `Models` (macOS only): model identifier (`hw.model`) → supported majors.
    public var models: [String: SOFAModel]
    /// `XProtectPayloads` / `XProtectPlistConfigData` (macOS only).
    public var xProtect: SOFAXProtect?

    public init(
        lastCheck: Date? = nil,
        updateHash: String? = nil,
        osVersions: [SOFAOSVersion],
        devices: [String: SOFADevice] = [:],
        models: [String: SOFAModel] = [:],
        xProtect: SOFAXProtect? = nil
    ) {
        self.lastCheck = lastCheck
        self.updateHash = updateHash
        self.osVersions = osVersions
        self.devices = devices
        self.models = models
        self.xProtect = xProtect
    }

    /// Decodes a SOFA v2 feed (or a bundled snapshot in the same shape). Returns nil on any
    /// failure, including truncated JSON and a feed with no usable OS versions.
    public static func decode(_ data: Data) -> SOFAFeed? {
        do {
            let feed = try JSONDecoder().decode(SOFAFeed.self, from: data)
            guard feed.isUsable else { return nil }
            return feed
        } catch {
            return nil
        }
    }

    /// At least one major with at least one parsable release.
    public var isUsable: Bool {
        osVersions.contains { !$0.allReleases.isEmpty }
    }

    /// Every major in the feed, highest first, without duplicates.
    public var majors: [Int] {
        Array(Set(osVersions.map(\.major))).sorted(by: >)
    }

    /// The entry for `major`. If the feed lists a major twice, the first one wins.
    public func osVersion(major: Int) -> SOFAOSVersion? {
        osVersions.first { $0.major == major }
    }
}

// MARK: - OS line

public struct SOFAOSVersion: Sendable, Hashable {
    /// The trailing integer of `OSVersion` ("Tahoe 26" → 26, "18" → 18).
    public var major: Int
    /// `Latest`: the latest *universal* release, which is not always the right target (§5.2).
    public var latest: SOFARelease?
    /// `SecurityReleases[]`.
    public var securityReleases: [SOFARelease]

    public init(major: Int, latest: SOFARelease? = nil, securityReleases: [SOFARelease]) {
        self.major = major
        self.latest = latest
        self.securityReleases = securityReleases
    }

    /// `SecurityReleases` plus `Latest` when it is not already listed.
    public var allReleases: [SOFARelease] {
        var releases = securityReleases
        if let latest, !releases.contains(where: { $0.productVersion == latest.productVersion && $0.supportedDevices == latest.supportedDevices }) {
            releases.append(latest)
        }
        return releases
    }

    /// The releases that set `feedTarget` (§5.2 step 2): `SecurityReleases`, or `allReleases`
    /// when the line lists none. The same rule as `highestSecurityVersion`, so a minimum the
    /// evaluator remembers can never be above the baseline the raise-only check holds the next
    /// feed to (`Latest` comes from Apple's catalog and often runs ahead of the security page).
    public var targetReleases: [SOFARelease] {
        securityReleases.isEmpty ? allReleases : securityReleases
    }

    /// The highest version listed for this major, for any device (used by the raise-only check).
    public var highestVersion: OSVersion? {
        allReleases.map(\.productVersion).max()
    }

    /// The highest `SecurityReleases` version, or `highestVersion` when the line lists none (the
    /// raise-only baseline, §5.2 step 2/3).
    public var highestSecurityVersion: OSVersion? {
        securityReleases.map(\.productVersion).max() ?? highestVersion
    }

    /// Every identifier any release of this major names ("the major's device list", §5.2 step 2).
    public var deviceList: Set<String> {
        var devices = Set<String>()
        for release in allReleases { devices.formUnion(release.supportedDevices) }
        return devices
    }
}

// MARK: - Release

public struct SOFARelease: Sendable, Hashable {
    public enum DeviceScope: Sendable, Hashable {
        case universal
        case deviceSpecific
        case unspecified
        case other(String)

        init(_ raw: String?) {
            switch raw?.lowercased() {
            case nil, "": self = .unspecified
            case "universal": self = .universal
            case "device-specific": self = .deviceSpecific
            case let value?: self = .other(value)
            }
        }
    }

    /// `ProductVersion`.
    public var productVersion: OSVersion
    /// `Build`; nil when null, missing or "".
    public var build: String?
    /// `ReleaseDate`; nil when missing or unparsable (informational).
    public var releaseDate: Date?
    /// `DeviceScope`.
    public var deviceScope: DeviceScope
    /// `SupportedDevices` (iOS model identifiers, or macOS board IDs). Empty when missing or null.
    public var supportedDevices: [String]
    /// `ActivelyExploitedCVEs` plus any `CVEs` map entry with `ActivelyExploited == true`.
    public var activelyExploitedCVEs: [String]
    /// `CVEs`, whatever shape it came in.
    public var cves: SOFACVEs

    public init(
        productVersion: OSVersion,
        build: String? = nil,
        releaseDate: Date? = nil,
        deviceScope: DeviceScope = .universal,
        supportedDevices: [String] = [],
        activelyExploitedCVEs: [String] = [],
        cves: SOFACVEs = .none
    ) {
        self.productVersion = productVersion
        self.build = build
        self.releaseDate = releaseDate
        self.deviceScope = deviceScope
        self.supportedDevices = supportedDevices
        self.activelyExploitedCVEs = activelyExploitedCVEs
        self.cves = cves
    }

    /// True when this release fixes at least one actively exploited CVE (§5.2 step 4).
    /// Uses `ActivelyExploitedCVEs` / `CVEs[x].ActivelyExploited`, never `UpdateSummary.Stats`.
    public var fixesActivelyExploited: Bool {
        !activelyExploitedCVEs.isEmpty
    }
}

/// The `CVEs` field, which SOFA ships in three shapes (v2 Latest: Int; v2 SecurityReleases: map; v1: array).
public enum SOFACVEs: Sendable, Hashable {
    case none
    case count(Int)
    case ids([String])
    case map([String: SOFACVEInfo])

    /// How many CVEs the release lists.
    public var count: Int {
        switch self {
        case .none: 0
        case .count(let value): max(0, value)
        case .ids(let ids): ids.count
        case .map(let map): map.count
        }
    }

    /// IDs flagged as actively exploited inside a map (empty for the other shapes).
    public var exploitedIDs: [String] {
        guard case .map(let map) = self else { return [] }
        return map.filter { $0.value.activelyExploited }.map(\.key).sorted()
    }
}

public struct SOFACVEInfo: Sendable, Hashable {
    public var activelyExploited: Bool
    public var inKEV: Bool

    public init(activelyExploited: Bool = false, inKEV: Bool = false) {
        self.activelyExploited = activelyExploited
        self.inKEV = inKEV
    }
}

// MARK: - Devices, models, XProtect

public struct SOFADevice: Sendable, Hashable {
    /// macOS only: the model identifier for a board ID (e.g. J704AP → "Mac17,2").
    public var deviceID: String?

    public init(deviceID: String? = nil) {
        self.deviceID = deviceID
    }
}

public struct SOFAModel: Sendable, Hashable {
    /// The majors this Mac model can run, e.g. [27, 26].
    public var osVersions: [Int]

    public init(osVersions: [Int]) {
        self.osVersions = osVersions
    }
}

public struct SOFAXProtect: Sendable, Hashable {
    /// `XProtectPayloads["com.apple.XProtectFramework.XProtect"]`, e.g. "170".
    public var xprotectVersion: String?
    /// `XProtectPayloads["com.apple.XprotectFramework.PluginService"]`, e.g. "74".
    public var pluginServiceVersion: String?
    /// `XProtectPlistConfigData["com.apple.XProtect"]`, e.g. "5368".
    public var plistConfigVersion: String?

    public init(xprotectVersion: String? = nil, pluginServiceVersion: String? = nil, plistConfigVersion: String? = nil) {
        self.xprotectVersion = xprotectVersion
        self.pluginServiceVersion = pluginServiceVersion
        self.plistConfigVersion = plistConfigVersion
    }
}

// MARK: - Decoding

struct SOFAKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { self.stringValue = string; self.intValue = nil }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

extension KeyedDecodingContainer where Key == SOFAKey {
    /// Present and not null.
    fileprivate func has(_ key: String) throws -> Bool {
        let codingKey = SOFAKey(key)
        guard contains(codingKey) else { return false }
        return try !decodeNil(forKey: codingKey)
    }

    /// nil when missing or null; throws when present with the wrong type.
    fileprivate func optional<T: Decodable>(_ type: T.Type, _ key: String) throws -> T? {
        guard try has(key) else { return nil }
        return try decode(T.self, forKey: SOFAKey(key))
    }

    /// A string or a number, as a string. nil when missing or null.
    fileprivate func stringOrNumber(_ key: String) throws -> String? {
        guard try has(key) else { return nil }
        let codingKey = SOFAKey(key)
        if let string = try? decode(String.self, forKey: codingKey) { return string }
        if let int = try? decode(Int.self, forKey: codingKey) { return String(int) }
        let double = try decode(Double.self, forKey: codingKey)
        return String(double)
    }
}

enum SOFADate {
    /// Parses "2026-09-28T00:00:00Z" and "2026-10-22T20:18:20.379737709+00:00".
    static func parse(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        // Drop a fractional-seconds part of any length, then retry.
        if let dot = string.firstIndex(of: "."), dot > string.startIndex {
            var end = string.index(after: dot)
            while end < string.endIndex, string[end].isASCII, string[end].isNumber { end = string.index(after: end) }
            let stripped = String(string[..<dot]) + String(string[end...])
            if let date = plain.date(from: stripped) { return date }
        }
        return nil
    }
}

extension SOFAFeed: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SOFAKey.self)
        self.lastCheck = try container.optional(String.self, "LastCheck").flatMap(SOFADate.parse)
        self.updateHash = try? container.optional(String.self, "UpdateHash")
        // Required.
        self.osVersions = try container.decode([SOFAOSVersion].self, forKey: SOFAKey("OSVersions"))
        self.devices = try container.optional([String: SOFADevice].self, "Devices") ?? [:]
        self.models = try container.optional([String: SOFAModel].self, "Models") ?? [:]

        var xProtect = SOFAXProtect()
        var hasXProtect = false
        if try container.has("XProtectPayloads") {
            let payloads = try container.nestedContainer(keyedBy: SOFAKey.self, forKey: SOFAKey("XProtectPayloads"))
            xProtect.xprotectVersion = try payloads.stringOrNumber("com.apple.XProtectFramework.XProtect")
            xProtect.pluginServiceVersion = try payloads.stringOrNumber("com.apple.XprotectFramework.PluginService")
            hasXProtect = true
        }
        if try container.has("XProtectPlistConfigData") {
            let config = try container.nestedContainer(keyedBy: SOFAKey.self, forKey: SOFAKey("XProtectPlistConfigData"))
            xProtect.plistConfigVersion = try config.stringOrNumber("com.apple.XProtect")
            hasXProtect = true
        }
        self.xProtect = hasXProtect ? xProtect : nil
    }
}

extension SOFAOSVersion: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SOFAKey.self)
        let key = SOFAKey("OSVersion")
        let major: Int
        if let number = try? container.decode(Int.self, forKey: key) {
            major = number
        } else {
            let name = try container.decode(String.self, forKey: key)
            guard let parsed = SOFAOSVersion.trailingInteger(name) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "No major in OSVersion")
            }
            major = parsed
        }
        guard major > 0, major < 1000 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Implausible major")
        }
        self.major = major
        self.latest = try container.optional(SOFARelease.self, "Latest")
        self.securityReleases = try container.optional([SOFARelease].self, "SecurityReleases") ?? []
        // Every release must belong to this major; anything else is a corrupt feed.
        for release in allReleases where release.productVersion.major != major {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Release outside its major")
        }
    }

    /// "Tahoe 26" → 26, "18" → 18, "Golden Gate 27" → 27. nil if there is no trailing integer.
    static func trailingInteger(_ string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.reversed().prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        return Int(String(digits.reversed()))
    }
}

extension SOFARelease: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SOFAKey.self)
        let versionKey = SOFAKey("ProductVersion")
        let versionString = try container.decode(String.self, forKey: versionKey)
        guard let version = OSVersion(versionString) else {
            throw DecodingError.dataCorruptedError(forKey: versionKey, in: container, debugDescription: "Bad ProductVersion")
        }
        self.productVersion = version

        let build = try container.optional(String.self, "Build")
        self.build = (build?.isEmpty ?? true) ? nil : build
        self.releaseDate = try container.optional(String.self, "ReleaseDate").flatMap(SOFADate.parse)
        self.deviceScope = DeviceScope(try container.optional(String.self, "DeviceScope"))
        self.supportedDevices = try container.optional([String].self, "SupportedDevices") ?? []

        let cves = try SOFARelease.decodeCVEs(container)
        self.cves = cves
        var exploited = try container.optional([String].self, "ActivelyExploitedCVEs") ?? []
        for id in cves.exploitedIDs where !exploited.contains(id) { exploited.append(id) }
        self.activelyExploitedCVEs = exploited
    }

    private static func decodeCVEs(_ container: KeyedDecodingContainer<SOFAKey>) throws -> SOFACVEs {
        let key = SOFAKey("CVEs")
        guard try container.has("CVEs") else { return .none }
        if let count = try? container.decode(Int.self, forKey: key) { return .count(count) }
        if let ids = try? container.decode([String].self, forKey: key) { return .ids(ids) }
        if let map = try? container.decode([String: SOFACVEInfo].self, forKey: key) { return .map(map) }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "CVEs is not an int, array or map")
    }
}

extension SOFACVEInfo: Decodable {
    public init(from decoder: any Decoder) throws {
        // Lenient: a CVE entry with odd contents still counts as a CVE, just not as exploited.
        guard let container = try? decoder.container(keyedBy: SOFAKey.self) else {
            self.init()
            return
        }
        let exploited = (try? container.decode(Bool.self, forKey: SOFAKey("ActivelyExploited"))) ?? false
        let kev = (try? container.decode(Bool.self, forKey: SOFAKey("InKEV"))) ?? false
        self.init(activelyExploited: exploited, inKEV: kev)
    }
}

extension SOFADevice: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SOFAKey.self)
        self.init(deviceID: try container.optional(String.self, "DeviceID"))
    }
}

extension SOFAModel: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SOFAKey.self)
        guard try container.has("OSVersions") else {
            self.init(osVersions: [])
            return
        }
        var list = try container.nestedUnkeyedContainer(forKey: SOFAKey("OSVersions"))
        var majors: [Int] = []
        while !list.isAtEnd {
            if let value = try? list.decode(Int.self) {
                majors.append(value)
            } else {
                let string = try list.decode(String.self)
                guard let value = SOFAOSVersion.trailingInteger(string) else {
                    throw DecodingError.dataCorruptedError(in: list, debugDescription: "Bad model OSVersions entry")
                }
                majors.append(value)
            }
        }
        self.init(osVersions: majors)
    }
}
