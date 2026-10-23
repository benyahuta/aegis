// In-process reads for the Mac checks (SPEC §6.2). Read-only; no admin, no Full Disk Access,
// no prompts. Every failure returns an "unreadable" value so the check becomes unknown (H7).
//
// - SoftwareUpdate prefs: CFPreferences (`CFPreferencesCopyAppValue` also sees MDM-managed
//   values). Only the keys in `SoftwareUpdatePrefs.keys` are copied out.
// - MobileMeAccounts.plist: raw bytes handed straight to the `find_my` parser, which keeps only
//   the FIND_MY_MAC `Enabled` flag (§12.2).
// - XProtect: the two Info.plist versions.
// - Identity: `operatingSystemVersion`, `sysctlbyname("hw.target")`, `sysctlbyname("hw.model")`.

import Foundation
import Darwin
import ShieldCore

struct MacSystemReader: MacSystemReading {
    /// Files larger than this are not plausible preference files; don't read them.
    static let maxPlistBytes = 4 * 1024 * 1024

    func softwareUpdatePrefs() -> SoftwareUpdatePrefs {
        let domain = SoftwareUpdatePrefs.domain as CFString
        // /Library/Preferences/com.apple.SoftwareUpdate.plist is the any-user / any-host domain.
        // An empty copy means "can't read", never "every key missing = on".
        let stored = CFPreferencesCopyMultiple(nil, domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
        guard !stored.isEmpty else {
            Log.checks.notice("softwareupdate.prefs unreadable")
            return .unreadable
        }
        var values: [String: PrefValue] = [:]
        for key in SoftwareUpdatePrefs.keys {
            if let effective = CFPreferencesCopyAppValue(key as CFString, domain) {
                values[key] = PrefValue(propertyList: effective)
            } else if let raw = stored[key] {
                values[key] = PrefValue(propertyList: raw)
            }
        }
        return SoftwareUpdatePrefs(readable: true, values: values)
    }

    func mobileMeAccountsPlist() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/MobileMeAccounts.plist")
        return Self.readSmallFile(url)
    }

    func xprotectInstalledVersions() -> XProtectInstalledVersions {
        XProtectInstalledVersions(
            bundleVersion: MacPreferenceParsers.bundleShortVersion(
                infoPlist: Self.readSmallFile(URL(fileURLWithPath: XProtectInstalledVersions.bundleInfoPlistPath))
            ),
            appVersion: MacPreferenceParsers.bundleShortVersion(
                infoPlist: Self.readSmallFile(URL(fileURLWithPath: XProtectInstalledVersions.appInfoPlistPath))
            )
        )
    }

    func deviceIdentity() -> MacDeviceIdentity {
        MacDeviceIdentity(
            ProcessInfo.processInfo.operatingSystemVersion,
            boardID: Self.sysctlString("hw.target"),
            modelID: Self.sysctlString("hw.model")
        )
    }

    // MARK: Helpers

    static func readSmallFile(_ url: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maxPlistBytes else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    /// A string sysctl value, or nil.
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size <= 256 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix(size).prefix { $0 != 0 }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
