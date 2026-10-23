// MacCheckSuite orchestration with fake readers: every P0 §6.2 check is produced, in order,
// from the right input; nothing blocks; failures degrade to unknown; demo states are fixed.

import XCTest
@testable import ShieldCore

struct FakeTools: ToolRunning {
    var outputs: [MacTool: ToolOutput]
    /// Records which tools ran.
    let calls = CallLog()

    func run(_ tool: MacTool) async -> ToolOutput {
        calls.record(tool)
        return outputs[tool] ?? ToolOutput(termination: .launchFailed)
    }

    final class CallLog: @unchecked Sendable {
        private let lock = NSLock()
        private var tools: [MacTool] = []
        func record(_ tool: MacTool) { lock.withLock { tools.append(tool) } }
        var all: [MacTool] { lock.withLock { tools } }
    }
}

struct FakeProbes: LoopbackProbing {
    var results: [UInt16: PortProbeResult]
    func probeRemoteAccessPorts() async -> [UInt16: PortProbeResult] { results }
}

struct FakeSystem: MacSystemReading {
    var prefs: SoftwareUpdatePrefs
    var mobileMe: Data?
    var xprotect: XProtectInstalledVersions
    var identity: MacDeviceIdentity

    func softwareUpdatePrefs() -> SoftwareUpdatePrefs { prefs }
    func mobileMeAccountsPlist() -> Data? { mobileMe }
    func xprotectInstalledVersions() -> XProtectInstalledVersions { xprotect }
    func deviceIdentity() -> MacDeviceIdentity { identity }
}

struct FakeVersion: MacVersionAssessing {
    var assessment: MacVersionAssessment
    func assess(_ identity: MacDeviceIdentity, now: Date) async -> MacVersionAssessment { assessment }
}

final class MacCheckSuiteTests: XCTestCase {

    static let healthyTools: [MacTool: ToolOutput] = [
        .fdesetupIsActive: .exited(0, stdout: "true\n"),
        .spctlStatus: .exited(0, stdout: "assessments enabled\n"),
        .csrutilStatus: .exited(0, stdout: "System Integrity Protection status: enabled.\n"),
        .sysadminctlScreenLock: .exited(0, stderr: "2026-10-22 21:24:38.219 sysadminctl[1:2] screenLock delay is immediate\n"),
        .firewallGlobalState: .exited(0, stdout: "Firewall is enabled. (State = 1)\n"),
        .profilesEnrollment: .exited(0, stdout: "Enrolled via DEP: No\nMDM enrollment: No\n"),
        .tmutilDestinationInfo: .exited(0, stdout: "Name : Backup\nID : 1\n"),
        .defaultsReadCatalogURL: .exited(1, stderr: "does not exist"),
    ]

    static let closedPorts: [UInt16: PortProbeResult] = [22: .closed, 5900: .closed, 445: .closed, 548: .closed]

    func healthySystem() throws -> FakeSystem {
        FakeSystem(
            prefs: SoftwareUpdatePrefs(plistData: try MacFixtures.data("softwareupdate_clean", "plist")),
            mobileMe: try MacFixtures.data("mobileme_findmy_on", "plist"),
            xprotect: XProtectInstalledVersions(bundleVersion: "5368", appVersion: "170"),
            identity: MacDeviceIdentity(osMajor: 26, osMinor: 7, osPatch: 1, boardID: "J704AP", modelID: "Mac17,2")
        )
    }

    static let patched = MacVersionAssessment(
        osPatched: .pass, activelyExploited: false, deviceSupported: .pass,
        xprotectFeed: XProtectFeedVersions(plistConfigData: "5368", payloads: "170")
    )

    func makeSuite(
        tools: [MacTool: ToolOutput] = healthyTools,
        ports: [UInt16: PortProbeResult] = closedPorts,
        system: FakeSystem,
        version: MacVersionAssessment = patched,
        mdmExpected: Bool = false,
        includeP1: Bool = false
    ) -> (MacCheckSuite, FakeTools) {
        let fakeTools = FakeTools(outputs: tools)
        let suite = MacCheckSuite(
            tools: fakeTools,
            probes: FakeProbes(results: ports),
            system: system,
            version: FakeVersion(assessment: version),
            clock: .fixed(MacFixtures.captureDate),
            mdmExpectedByOwner: mdmExpected,
            includeP1: includeP1
        )
        return (suite, fakeTools)
    }

    func testP0ListMatchesSpec() {
        XCTAssertEqual(MacCheckSuite.p0Checks.map(\.rawValue), [
            "os_patched", "os_update_stuck", "beta_catalog", "device_supported", "auto_updates", "filevault",
            "gatekeeper", "sip", "xprotect_current", "screen_lock", "find_my", "firewall", "remote_access_off",
            "mdm_unexpected",
        ])
    }

    func testHealthyMacAllPassInSpecOrder() async throws {
        let (suite, tools) = makeSuite(system: try healthySystem())
        let outcomes = await suite.run()
        XCTAssertEqual(outcomes.map(\.checkID), MacCheckSuite.p0Checks)
        for outcome in outcomes {
            XCTAssertEqual(outcome.status, .pass, outcome.checkID.rawValue)
            XCTAssertEqual(outcome.note, .measured, outcome.checkID.rawValue)
        }
        // Prefs were readable, so the `defaults` fallback and the P1 tool never ran.
        XCTAssertFalse(tools.calls.all.contains(.defaultsReadCatalogURL))
        XCTAssertFalse(tools.calls.all.contains(.tmutilDestinationInfo))
        XCTAssertEqual(Set(tools.calls.all), [
            .fdesetupIsActive, .spctlStatus, .csrutilStatus, .sysadminctlScreenLock, .firewallGlobalState, .profilesEnrollment,
        ])
    }

    func testBensMacMatchesSmokeTestExpectations() async throws {
        // §13.3: os_patched fail (red), os_update_stuck fail, beta_catalog fail, firewall fail (yellow);
        // filevault, gatekeeper, sip, find_my, screen_lock, remote_access_off pass.
        var tools = Self.healthyTools
        tools[.firewallGlobalState] = .exited(0, stdout: "Firewall is disabled. (State = 0)\n")
        var system = try healthySystem()
        system.prefs = SoftwareUpdatePrefs(plistData: try MacFixtures.data("softwareupdate_bens_mac_2026-10-22", "plist"))
        system.identity = MacDeviceIdentity(osMajor: 26, osMinor: 5, osPatch: 1, boardID: "J704AP", modelID: "Mac17,2")
        let version = BundledMacVersionAssessor.assessment(for: system.identity)

        let (suite, _) = makeSuite(tools: tools, system: system, version: version)
        let byID = Dictionary(uniqueKeysWithValues: await suite.run().map { ($0.checkID, $0) })

        XCTAssertEqual(byID[.osPatched]?.status, .fail)
        XCTAssertEqual(byID[.osPatched]?.tierOverride, .red)
        XCTAssertEqual(byID[.osUpdateStuck]?.status, .fail)
        XCTAssertEqual(byID[.betaCatalog]?.status, .fail)
        XCTAssertEqual(byID[.firewall]?.status, .fail)
        for id in [CheckID.filevault, .gatekeeper, .sip, .findMy, .screenLock, .remoteAccessOff, .autoUpdates, .mdmUnexpected] {
            XCTAssertEqual(byID[id]?.status, .pass, id.rawValue)
        }
        XCTAssertEqual(byID[.xprotectCurrent]?.status, .unknown, "bundled assessor has no feed")
    }

    func testEverythingBrokenIsUnknownNeverPass() async {
        let broken = FakeSystem(
            prefs: .unreadable,
            mobileMe: nil,
            xprotect: XProtectInstalledVersions(bundleVersion: nil, appVersion: nil),
            identity: MacDeviceIdentity(osMajor: 26, osMinor: 7, osPatch: 1, boardID: nil, modelID: nil)
        )
        let timedOut = Dictionary(uniqueKeysWithValues: MacTool.allCases.map { ($0, ToolOutput(termination: .timedOut)) })
        let (suite, tools) = makeSuite(
            tools: timedOut,
            ports: [22: .indeterminate, 5900: .indeterminate, 445: .indeterminate, 548: .indeterminate],
            system: broken,
            version: MacVersionAssessment(osPatched: .unknown, activelyExploited: false, deviceSupported: .unknown)
        )
        let outcomes = await suite.run()
        XCTAssertEqual(outcomes.count, MacCheckSuite.p0Checks.count)
        for outcome in outcomes {
            XCTAssertEqual(outcome.status, .unknown, outcome.checkID.rawValue)
        }
        XCTAssertTrue(tools.calls.all.contains(.defaultsReadCatalogURL), "unreadable prefs → defaults fallback")
    }

    func testBetaCatalogFallsBackToDefaultsTool() async throws {
        var system = try healthySystem()
        system.prefs = .unreadable
        var tools = Self.healthyTools
        tools[.defaultsReadCatalogURL] = .exited(0, stdout: "https://swscan.apple.com/content/catalogs/others/index-26seed-26.merged-1.sucatalog.gz\n")
        let (suite, _) = makeSuite(tools: tools, system: system)
        let beta = await suite.run().first { $0.checkID == .betaCatalog }
        XCTAssertEqual(beta?.status, .fail)
    }

    func testRemoteAccessRedWithScreenSharingExploit() async throws {
        var ports = Self.closedPorts
        ports[5900] = .open
        let exposed = MacVersionAssessment(
            osPatched: .fail, activelyExploited: true, unpatchedExploitedCVEs: [MacVersionAssessment.screenSharingBypassCVE],
            deviceSupported: .pass
        )
        let (suite, _) = makeSuite(ports: ports, system: try healthySystem(), version: exposed)
        let remote = await suite.run().first { $0.checkID == .remoteAccessOff }
        XCTAssertEqual(remote?.status, .fail)
        XCTAssertEqual(remote?.tierOverride, .red)
    }

    func testMDMExpectedFlagIsPassedThrough() async throws {
        var tools = Self.healthyTools
        tools[.profilesEnrollment] = .exited(0, stdout: "MDM enrollment: Yes (User Approved)\n")
        let (unexpected, _) = makeSuite(tools: tools, system: try healthySystem())
        let (expected, _) = makeSuite(tools: tools, system: try healthySystem(), mdmExpected: true)
        let first = await unexpected.run().first { $0.checkID == .mdmUnexpected }
        let second = await expected.run().first { $0.checkID == .mdmUnexpected }
        XCTAssertEqual(first?.status, .fail)
        XCTAssertEqual(second?.status, .pass)
        XCTAssertEqual(second?.note, .expectedByOwner)
    }

    func testIncludeP1AddsTimeMachine() async throws {
        let (suite, tools) = makeSuite(system: try healthySystem(), includeP1: true)
        let outcomes = await suite.run()
        XCTAssertEqual(outcomes.map(\.checkID), MacCheckSuite.p0Checks + [.timeMachine])
        XCTAssertEqual(suite.checkIDs, outcomes.map(\.checkID))
        XCTAssertEqual(outcomes.last?.status, .pass)
        XCTAssertTrue(tools.calls.all.contains(.tmutilDestinationInfo))
    }

    func testResultsAreMeasuredAndCarryOnlyContractFields() async throws {
        let (suite, _) = makeSuite(system: try healthySystem())
        let outcomes = await suite.run()
        let deviceID = UUID()
        let day = DateDay(MacFixtures.captureDate)
        let results = MacCheckSuite.results(outcomes, deviceID: deviceID, checkedOn: day, catalogVersion: 3)
        XCTAssertEqual(results.count, outcomes.count)
        for result in results {
            XCTAssertEqual(result.source, .measured)
            XCTAssertEqual(result.deviceID, deviceID)
            XCTAssertEqual(result.checkedOn, day)
            XCTAssertEqual(result.catalogVersion, 3)
            XCTAssertTrue(CheckResult.isValidRecordName(result.recordName))
        }
        // The sink's §8.3 checks accept them.
        let device = DeviceInfo(deviceID: deviceID, platform: .mac, enrolledOn: day, catalogVersion: 3, appBuild: 1, lastReport: day)
        XCTAssertNoThrow(try validateForSink(device: device, results: results))
        let sink = InMemoryResultSink()
        try await sink.upsert(device: device, results: results)
        let stored = await sink.results(for: deviceID)
        XCTAssertEqual(stored.count, MacCheckSuite.p0Checks.count)
    }

    // MARK: Demo states

    func testDemoStateNames() {
        XCTAssertEqual(MacDemoState(name: "protected"), .protected)
        XCTAssertEqual(MacDemoState(name: "Home-Protected"), .protected)
        XCTAssertEqual(MacDemoState(name: "one_red"), .oneRed)
        XCTAssertEqual(MacDemoState(name: "OneRed"), .oneRed)
        XCTAssertEqual(MacDemoState(name: "home_1_red"), .oneRed)
        XCTAssertEqual(MacDemoState(name: "bens-mac"), .bensMac)
        XCTAssertEqual(MacDemoState(name: "all_unknown"), .allUnknown)
        XCTAssertNil(MacDemoState(name: "nonsense"))
    }

    func testDemoOutcomes() {
        for state in MacDemoState.allCases {
            let outcomes = state.outcomes
            XCTAssertEqual(outcomes.map(\.checkID), MacCheckSuite.p0Checks, "\(state)")
            XCTAssertTrue(outcomes.allSatisfy { $0.note == .demo })
        }
        XCTAssertTrue(MacDemoState.protected.outcomes.allSatisfy { $0.status == .pass })
        XCTAssertTrue(MacDemoState.allUnknown.outcomes.allSatisfy { $0.status == .unknown })
        let red = MacDemoState.oneRed.outcomes.filter { $0.status == .fail }
        XCTAssertEqual(red.map(\.checkID), [.osPatched])
        XCTAssertEqual(red.first?.tierOverride, .red)
        XCTAssertEqual(
            Set(MacDemoState.bensMac.outcomes.filter { $0.status == .fail }.map(\.checkID)),
            [.osPatched, .osUpdateStuck, .betaCatalog, .firewall]
        )
    }
}
