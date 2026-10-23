// SHARED CONTRACT (scaffold). Every builder depends on this file.
// Change it only together with SPEC §6 and catalog.json; CatalogLintTests compares them.
//
// `CheckID` is the sync allowlist (SPEC §5.1, §8.3). Raw values are the exact wire IDs
// from SPEC §6. CloudKitSink must refuse to write any value that is not a case here.

import Foundation

/// Every check ID in SPEC §6. The raw value is the wire value (CloudKit `checkID` field,
/// record-name suffix, catalog.json key). Raw values match `^[a-z0-9_]{1,48}$`.
public enum CheckID: String, CaseIterable, Codable, Sendable, Hashable {

    // MARK: §6.1 iPhone, measured (some IDs are shared with the Mac)
    /// iPhone and Mac. §5.2.
    case osPatched = "os_patched"
    /// iPhone and Mac. §5.2 step 6.
    case deviceSupported = "device_supported"
    case passcodeSet = "passcode_set"
    case biometricsEnrolled = "biometrics_enrolled"
    /// Ben-only (family banner at day 60).
    case appBuildFresh = "app_build_fresh"

    // MARK: §6.2 Mac, measured
    case osUpdateStuck = "os_update_stuck"
    /// Ben-only.
    case betaCatalog = "beta_catalog"
    /// Measured on the Mac, self-reported on iOS (§6.3).
    case autoUpdates = "auto_updates"
    case filevault = "filevault"
    case gatekeeper = "gatekeeper"
    case sip = "sip"
    case xprotectCurrent = "xprotect_current"
    case screenLock = "screen_lock"
    /// Measured on the Mac, self-reported on iOS (§6.3).
    case findMy = "find_my"
    case firewall = "firewall"
    case remoteAccessOff = "remote_access_off"
    case mdmUnexpected = "mdm_unexpected"
    /// P1.
    case timeMachine = "time_machine"
    /// P1, Ben-only. The relative sees nothing.
    case persistenceNewItem = "persistence_new_item"
    /// P2, Ben-only.
    case chromeExtForced = "chrome_ext_forced"
    /// Not measured. "Check yourself" link only; never fails (§6.2).
    case lockdown = "lockdown"
    /// Not measured. "Check yourself" link only; never fails (§6.2).
    case adp = "adp"

    // MARK: §6.3 Guided self-checks ("confirmed by you")
    case stolenDeviceProtection = "stolen_device_protection"
    case recoveryContact = "recovery_contact"
    case screenUnknown = "screen_unknown"
    case familyCodeWord = "family_code_word"
    case carrierLock = "carrier_lock"
    case creditFreezeEquifax = "credit_freeze_equifax"
    case creditFreezeExperian = "credit_freeze_experian"
    case creditFreezeTransunion = "credit_freeze_transunion"
    /// P1.
    case passwordsAlertsClear = "passwords_alerts_clear"
    /// P1.
    case fraudWebsiteWarning = "fraud_website_warning"
    /// P1.
    case safetyCheckQuarterly = "safety_check_quarterly"
    /// P2, optional. Never counts against status.
    case advancedDataProtection = "advanced_data_protection"

    // MARK: §6.4 Online-account category rollups (the only account data that syncs)
    case accountsEmail = "accounts_email"
    case accountsMoney = "accounts_money"
    case accountsSocial = "accounts_social"
    case accountsShopping = "accounts_shopping"
    case accountsGovernment = "accounts_government"
    case accountsHealth = "accounts_health"
}

extension CheckID {
    /// The six §6.4 category rollups, in spec order.
    public static let accountRollups: [CheckID] = [
        .accountsEmail, .accountsMoney, .accountsSocial,
        .accountsShopping, .accountsGovernment, .accountsHealth,
    ]

    /// True for the §6.4 `accounts_*` rollups.
    public var isAccountRollup: Bool { Self.accountRollups.contains(self) }

    /// IDs the spec says never fail and never count against status
    /// (§6.2 `lockdown`, `adp`; §6.3 `advanced_data_protection`).
    public static let neverFails: Set<CheckID> = [.lockdown, .adp, .advancedDataProtection]

    /// The wire format rule for check IDs (§8.3 record name suffix, §9.2 `check_id`).
    public static let wirePattern = "^[a-z0-9_]{1,48}$"

    /// The allowlist gate. Returns nil for any string that is not a known check ID.
    public static func allowlisted(_ wireValue: String) -> CheckID? {
        CheckID(rawValue: wireValue)
    }
}

/// Info-only items (SPEC §6.5, §12.8). These are deliberately NOT `CheckID` cases, so the
/// sync allowlist can never carry them. Show them on the device only.
public enum LocalInfoID: String, CaseIterable, Codable, Sendable, Hashable {
    case scamCheckerAvailable = "scam_checker_available"
    /// Would leak device class if synced (§6.5).
    case llmAvailable = "llm_available"
    /// "Last checked …" on the device; Feed health on Ben's device.
    case feedFresh = "feed_fresh"
    /// Ben's dashboard only (§12.8).
    case appOutdated = "app_outdated"
}
