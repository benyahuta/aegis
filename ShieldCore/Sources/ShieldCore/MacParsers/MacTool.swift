// The child-process allowlist for the Mac checks (SPEC §6.2, §12.5).
//
// Every child process the Mac app starts is one of these cases: an absolute path to an Apple tool
// and a fixed argument array. There is no way to build an invocation from a string, so no caller
// can add a path, an argument or a shell. `sfltool` is deliberately absent (it can prompt for admin,
// §6.2), as are `sudo`, `systemsetup` and every shell.

import Foundation

/// One allowlisted, read-only tool invocation.
public enum MacTool: String, CaseIterable, Sendable, Hashable {
    /// `filevault`: exit 0 + "true" = on, exit 1 + "false" = off.
    case fdesetupIsActive = "fdesetup_isactive"
    /// `gatekeeper`: "assessments enabled".
    case spctlStatus = "spctl_status"
    /// `sip`: "System Integrity Protection status: enabled."
    case csrutilStatus = "csrutil_status"
    /// `screen_lock`: the answer is an NSLog line on **stderr**.
    case sysadminctlScreenLock = "sysadminctl_screenlock"
    /// `firewall`: "Firewall is enabled. (State = 1)".
    case firewallGlobalState = "socketfilterfw_globalstate"
    /// `mdm_unexpected`: "MDM enrollment: No".
    case profilesEnrollment = "profiles_enrollment"
    /// `time_machine` (P1): "No destinations configured." or one block per destination.
    case tmutilDestinationInfo = "tmutil_destinationinfo"
    /// `beta_catalog` fallback when CFPreferences cannot read the SoftwareUpdate domain.
    case defaultsReadCatalogURL = "defaults_catalogurl"

    /// The absolute path of the executable.
    public var executablePath: String {
        switch self {
        case .fdesetupIsActive: "/usr/bin/fdesetup"
        case .spctlStatus: "/usr/sbin/spctl"
        case .csrutilStatus: "/usr/bin/csrutil"
        case .sysadminctlScreenLock: "/usr/sbin/sysadminctl"
        case .firewallGlobalState: "/usr/libexec/ApplicationFirewall/socketfilterfw"
        case .profilesEnrollment: "/usr/bin/profiles"
        case .tmutilDestinationInfo: "/usr/bin/tmutil"
        case .defaultsReadCatalogURL: "/usr/bin/defaults"
        }
    }

    /// The fixed argument array (never built from input).
    public var arguments: [String] {
        switch self {
        case .fdesetupIsActive: ["isactive"]
        case .spctlStatus: ["--status"]
        case .csrutilStatus: ["status"]
        case .sysadminctlScreenLock: ["-screenLock", "status"]
        case .firewallGlobalState: ["--getglobalstate"]
        case .profilesEnrollment: ["status", "-type", "enrollment"]
        case .tmutilDestinationInfo: ["destinationinfo"]
        case .defaultsReadCatalogURL: ["read", "/Library/Preferences/com.apple.SoftwareUpdate", "CatalogURL"]
        }
    }

    /// The §12.5 executable allowlist: `fdesetup`, `spctl`, `csrutil`, `sysadminctl`,
    /// `socketfilterfw`, `profiles`, `tmutil`, `defaults`. Absolute paths only.
    public static let allowedExecutables: Set<String> = [
        "/usr/bin/fdesetup",
        "/usr/sbin/spctl",
        "/usr/bin/csrutil",
        "/usr/sbin/sysadminctl",
        "/usr/libexec/ApplicationFirewall/socketfilterfw",
        "/usr/bin/profiles",
        "/usr/bin/tmutil",
        "/usr/bin/defaults",
    ]

    /// Defense in depth: true when the path is absolute and on the allowlist.
    public var isAllowlisted: Bool {
        executablePath.hasPrefix("/") && MacTool.allowedExecutables.contains(executablePath)
    }
}
