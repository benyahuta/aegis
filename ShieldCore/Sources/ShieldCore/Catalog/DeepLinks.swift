// SHARED CONTRACT (scaffold shell). The Catalog builder owns and extends this file.
// SPEC §6 deep-link legend, §12.4: every displayed URL comes from compiled constants in
// DeepLinks.swift, Services.swift or catalog.json. `URL(string:` anywhere else fails CI lint.
//
// - iOS: fix cards open the Settings app's home screen (`App-prefs:`). iOS 26 ignores the
//   pane path in these URLs (tested on the iOS 26.5 simulator: even `App-prefs:General` lands on
//   the top level), so every card also shows the written path. If the URL is refused, the card
//   falls back to `UIApplication.openSettingsURLString` (Family Shield's own Settings page),
//   which is also what the Reminders screen uses on purpose.
// - Mac: only `x-apple.systempreferences:` URLs verified on macOS 26.5.1
//   (docs/research/ux-older-adults.md §2.1). Every card also shows the written path,
//   because a wrong link fails silently.

import Foundation
#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

/// A Settings destination a fix card can open. The raw value is the catalog.json `deepLink` string.
public enum DeepLink: String, CaseIterable, Codable, Sendable, Hashable {
    // MARK: iOS
    /// `UIApplication.openSettingsURLString`. ShieldCore cannot read that UIKit constant on the
    /// Mac, so `url` is nil here; the iOS app resolves it with `UIApplication.openSettingsURLString`.
    case iosAppSettings = "ios_app_settings"
    /// The Settings app's home screen. Used by every iOS fix card.
    case iosSettingsHome = "ios_settings_home"

    // MARK: Mac (x-apple.systempreferences:)
    case macSoftwareUpdate = "mac_software_update"
    case macPrivacySecurity = "mac_privacy_security"
    case macSecurity = "mac_security"
    case macFileVault = "mac_filevault"
    case macLockdownMode = "mac_lockdown_mode"
    /// Privacy & Security → Background Security Improvements (macOS 26.1+). The search anchor
    /// `SecurityImprovements` is in PrivacySecurity.searchTerms on macOS 26.5.1
    /// (docs/verified/AUDITED.md §1 #9), but the URL has not been opened yet. Not used by any
    /// card until Ben's `tools/deeplink-test.sh` run confirms it; the BSI step stays written only.
    case macSecurityImprovements = "mac_security_improvements"
    case macLockScreen = "mac_lock_screen"
    case macAppleAccount = "mac_apple_account"
    case macICloud = "mac_icloud"
    /// Opens Network only; the copy must say "then click **Firewall**" (§6.2).
    case macFirewall = "mac_firewall"
    case macSharing = "mac_sharing"
    case macProfiles = "mac_profiles"
    case macTimeMachine = "mac_time_machine"
    /// Used when `SMAppService.mainApp.status == .requiresApproval` (§10.2).
    case macLoginItems = "mac_login_items"
}

extension DeepLink {
    /// The platform this link works on.
    public var platform: Platform {
        switch self {
        case .iosAppSettings, .iosSettingsHome: .ios
        default: .mac
        }
    }

    /// The exact URL string. nil for `.iosAppSettings` (see that case).
    public var urlString: String? {
        let prefix = "x-apple.systempreferences:"
        switch self {
        case .iosAppSettings: return nil
        case .iosSettingsHome: return "App-prefs:"
        case .macSoftwareUpdate: return prefix + "com.apple.Software-Update-Settings.extension"
        case .macPrivacySecurity: return prefix + "com.apple.settings.PrivacySecurity.extension"
        case .macSecurity: return prefix + "com.apple.settings.PrivacySecurity.extension?Security"
        case .macFileVault: return prefix + "com.apple.settings.PrivacySecurity.extension?FileVault"
        case .macLockdownMode: return prefix + "com.apple.settings.PrivacySecurity.extension?LockdownMode"
        case .macSecurityImprovements: return prefix + "com.apple.settings.PrivacySecurity.extension?SecurityImprovements"
        case .macLockScreen: return prefix + "com.apple.Lock-Screen-Settings.extension"
        case .macAppleAccount: return prefix + "com.apple.systempreferences.AppleIDSettings"
        case .macICloud: return prefix + "com.apple.systempreferences.AppleIDSettings?iCloud"
        case .macFirewall: return prefix + "com.apple.Network-Settings.extension?Firewall"
        case .macSharing: return prefix + "com.apple.Sharing-Settings.extension"
        case .macProfiles: return prefix + "com.apple.Profiles-Settings.extension"
        case .macTimeMachine: return prefix + "com.apple.Time-Machine-Settings.extension"
        case .macLoginItems: return prefix + "com.apple.LoginItems-Settings.extension"
        }
    }

    /// The URL to open, or nil for `.iosAppSettings`.
    public var url: URL? {
        urlString.flatMap { URL(string: $0) }
    }
}

// MARK: - Catalog builder additions (additive; nothing above changed)

extension DeepLink {
    /// The URL a fix card should open on this platform. On iOS, `.iosAppSettings` resolves to
    /// `UIApplication.openSettingsURLString` (Family Shield's own Settings page). A link for the
    /// other platform returns nil, so a card never opens the wrong kind of link.
    @MainActor
    public var openableURL: URL? {
        guard platform == .current else { return nil }
        #if canImport(UIKit) && !os(macOS)
        if self == .iosAppSettings {
            return URL(string: UIApplication.openSettingsURLString)
        }
        #endif
        return url
    }

    /// Where to go if iOS refuses `openableURL`: Family Shield's own Settings page, which is
    /// one tap from the Settings home screen. nil on the Mac.
    @MainActor
    public var fallbackURL: URL? {
        #if canImport(UIKit) && !os(macOS)
        if self == .iosSettingsHome {
            return URL(string: UIApplication.openSettingsURLString)
        }
        #endif
        return nil
    }

    /// Button title key: "Open Settings" (iOS) or "Open System Settings" (Mac).
    public var buttonTitleKey: String {
        platform == .ios ? "deeplink.open.ios" : "deeplink.open.mac"
    }
}

/// Official https pages shown outside the check catalog and the service catalog (§10.1, §6.3).
/// Like every displayed URL, they are compiled constants (§12.4).
public enum OfficialLinks {
    /// "Report it at ReportFraud.ftc.gov" on the scam result screen (§10.1).
    public static let reportFraudFTCString = "https://reportfraud.ftc.gov/"
    /// "Why am I seeing this?" on update fix steps (§10.1): Apple security releases.
    public static let appleSecurityReleasesString = "https://support.apple.com/en-us/100100"
    /// FTC overview of credit freezes (verified 2026-10-22; the §6.3 slug was not the indexed
    /// page). Each `credit_freeze_*` item opens its own bureau's free-freeze page instead
    /// (catalog.json `supportURL`).
    public static let ftcCreditFreezesString = "https://consumer.ftc.gov/articles/credit-freezes-and-fraud-alerts"

    public static var reportFraudFTC: URL? { httpsURL(reportFraudFTCString) }
    public static var appleSecurityReleases: URL? { httpsURL(appleSecurityReleasesString) }
    public static var ftcCreditFreezes: URL? { httpsURL(ftcCreditFreezesString) }

    /// Every constant above, for lint tests.
    public static let allStrings = [reportFraudFTCString, appleSecurityReleasesString, ftcCreditFreezesString]

    /// A `tel:` URL for **Call Ben** (§10.1), built from the number picked in Contacts and kept
    /// on the device. Keeps only digits and a leading "+", so nothing else can be injected.
    /// Lives here so app code never needs its own `URL(string:)` (§12.4 lint).
    public static func telURL(_ phoneNumber: String) -> URL? {
        // Same rules as the saved Call Ben number: stop at a pause or extension, never join them.
        guard let number = CallBenNumber.clean(phoneNumber) else { return nil }
        return URL(string: "tel:\(number)")
    }

    /// Parses an https URL with a host. Anything else (http, custom schemes, junk) is nil.
    /// Web-page URLs in ShieldCore are built only here (§12.4 lint).
    public static func httpsURL(_ string: String) -> URL? {
        guard string.hasPrefix("https://"),
              let url = URL(string: string),
              url.scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
