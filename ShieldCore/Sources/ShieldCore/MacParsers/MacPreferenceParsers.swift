// Pure parsers for in-process reads on the Mac (SPEC §6.2): SoftwareUpdate preferences
// (`auto_updates`, `os_update_stuck`, `beta_catalog`), MobileMeAccounts.plist (`find_my`) and
// the XProtect bundle versions (`xprotect_current`). H7 applies: unreadable → unknown.

import Foundation

// MARK: - Preference values

/// A property-list value, reduced to what the parsers need. Built from CFPreferences or
/// PropertyListSerialization output with `PrefValue(propertyList:)`.
public indirect enum PrefValue: Sendable, Hashable {
    case bool(Bool)
    case integer(Int)
    case real(Double)
    case string(String)
    case date(Date)
    case array([PrefValue])
    case dictionary([String: PrefValue])
    /// Data or anything else the parsers never look at.
    case other

    /// Converts a property-list object. Distinguishes CFBoolean from other numbers.
    public init(propertyList value: Any) {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number as CFNumber) {
                self = .real(number.doubleValue)
            } else {
                self = .integer(number.intValue)
            }
        case let string as String:
            self = .string(string)
        case let date as Date:
            self = .date(date)
        case let array as [Any]:
            self = .array(array.map(PrefValue.init(propertyList:)))
        case let dictionary as [String: Any]:
            self = .dictionary(dictionary.mapValues(PrefValue.init(propertyList:)))
        default:
            self = .other
        }
    }

    /// A boolean flag: a real boolean, or the integers 0 / 1. Anything else is nil.
    public var flag: Bool? {
        switch self {
        case .bool(let value): value
        case .integer(0): false
        case .integer(1): true
        default: nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .integer(let value): value
        case .string(let value): Int(value.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }
}

// MARK: - SoftwareUpdate preferences

/// The `com.apple.SoftwareUpdate` values the Mac checks read, plus whether the domain could be
/// read at all (a nil read must never look like "key missing = on").
public struct SoftwareUpdatePrefs: Sendable, Hashable {
    public static let domain = "com.apple.SoftwareUpdate"
    public static let autoInstallMacOSKey = "AutomaticallyInstallMacOSUpdates"
    public static let criticalUpdateInstallKey = "CriticalUpdateInstall"
    public static let automaticCheckKey = "AutomaticCheckEnabled"
    public static let ddmErrorKey = "DDMPersistedErrorKey"
    public static let catalogURLKey = "CatalogURL"

    /// Every key the checks use. Readers copy only these out of the domain.
    public static let keys: [String] = [
        autoInstallMacOSKey, criticalUpdateInstallKey, automaticCheckKey, ddmErrorKey, catalogURLKey,
    ]

    /// False when the domain could not be read (no keys at all, sandbox, missing file).
    public var readable: Bool
    public var values: [String: PrefValue]

    public init(readable: Bool, values: [String: PrefValue]) {
        self.readable = readable
        self.values = readable ? values : [:]
    }

    public static let unreadable = SoftwareUpdatePrefs(readable: false, values: [:])

    /// From a property-list dictionary (e.g. a fixture plist or `CFPreferencesCopyMultiple`).
    /// An empty or non-dictionary value is unreadable.
    public init(propertyList: Any?) {
        guard let dictionary = propertyList as? [String: Any], !dictionary.isEmpty else {
            self = .unreadable
            return
        }
        var values: [String: PrefValue] = [:]
        for key in Self.keys {
            if let value = dictionary[key] { values[key] = PrefValue(propertyList: value) }
        }
        self.init(readable: true, values: values)
    }

    /// From plist file data. Unparseable data is unreadable.
    public init(plistData: Data?) {
        guard let plistData,
              let object = try? PropertyListSerialization.propertyList(from: plistData, format: nil) else {
            self = .unreadable
            return
        }
        self.init(propertyList: object)
    }
}

// MARK: - XProtect

/// Versions read from the installed XProtect components. Local only.
public struct XProtectInstalledVersions: Sendable, Hashable {
    /// `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist`
    /// `CFBundleShortVersionString` (the §6.2 file; e.g. "5368"). Same series as SOFA
    /// `XProtectPlistConfigData["com.apple.XProtect"]`.
    public var bundleVersion: String?
    /// `/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist`
    /// `CFBundleShortVersionString` (e.g. "170"). Same series as SOFA
    /// `XProtectPayloads["com.apple.XProtectFramework.XProtect"]`.
    public var appVersion: String?

    public static let bundleInfoPlistPath = "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
    public static let appInfoPlistPath = "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist"

    public init(bundleVersion: String?, appVersion: String?) {
        self.bundleVersion = bundleVersion
        self.appVersion = appVersion
    }
}

/// The current XProtect versions published in the macOS feed. Local only.
public struct XProtectFeedVersions: Sendable, Hashable {
    /// SOFA v2 `XProtectPlistConfigData["com.apple.XProtect"]` (e.g. "5368").
    public var plistConfigData: String?
    /// SOFA v2 `XProtectPayloads["com.apple.XProtectFramework.XProtect"]` (e.g. "170").
    public var payloads: String?

    public init(plistConfigData: String?, payloads: String?) {
        self.plistConfigData = plistConfigData
        self.payloads = payloads
    }

    public static let sofaPlistConfigKey = "com.apple.XProtect"
    public static let sofaPayloadsKey = "com.apple.XProtectFramework.XProtect"

    /// From the two SOFA v2 macOS objects (values may be strings or numbers). nil when neither
    /// carries a version.
    public init?(sofaXProtectPayloads payloads: [String: Any]?, sofaXProtectPlistConfigData config: [String: Any]?) {
        func version(_ value: Any?) -> String? {
            switch value {
            case let string as String: string.isEmpty ? nil : string
            case let number as NSNumber: number.stringValue
            default: nil
            }
        }
        let configVersion = version(config?[Self.sofaPlistConfigKey])
        let payloadVersion = version(payloads?[Self.sofaPayloadsKey])
        guard configVersion != nil || payloadVersion != nil else { return nil }
        self.init(plistConfigData: configVersion, payloads: payloadVersion)
    }
}

// MARK: - Parsers

public enum MacPreferenceParsers {

    /// `auto_updates`: `AutomaticallyInstallMacOSUpdates`, `CriticalUpdateInstall` and
    /// `AutomaticCheckEnabled`; a missing key = on [V]. Any one off → fail. Never implies patched.
    public static func autoUpdates(_ prefs: SoftwareUpdatePrefs) -> MacCheckOutcome {
        let id = CheckID.autoUpdates
        guard prefs.readable else { return .unknown(id, .dataUnavailable) }
        let keys = [
            SoftwareUpdatePrefs.autoInstallMacOSKey,
            SoftwareUpdatePrefs.criticalUpdateInstallKey,
            SoftwareUpdatePrefs.automaticCheckKey,
        ]
        var allOn = true
        for key in keys {
            guard let value = prefs.values[key] else { continue }   // missing = on
            guard let flag = value.flag else { return .unknown(id, .unparseable) }
            if !flag { allOn = false }
        }
        return allOn ? .pass(id) : .fail(id)
    }

    /// Failures at or above this count, recent enough, mean "stuck" (§6.2).
    public static let stuckFailureCount = 3
    /// "within 14 days".
    public static let stuckWindowDays = 14

    /// `os_update_stuck`: `DDMPersistedErrorKey` with count ≥ 3 and a timestamp within 14 days →
    /// fail [V]. No key → pass (no recorded failures). An unreadable domain or malformed entry → unknown.
    public static func updateStuck(_ prefs: SoftwareUpdatePrefs, now: Date) -> MacCheckOutcome {
        let id = CheckID.osUpdateStuck
        guard prefs.readable else { return .unknown(id, .dataUnavailable) }
        guard let entry = prefs.values[SoftwareUpdatePrefs.ddmErrorKey] else { return .pass(id) }
        guard case .dictionary(let error) = entry, let count = error["count"]?.intValue else {
            return .unknown(id, .unparseable)
        }
        guard count >= stuckFailureCount else { return .pass(id) }
        guard let timestamp = error["timestamp"].flatMap(date(from:)) else {
            return .unknown(id, .unparseable)
        }
        // A timestamp in the future (clock skew) counts as recent.
        let age = now.timeIntervalSince(timestamp)
        return age <= TimeInterval(stuckWindowDays) * 86_400 ? .fail(id) : .pass(id)
    }

    /// `beta_catalog` from preferences: a `CatalogURL` containing "seed" or "beta" → fail;
    /// missing → pass; an unreadable domain → unknown (the suite then tries `defaults read`).
    public static func betaCatalog(_ prefs: SoftwareUpdatePrefs) -> MacCheckOutcome {
        let id = CheckID.betaCatalog
        guard prefs.readable else { return .unknown(id, .dataUnavailable) }
        guard let value = prefs.values[SoftwareUpdatePrefs.catalogURLKey] else { return .pass(id) }
        guard case .string(let url) = value else { return .unknown(id, .unparseable) }
        return isBetaCatalog(url) ? .fail(id) : .pass(id)
    }

    /// True when a SoftwareUpdate catalog URL points at a seed (beta) catalog.
    public static func isBetaCatalog(_ url: String) -> Bool {
        let lowered = url.lowercased()
        return lowered.contains("seed") || lowered.contains("beta")
    }

    /// The `MobileMeAccounts` service name for Find My Mac.
    public static let findMyServiceName = "FIND_MY_MAC"

    /// `find_my`: `Accounts[].Services[]` where `Name == "FIND_MY_MAC"` → `Enabled` [V].
    ///
    /// Privacy (§12.2): this reads only that one flag. The decoded dictionary lives only inside
    /// this call; nothing else from the file is returned, kept or logged.
    /// - no file / unparseable → unknown
    /// - `Accounts` is an empty array (signed out of iCloud) → fail
    /// - a FIND_MY_MAC service with `Enabled` true → pass; all with `Enabled` false → fail
    /// - no FIND_MY_MAC service, or no `Enabled` key (undocumented shapes) → unknown
    public static func findMy(mobileMeAccountsPlist data: Data?) -> MacCheckOutcome {
        let id = CheckID.findMy
        guard let data else { return .unknown(id, .dataUnavailable) }
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let accounts = root["Accounts"] as? [Any] else {
            return .unknown(id, .unparseable)
        }
        if accounts.isEmpty { return .fail(id) }
        var sawDisabled = false
        var sawUnreadableFlag = false
        for case let account as [String: Any] in accounts {
            for case let service as [String: Any] in (account["Services"] as? [Any]) ?? [] {
                guard (service["Name"] as? String) == findMyServiceName else { continue }
                switch service["Enabled"].map(PrefValue.init(propertyList:))?.flag {
                case true?: return .pass(id)
                case false?: sawDisabled = true
                case nil: sawUnreadableFlag = true
                }
            }
        }
        if sawUnreadableFlag { return .unknown(id, .unparseable) }
        if sawDisabled { return .fail(id) }
        return .unknown(id, .dataUnavailable)
    }

    /// `CFBundleShortVersionString` from Info.plist data, or nil.
    public static func bundleShortVersion(infoPlist data: Data?) -> String? {
        guard let data,
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = root["CFBundleShortVersionString"] as? String else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `xprotect_current`: each installed component ≥ the feed's current version; no feed → unknown.
    ///
    /// Note: §6.2 names the XProtect.bundle version and the feed's `XProtectPayloads`. On the
    /// 2026-10-22 data those are different series (bundle 5368 = `XProtectPlistConfigData` 5368;
    /// `XProtectPayloads` 170 = XProtect.app 170), and comparing across them would always pass
    /// (a false green). So each installed version is compared with its own series. At least one
    /// comparable pair is required, and every comparable pair must be current.
    public static func xprotect(installed: XProtectInstalledVersions, feed: XProtectFeedVersions?) -> MacCheckOutcome {
        let id = CheckID.xprotectCurrent
        guard let feed, feed.plistConfigData != nil || feed.payloads != nil else { return .unknown(id, .noFeed) }
        guard installed.bundleVersion != nil || installed.appVersion != nil else {
            return .unknown(id, .dataUnavailable)
        }
        let pairs: [(String?, String?)] = [
            (installed.bundleVersion, feed.plistConfigData),
            (installed.appVersion, feed.payloads),
        ]
        var compared = 0
        for case let (local?, current?) in pairs {
            guard let order = compareVersions(local, current) else { return .unknown(id, .unparseable) }
            if order == .orderedAscending { return .fail(id) }
            compared += 1
        }
        return compared > 0 ? .pass(id) : .unknown(id, .dataUnavailable)
    }

    // MARK: Helpers

    /// Numeric dotted-version comparison ("5368" vs "5370", "26.7.1" vs "26.7"). nil if either
    /// side is not purely numeric components.
    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        func components(_ text: String) -> [Int]? {
            let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty else { return nil }
            var numbers: [Int] = []
            for part in parts {
                guard !part.isEmpty, part.allSatisfy(\.isASCII), let value = Int(part), value >= 0 else { return nil }
                numbers.append(value)
            }
            return numbers
        }
        guard let left = components(lhs), let right = components(rhs) else { return nil }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    /// A DDM timestamp: a plist date, or an ISO 8601 string ("2026-10-14T22:35:25-04:00").
    static func date(from value: PrefValue) -> Date? {
        switch value {
        case .date(let date):
            return date
        case .string(let text):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)
        default:
            return nil
        }
    }
}
