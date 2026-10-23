// Runs every P0 Mac check in SPEC §6.2 against injected readers and maps the raw inputs through
// the pure parsers. The Mac app supplies the real readers (ShieldMac/Checks); tests supply fakes.
//
// Nothing here changes a setting (H3), asks for admin, or touches the network beyond loopback.
// Raw inputs (tool output, plist contents, versions) stay inside `run()`; only outcomes leave.

import Foundation

// MARK: - Reader seams

/// Runs one allowlisted tool (ShieldMac `ProcessRunner`; `BoundedProcess` underneath).
public protocol ToolRunning: Sendable {
    func run(_ tool: MacTool) async -> ToolOutput
}

/// Probes the §6.2 loopback ports (`LoopbackProber`).
public protocol LoopbackProbing: Sendable {
    func probeRemoteAccessPorts() async -> [UInt16: PortProbeResult]
}

/// In-process reads (CFPreferences, files, sysctl). Every method must return "unreadable"
/// values (`.unreadable`, nil) on any error rather than throwing or guessing.
public protocol MacSystemReading: Sendable {
    /// `com.apple.SoftwareUpdate`, only the `SoftwareUpdatePrefs.keys` values.
    func softwareUpdatePrefs() -> SoftwareUpdatePrefs
    /// Raw bytes of `~/Library/Preferences/MobileMeAccounts.plist`, or nil. The suite parses it
    /// immediately for the one `find_my` flag and drops it (§12.2).
    func mobileMeAccountsPlist() -> Data?
    func xprotectInstalledVersions() -> XProtectInstalledVersions
    func deviceIdentity() -> MacDeviceIdentity
}

// MARK: - Suite

public struct MacCheckSuite: Sendable {
    /// Every P0 Mac check in §6.2, in spec order. `run()` returns exactly these, in this order.
    public static let p0Checks: [CheckID] = [
        .osPatched, .osUpdateStuck, .betaCatalog, .deviceSupported, .autoUpdates, .filevault,
        .gatekeeper, .sip, .xprotectCurrent, .screenLock, .findMy, .firewall, .remoteAccessOff,
        .mdmUnexpected,
    ]
    /// P1 measured checks this suite can also run (`includeP1`).
    public static let p1Checks: [CheckID] = [.timeMachine]

    private let tools: any ToolRunning
    private let probes: any LoopbackProbing
    private let system: any MacSystemReading
    private let version: any MacVersionAssessing
    private let clock: Clock
    private let mdmExpectedByOwner: Bool
    private let includeP1: Bool

    /// - Parameter mdmExpectedByOwner: Ben's local "MDM is expected" mark (his own Mac only, §6.2).
    public init(
        tools: any ToolRunning,
        probes: any LoopbackProbing,
        system: any MacSystemReading,
        version: any MacVersionAssessing,
        clock: Clock = .system,
        mdmExpectedByOwner: Bool = false,
        includeP1: Bool = false
    ) {
        self.tools = tools
        self.probes = probes
        self.system = system
        self.version = version
        self.clock = clock
        self.mdmExpectedByOwner = mdmExpectedByOwner
        self.includeP1 = includeP1
    }

    /// The IDs `run()` will return.
    public var checkIDs: [CheckID] { includeP1 ? Self.p0Checks + Self.p1Checks : Self.p0Checks }

    /// Runs every check concurrently. Never throws: every failure is an `.unknown` outcome.
    public func run() async -> [MacCheckOutcome] {
        let now = clock.now()
        let identity = system.deviceIdentity()

        async let assessment = version.assess(identity, now: now)
        async let fileVault = tools.run(.fdesetupIsActive)
        async let gatekeeper = tools.run(.spctlStatus)
        async let sip = tools.run(.csrutilStatus)
        async let screenLock = tools.run(.sysadminctlScreenLock)
        async let firewall = tools.run(.firewallGlobalState)
        async let mdm = tools.run(.profilesEnrollment)
        async let ports = probes.probeRemoteAccessPorts()

        let prefs = system.softwareUpdatePrefs()
        // Parse and drop the MobileMeAccounts bytes right away (§12.2).
        let findMy = MacPreferenceParsers.findMy(mobileMeAccountsPlist: system.mobileMeAccountsPlist())
        let xprotectInstalled = system.xprotectInstalledVersions()

        var betaCatalog = MacPreferenceParsers.betaCatalog(prefs)
        if betaCatalog.note == .dataUnavailable {
            betaCatalog = MacToolParsers.betaCatalog(defaultsOutput: await tools.run(.defaultsReadCatalogURL))
        }

        var timeMachine: MacCheckOutcome?
        if includeP1 {
            timeMachine = MacToolParsers.timeMachine(await tools.run(.tmutilDestinationInfo))
        }

        let versionAssessment = await assessment
        var outcomes: [MacCheckOutcome] = [
            MacDerivedParsers.osPatched(versionAssessment),
            MacPreferenceParsers.updateStuck(prefs, now: now),
            betaCatalog,
            MacDerivedParsers.deviceSupported(versionAssessment),
            MacPreferenceParsers.autoUpdates(prefs),
            MacToolParsers.fileVault(await fileVault),
            MacToolParsers.gatekeeper(await gatekeeper),
            MacToolParsers.sip(await sip),
            MacPreferenceParsers.xprotect(installed: xprotectInstalled, feed: versionAssessment.xprotectFeed),
            MacToolParsers.screenLock(await screenLock),
            findMy,
            MacToolParsers.firewall(await firewall),
            MacDerivedParsers.remoteAccess(
                await ports,
                screenSharingExploitUnpatched: versionAssessment.screenSharingExploitUnpatched
            ),
            MacToolParsers.mdmEnrollment(await mdm, expectedByOwner: mdmExpectedByOwner),
        ]
        if let timeMachine { outcomes.append(timeMachine) }

        for outcome in outcomes {
            Log.checks.info("check \(outcome.checkID.rawValue, privacy: .public) status=\(outcome.status.rawValue, privacy: .public) note=\(outcome.note.rawValue, privacy: .public)")
        }
        return outcomes
    }

    /// The synced form of `outcomes` (§8.2 fields only, `source = .measured`).
    public static func results(
        _ outcomes: [MacCheckOutcome],
        deviceID: UUID,
        checkedOn: DateDay,
        catalogVersion: Int
    ) -> [CheckResult] {
        outcomes.map { $0.checkResult(deviceID: deviceID, checkedOn: checkedOn, catalogVersion: catalogVersion) }
    }
}

// MARK: - Demo states (-FSDemoState, §13.2)

/// Fixed outcomes for screenshots and UI tests. No tool, file or port is touched.
public enum MacDemoState: String, CaseIterable, Sendable {
    /// Every P0 check passes ("You're protected").
    case protected = "protected"
    /// One red item: `os_patched` fails, actively exploited.
    case oneRed = "one_red"
    /// Ben's Mac today (§13.3): os_patched red, os_update_stuck, beta_catalog, firewall fail.
    case bensMac = "bens_mac"
    /// Nothing could be checked.
    case allUnknown = "all_unknown"

    /// Accepts the raw value, ignoring case, `-`, `_` and spaces ("one-red", "OneRed", "home_one_red").
    public init?(name: String) {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "protected", "homeprotected": self = .protected
        case "onered", "1red", "homeonered", "home1red": self = .oneRed
        case "bensmac", "smoke", "smoketest": self = .bensMac
        case "allunknown", "unknown": self = .allUnknown
        default: return nil
        }
    }

    public var outcomes: [MacCheckOutcome] {
        MacCheckSuite.p0Checks.map { id in
            switch self {
            case .protected:
                return MacCheckOutcome(checkID: id, status: .pass, note: .demo)
            case .allUnknown:
                return MacCheckOutcome(checkID: id, status: .unknown, note: .demo)
            case .oneRed:
                return id == .osPatched
                    ? MacCheckOutcome(checkID: id, status: .fail, note: .demo, tierOverride: .red)
                    : MacCheckOutcome(checkID: id, status: .pass, note: .demo)
            case .bensMac:
                switch id {
                case .osPatched:
                    return MacCheckOutcome(checkID: id, status: .fail, note: .demo, tierOverride: .red)
                case .osUpdateStuck, .betaCatalog, .firewall:
                    return MacCheckOutcome(checkID: id, status: .fail, note: .demo)
                default:
                    return MacCheckOutcome(checkID: id, status: .pass, note: .demo)
                }
            }
        }
    }
}
