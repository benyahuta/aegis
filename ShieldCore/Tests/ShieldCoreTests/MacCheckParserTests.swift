// MacCheckParserTests (SPEC §13.1): captured outputs for each tool (on/off/error/garbage) →
// pass/fail/unknown, including `sysadminctl` stderr parsing; plus the in-process parsers.

import XCTest
@testable import ShieldCore

enum MacFixtures {
    static func url(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures/MacChecks"),
            "missing fixture \(name).\(ext)"
        )
    }

    static func data(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: url(name, ext))
    }

    struct ToolCase: Decodable {
        let tool: String
        let name: String
        let captured: Bool?
        let termination: String
        let exit: Int32?
        let stdout: String
        let stderr: String
        let expect: String

        var output: ToolOutput {
            let termination: ToolOutput.Termination = switch self.termination {
            case "exit": .exited(exit ?? -1)
            case "timeout": .timedOut
            case "launch_failed": .launchFailed
            case "signal": .signaled(exit ?? 9)
            default: .notAllowed
            }
            return ToolOutput(termination: termination, stdout: stdout, stderr: stderr)
        }

        var expectedStatus: Status? {
            switch expect {
            case "pass": .pass
            case "fail": .fail
            case "unknown": .unknown
            default: nil
            }
        }
    }

    struct ToolCaseFile: Decodable { let cases: [ToolCase] }

    static func toolCases() throws -> [ToolCase] {
        try JSONDecoder().decode(ToolCaseFile.self, from: data("tool_outputs", "json")).cases
    }

    /// Ben's Mac's "now" when the fixtures were captured.
    static let captureDate = ISO8601DateFormatter().date(from: "2026-10-22T21:24:00-04:00")!
}

final class MacCheckParserTests: XCTestCase {

    // MARK: Table-driven: every captured / synthesized tool output

    func parse(_ tool: MacTool, _ output: ToolOutput) -> MacCheckOutcome {
        switch tool {
        case .fdesetupIsActive: MacToolParsers.fileVault(output)
        case .spctlStatus: MacToolParsers.gatekeeper(output)
        case .csrutilStatus: MacToolParsers.sip(output)
        case .sysadminctlScreenLock: MacToolParsers.screenLock(output)
        case .firewallGlobalState: MacToolParsers.firewall(output)
        case .profilesEnrollment: MacToolParsers.mdmEnrollment(output)
        case .tmutilDestinationInfo: MacToolParsers.timeMachine(output)
        case .defaultsReadCatalogURL: MacToolParsers.betaCatalog(defaultsOutput: output)
        }
    }

    func testEveryFixtureCaseMatchesExpectation() throws {
        let cases = try MacFixtures.toolCases()
        XCTAssertGreaterThanOrEqual(cases.count, 40)
        for testCase in cases {
            let tool = try XCTUnwrap(MacTool(rawValue: testCase.tool), "unknown tool \(testCase.tool)")
            let expected = try XCTUnwrap(testCase.expectedStatus, "bad expect in \(testCase.name)")
            let outcome = parse(tool, testCase.output)
            XCTAssertEqual(outcome.status, expected, "\(testCase.tool)/\(testCase.name)")
            if expected != .unknown {
                XCTAssertEqual(outcome.note, .measured, "\(testCase.tool)/\(testCase.name)")
            }
        }
    }

    func testEveryToolHasOnOffErrorAndGarbageCases() throws {
        let cases = try MacFixtures.toolCases()
        for tool in MacTool.allCases {
            let mine = cases.filter { $0.tool == tool.rawValue }
            XCTAssertTrue(mine.contains { $0.expect == "pass" }, "\(tool) has no pass case")
            XCTAssertTrue(mine.contains { $0.expect == "fail" }, "\(tool) has no fail case")
            XCTAssertGreaterThanOrEqual(mine.filter { $0.expect == "unknown" }.count, 2, "\(tool) needs error + garbage")
            XCTAssertTrue(mine.contains { $0.captured == true }, "\(tool) has no captured case")
        }
    }

    // MARK: H7 — every abnormal termination is unknown for every tool, whatever the text says

    func testAbnormalTerminationIsNeverPass() {
        let onText = "true\nassessments enabled\nSystem Integrity Protection status: enabled.\nFirewall is enabled. (State = 1)\nMDM enrollment: No\nID : x\n"
        let terminations: [(ToolOutput.Termination, MacCheckNote)] = [
            (.timedOut, .timedOut), (.launchFailed, .toolFailed), (.notAllowed, .toolFailed), (.signaled(15), .toolFailed),
        ]
        for tool in MacTool.allCases {
            for (termination, note) in terminations {
                let output = ToolOutput(termination: termination, stdout: onText, stderr: "screenLock delay is immediate")
                let outcome = parse(tool, output)
                XCTAssertEqual(outcome.status, .unknown, "\(tool) \(termination)")
                XCTAssertEqual(outcome.note, note, "\(tool) \(termination)")
            }
        }
    }

    func testTruncatedOutputIsUnknown() {
        for tool in MacTool.allCases {
            var output = ToolOutput.exited(0, stdout: "true\nassessments enabled\n", stderr: "screenLock delay is immediate")
            output.stdoutTruncated = true
            let outcome = parse(tool, output)
            XCTAssertEqual(outcome.status, .unknown, "\(tool)")
            XCTAssertEqual(outcome.note, .unparseable, "\(tool)")
        }
    }

    func testNonZeroExitNotes() {
        XCTAssertEqual(MacToolParsers.fileVault(.exited(2)).note, .toolFailed)
        XCTAssertEqual(MacToolParsers.gatekeeper(.exited(3)).note, .toolFailed)
        XCTAssertEqual(MacToolParsers.sip(.exited(1)).note, .toolFailed)
        XCTAssertEqual(MacToolParsers.screenLock(.exited(1)).note, .toolFailed)
        XCTAssertEqual(MacToolParsers.firewall(.exited(1)).note, .toolFailed)
        XCTAssertEqual(MacToolParsers.mdmEnrollment(.exited(1)).note, .toolFailed)
        XCTAssertEqual(MacToolParsers.fileVault(.exited(0, stdout: "maybe")).note, .unparseable)
    }

    // MARK: sysadminctl stderr parsing

    func testScreenLockParsesNSLogLineOnStderr() {
        let line = "2026-10-22 21:24:38.219 sysadminctl[7557:19628757] screenLock delay is immediate"
        XCTAssertEqual(MacToolParsers.parseScreenLock(line), .immediate)
        XCTAssertEqual(MacToolParsers.parseScreenLock("x screenLock delay is 5 seconds"), .delay(seconds: 5))
        XCTAssertEqual(MacToolParsers.parseScreenLock("x screenLock delay is 1 second"), .delay(seconds: 1))
        XCTAssertEqual(MacToolParsers.parseScreenLock("x screenLock delay is 2 minutes"), .delay(seconds: 120))
        XCTAssertEqual(MacToolParsers.parseScreenLock("x screenLock is off"), .off)
        XCTAssertEqual(MacToolParsers.parseScreenLock("x screenLock is disabled"), .off)
        XCTAssertNil(MacToolParsers.parseScreenLock("x screenLock delay is soon"))
        XCTAssertNil(MacToolParsers.parseScreenLock("x screenLock delay is 5 fortnights"))
        XCTAssertNil(MacToolParsers.parseScreenLock(""))
    }

    func testScreenLockReadsStderrNotJustStdout() {
        let captured = ToolOutput.exited(0, stdout: "", stderr: "2026-10-22 21:24:38.219 sysadminctl[7557:19628757] screenLock delay is immediate\n")
        XCTAssertEqual(MacToolParsers.screenLock(captured).status, .pass)
        // stderr wins over stdout when both carry an answer.
        let both = ToolOutput.exited(0, stdout: "screenLock delay is immediate", stderr: "screenLock delay is 300 seconds")
        XCTAssertEqual(MacToolParsers.screenLock(both).status, .fail)
        // Boundary: 5 s passes, 6 s fails.
        XCTAssertEqual(MacToolParsers.screenLock(.exited(0, stderr: "screenLock delay is 6 seconds")).status, .fail)
        XCTAssertEqual(MacToolParsers.screenLock(.exited(0, stderr: "screenLock delay is 5 seconds")).status, .pass)
        XCTAssertEqual(MacToolParsers.screenLock(.exited(0, stderr: "screenLock delay is 0 seconds")).status, .pass)
    }

    // MARK: Other single-tool details

    func testFirewallStateParsing() {
        XCTAssertEqual(MacToolParsers.parseFirewallState("Firewall is disabled. (State = 0)"), 0)
        XCTAssertEqual(MacToolParsers.parseFirewallState("Firewall is enabled. (State = 1)"), 1)
        XCTAssertNil(MacToolParsers.parseFirewallState("Firewall is enabled."))
        XCTAssertEqual(MacToolParsers.firewall(.exited(0, stdout: "Firewall is enabled.\n")).status, .pass)
        XCTAssertEqual(MacToolParsers.firewall(.exited(0, stdout: "Firewall is disabled.\n")).status, .fail)
    }

    func testMDMExpectedByOwnerIsLocalPass() {
        let enrolled = ToolOutput.exited(0, stdout: "Enrolled via DEP: No\nMDM enrollment: Yes\n")
        XCTAssertEqual(MacToolParsers.mdmEnrollment(enrolled).status, .fail)
        let expected = MacToolParsers.mdmEnrollment(enrolled, expectedByOwner: true)
        XCTAssertEqual(expected.status, .pass)
        XCTAssertEqual(expected.note, .expectedByOwner)
        // The mark never turns an unreadable answer green.
        XCTAssertEqual(MacToolParsers.mdmEnrollment(.exited(0, stdout: "?"), expectedByOwner: true).status, .unknown)
    }

    func testDefaultsCatalogURLParse() {
        XCTAssertEqual(MacToolParsers.parseDefaultsCatalogURL(.exited(0, stdout: "https://a/b\n")), .some("https://a/b"))
        XCTAssertEqual(
            MacToolParsers.parseDefaultsCatalogURL(.exited(1, stderr: "The domain/default pair of (x, CatalogURL) does not exist")),
            .some(nil)
        )
        let untrusted: String?? = MacToolParsers.parseDefaultsCatalogURL(.exited(1, stderr: "boom"))
        XCTAssertTrue(untrusted == nil)
    }
}

final class MacPreferenceParserTests: XCTestCase {

    func prefs(_ name: String) throws -> SoftwareUpdatePrefs {
        SoftwareUpdatePrefs(plistData: try MacFixtures.data(name, "plist"))
    }

    // MARK: Ben's Mac, captured 2026-10-22 (§13.3 expectations)

    func testBensMacSoftwareUpdatePrefs() throws {
        let bens = try prefs("softwareupdate_bens_mac_2026-10-22")
        XCTAssertTrue(bens.readable)
        XCTAssertEqual(MacPreferenceParsers.autoUpdates(bens).status, .pass, "all flags on; AutomaticCheckEnabled missing = on")
        XCTAssertEqual(MacPreferenceParsers.updateStuck(bens, now: MacFixtures.captureDate).status, .fail, "5 failures, 8 days ago")
        XCTAssertEqual(MacPreferenceParsers.betaCatalog(bens).status, .fail, "index-26beta catalog")
    }

    func testUpdateStuckWindow() throws {
        let bens = try prefs("softwareupdate_bens_mac_2026-10-22")
        let failure = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T22:35:25-04:00"))
        XCTAssertEqual(MacPreferenceParsers.updateStuck(bens, now: failure.addingTimeInterval(14 * 86_400)).status, .fail)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(bens, now: failure.addingTimeInterval(14 * 86_400 + 1)).status, .pass)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(bens, now: failure.addingTimeInterval(-3600)).status, .fail, "future timestamp counts as recent")
    }

    func testUpdateStuckCountThresholdAndDateForms() {
        let now = MacFixtures.captureDate
        func ddm(_ count: PrefValue, _ timestamp: PrefValue?) -> SoftwareUpdatePrefs {
            var error: [String: PrefValue] = ["count": count]
            if let timestamp { error["timestamp"] = timestamp }
            return SoftwareUpdatePrefs(readable: true, values: [SoftwareUpdatePrefs.ddmErrorKey: .dictionary(error)])
        }
        XCTAssertEqual(MacPreferenceParsers.updateStuck(ddm(.integer(2), .date(now)), now: now).status, .pass)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(ddm(.integer(3), .date(now)), now: now).status, .fail)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(ddm(.string("4"), .string("2026-10-21T00:00:00.000Z")), now: now).status, .fail)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(ddm(.integer(3), nil), now: now).status, .unknown)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(ddm(.integer(3), .string("last tuesday")), now: now).status, .unknown)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(ddm(.bool(true), .date(now)), now: now).status, .unknown)
        // Count below threshold needs no timestamp.
        XCTAssertEqual(MacPreferenceParsers.updateStuck(ddm(.integer(1), nil), now: now).status, .pass)
    }

    func testCleanMac() throws {
        let clean = try prefs("softwareupdate_clean")
        XCTAssertEqual(MacPreferenceParsers.autoUpdates(clean).status, .pass)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(clean, now: MacFixtures.captureDate).status, .pass)
        XCTAssertEqual(MacPreferenceParsers.betaCatalog(clean).status, .pass, "no CatalogURL = production")
    }

    func testAutoUpdatesOff() throws {
        let off = try prefs("softwareupdate_autoupdates_off")
        XCTAssertEqual(MacPreferenceParsers.autoUpdates(off).status, .fail, "integer 0 = off")
        XCTAssertEqual(MacPreferenceParsers.updateStuck(off, now: MacFixtures.captureDate).status, .pass, "only 2 failures")
        for key in [SoftwareUpdatePrefs.criticalUpdateInstallKey, SoftwareUpdatePrefs.automaticCheckKey] {
            let one = SoftwareUpdatePrefs(readable: true, values: [key: .bool(false)])
            XCTAssertEqual(MacPreferenceParsers.autoUpdates(one).status, .fail, key)
        }
    }

    func testGarbageValuesAreUnknown() throws {
        let garbage = try prefs("softwareupdate_garbage_values")
        XCTAssertTrue(garbage.readable)
        XCTAssertEqual(MacPreferenceParsers.autoUpdates(garbage).status, .unknown)
        XCTAssertEqual(MacPreferenceParsers.updateStuck(garbage, now: MacFixtures.captureDate).status, .unknown)
        XCTAssertEqual(MacPreferenceParsers.betaCatalog(garbage).status, .unknown)
    }

    func testUnreadableDomainIsNeverMissingKeyEqualsOn() throws {
        let unreadable = [
            SoftwareUpdatePrefs.unreadable,
            SoftwareUpdatePrefs(plistData: nil),
            SoftwareUpdatePrefs(plistData: try MacFixtures.data("garbage", "txt")),
            SoftwareUpdatePrefs(propertyList: [String: Any]()),
            SoftwareUpdatePrefs(propertyList: "not a dictionary"),
        ]
        for prefs in unreadable {
            XCTAssertFalse(prefs.readable)
            for outcome in [
                MacPreferenceParsers.autoUpdates(prefs),
                MacPreferenceParsers.updateStuck(prefs, now: MacFixtures.captureDate),
                MacPreferenceParsers.betaCatalog(prefs),
            ] {
                XCTAssertEqual(outcome.status, .unknown, "\(outcome.checkID)")
                XCTAssertEqual(outcome.note, .dataUnavailable)
            }
        }
    }

    func testPrefsKeepOnlyTheKeysTheChecksRead() throws {
        let bens = try prefs("softwareupdate_bens_mac_2026-10-22")
        XCTAssertEqual(Set(bens.values.keys), Set(SoftwareUpdatePrefs.keys).subtracting([SoftwareUpdatePrefs.automaticCheckKey]))
        XCTAssertNil(bens.values["LastAttemptSystemVersion"], "OS version strings are not kept")
    }

    func testPrefValueConversion() {
        XCTAssertEqual(PrefValue(propertyList: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(PrefValue(propertyList: NSNumber(value: 1)), .integer(1))
        XCTAssertEqual(PrefValue(propertyList: NSNumber(value: 1.5)), .real(1.5))
        XCTAssertEqual(PrefValue(propertyList: "x"), .string("x"))
        XCTAssertEqual(PrefValue(propertyList: Data([1])), .other)
        XCTAssertEqual(PrefValue.integer(1).flag, true)
        XCTAssertEqual(PrefValue.integer(0).flag, false)
        XCTAssertNil(PrefValue.integer(2).flag)
        XCTAssertNil(PrefValue.string("YES").flag)
    }

    // MARK: find_my

    func testFindMy() throws {
        XCTAssertEqual(MacPreferenceParsers.findMy(mobileMeAccountsPlist: try MacFixtures.data("mobileme_findmy_on", "plist")).status, .pass)
        XCTAssertEqual(MacPreferenceParsers.findMy(mobileMeAccountsPlist: try MacFixtures.data("mobileme_findmy_off", "plist")).status, .fail)
        XCTAssertEqual(MacPreferenceParsers.findMy(mobileMeAccountsPlist: try MacFixtures.data("mobileme_signed_out", "plist")).status, .fail)

        let odd = MacPreferenceParsers.findMy(mobileMeAccountsPlist: try MacFixtures.data("mobileme_no_findmy_service", "plist"))
        XCTAssertEqual(odd.status, .unknown, "missing Enabled / missing service is unknown (research gotcha 7)")

        let missing = MacPreferenceParsers.findMy(mobileMeAccountsPlist: nil)
        XCTAssertEqual(missing.status, .unknown)
        XCTAssertEqual(missing.note, .dataUnavailable)

        let garbage = MacPreferenceParsers.findMy(mobileMeAccountsPlist: try MacFixtures.data("garbage", "txt"))
        XCTAssertEqual(garbage.status, .unknown)
        XCTAssertEqual(garbage.note, .unparseable)
    }

    func testFindMyNoAccountsKeyIsUnknown() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Other": 1], format: .xml, options: 0)
        XCTAssertEqual(MacPreferenceParsers.findMy(mobileMeAccountsPlist: data).status, .unknown)
    }

    func testFindMyOutcomeCarriesNothingFromTheFile() throws {
        let outcome = MacPreferenceParsers.findMy(mobileMeAccountsPlist: try MacFixtures.data("mobileme_findmy_on", "plist"))
        // The outcome type has no free-text fields; its description must not contain account data.
        let text = String(describing: outcome)
        XCTAssertFalse(text.contains("example.com"))
        XCTAssertFalse(text.contains("Test Person"))
    }

    // MARK: xprotect_current

    func testXProtectBundleVersionFromInfoPlist() throws {
        XCTAssertEqual(MacPreferenceParsers.bundleShortVersion(infoPlist: try MacFixtures.data("xprotect_bundle_info", "plist")), "5368")
        XCTAssertNil(MacPreferenceParsers.bundleShortVersion(infoPlist: try MacFixtures.data("garbage", "txt")))
        XCTAssertNil(MacPreferenceParsers.bundleShortVersion(infoPlist: nil))
    }

    func testXProtectCurrent() {
        let installed = XProtectInstalledVersions(bundleVersion: "5368", appVersion: "170")
        let current = XProtectFeedVersions(plistConfigData: "5368", payloads: "170")
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installed, feed: current).status, .pass)

        let newerConfig = XProtectFeedVersions(plistConfigData: "5370", payloads: "170")
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installed, feed: newerConfig).status, .fail)

        let newerPayload = XProtectFeedVersions(plistConfigData: "5368", payloads: "171")
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installed, feed: newerPayload).status, .fail)

        let ahead = XProtectFeedVersions(plistConfigData: "5300", payloads: "160")
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installed, feed: ahead).status, .pass)
    }

    func testXProtectNoFalseGreenAcrossSeries() {
        // The spec text compares the bundle (5368 series) with XProtectPayloads (170 series).
        // Comparing across series would always pass; an out-of-date XProtect.app must still fail.
        let installed = XProtectInstalledVersions(bundleVersion: "5368", appVersion: "150")
        let feed = XProtectFeedVersions(plistConfigData: nil, payloads: "170")
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installed, feed: feed).status, .fail)

        let onlyBundle = XProtectInstalledVersions(bundleVersion: "5368", appVersion: nil)
        let unknown = MacPreferenceParsers.xprotect(installed: onlyBundle, feed: feed)
        XCTAssertEqual(unknown.status, .unknown, "no comparable pair")
    }

    func testXProtectUnknowns() {
        let installed = XProtectInstalledVersions(bundleVersion: "5368", appVersion: "170")
        let noFeed = MacPreferenceParsers.xprotect(installed: installed, feed: nil)
        XCTAssertEqual(noFeed.status, .unknown)
        XCTAssertEqual(noFeed.note, .noFeed)
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: installed, feed: XProtectFeedVersions(plistConfigData: nil, payloads: nil)).note, .noFeed)
        let nothingInstalled = XProtectInstalledVersions(bundleVersion: nil, appVersion: nil)
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: nothingInstalled, feed: XProtectFeedVersions(plistConfigData: "1", payloads: "1")).note, .dataUnavailable)
        let garbage = XProtectInstalledVersions(bundleVersion: "53a8", appVersion: nil)
        XCTAssertEqual(MacPreferenceParsers.xprotect(installed: garbage, feed: XProtectFeedVersions(plistConfigData: "5368", payloads: nil)).status, .unknown)
    }

    func testXProtectFeedFromSOFAObjects() {
        let feed = XProtectFeedVersions(
            sofaXProtectPayloads: ["com.apple.XProtectFramework.XProtect": "170", "com.apple.XprotectFramework.PluginService": "74", "ReleaseDate": "2026-10-21T00:00:00Z"],
            sofaXProtectPlistConfigData: ["com.apple.XProtect": NSNumber(value: 5368), "ReleaseDate": "2026-10-21T00:00:00Z"]
        )
        XCTAssertEqual(feed, XProtectFeedVersions(plistConfigData: "5368", payloads: "170"))
        XCTAssertNil(XProtectFeedVersions(sofaXProtectPayloads: nil, sofaXProtectPlistConfigData: ["ReleaseDate": "x"]))
    }

    func testCompareVersions() {
        XCTAssertEqual(MacPreferenceParsers.compareVersions("26.5.1", "26.7.1"), .orderedAscending)
        XCTAssertEqual(MacPreferenceParsers.compareVersions("26.7.1", "26.7.1"), .orderedSame)
        XCTAssertEqual(MacPreferenceParsers.compareVersions("26.7", "26.7.0"), .orderedSame)
        XCTAssertEqual(MacPreferenceParsers.compareVersions("26.10", "26.9"), .orderedDescending)
        XCTAssertEqual(MacPreferenceParsers.compareVersions("5368", "170"), .orderedDescending)
        XCTAssertNil(MacPreferenceParsers.compareVersions("26.x", "26.1"))
        XCTAssertNil(MacPreferenceParsers.compareVersions("", "1"))
        XCTAssertNil(MacPreferenceParsers.compareVersions("1..2", "1"))
        XCTAssertNil(MacPreferenceParsers.compareVersions("-1", "1"))
    }
}

final class MacDerivedParserTests: XCTestCase {
    let allClosed: [UInt16: PortProbeResult] = [22: .closed, 5900: .closed, 445: .closed, 548: .closed]

    func testRemoteAccess() {
        XCTAssertEqual(MacDerivedParsers.remoteAccess(allClosed, screenSharingExploitUnpatched: false).status, .pass)

        for port in MacDerivedParsers.remoteAccessPorts {
            var probes = allClosed
            probes[port] = .open
            let outcome = MacDerivedParsers.remoteAccess(probes, screenSharingExploitUnpatched: false)
            XCTAssertEqual(outcome.status, .fail, "port \(port)")
            XCTAssertEqual(outcome.tierOverride, .yellow, "port \(port)")
        }
    }

    func testRemoteAccessRedOnlyForScreenSharingWithExploit() {
        var screenSharing = allClosed
        screenSharing[5900] = .open
        XCTAssertEqual(MacDerivedParsers.remoteAccess(screenSharing, screenSharingExploitUnpatched: true).tierOverride, .red)
        var ssh = allClosed
        ssh[22] = .open
        XCTAssertEqual(MacDerivedParsers.remoteAccess(ssh, screenSharingExploitUnpatched: true).tierOverride, .yellow)
    }

    func testRemoteAccessIndeterminateIsUnknown() {
        var probes = allClosed
        probes[445] = .indeterminate
        XCTAssertEqual(MacDerivedParsers.remoteAccess(probes, screenSharingExploitUnpatched: false).status, .unknown)
        probes[445] = nil
        XCTAssertEqual(MacDerivedParsers.remoteAccess(probes, screenSharingExploitUnpatched: false).status, .unknown)
        XCTAssertEqual(MacDerivedParsers.remoteAccess([:], screenSharingExploitUnpatched: false).status, .unknown)
        // An open port still fails even if another probe was indeterminate.
        probes[22] = .open
        XCTAssertEqual(MacDerivedParsers.remoteAccess(probes, screenSharingExploitUnpatched: false).status, .fail)
    }

    func testPortsMatchSpec() {
        XCTAssertEqual(MacDerivedParsers.remoteAccessPorts, [22, 5900, 445, 548])
    }

    func testOSPatchedTiers() {
        let exploited = MacVersionAssessment(osPatched: .fail, activelyExploited: true, deviceSupported: .pass)
        XCTAssertEqual(MacDerivedParsers.osPatched(exploited).tierOverride, .red)
        let plain = MacVersionAssessment(osPatched: .fail, activelyExploited: false, deviceSupported: .pass)
        XCTAssertEqual(MacDerivedParsers.osPatched(plain).tierOverride, .amber)
        let ok = MacVersionAssessment(osPatched: .pass, activelyExploited: true, deviceSupported: .pass)
        XCTAssertEqual(MacDerivedParsers.osPatched(ok).status, .pass)
        XCTAssertNil(MacDerivedParsers.osPatched(ok).tierOverride)
        XCTAssertFalse(ok.activelyExploited, "exploited only means something on a fail")
        XCTAssertEqual(MacDerivedParsers.osPatched(nil).status, .unknown)
        XCTAssertEqual(MacDerivedParsers.osPatched(MacVersionAssessment(osPatched: .unknown, activelyExploited: false, deviceSupported: .unknown)).note, .noFeed)
    }

    func testDeviceSupported() {
        XCTAssertEqual(MacDerivedParsers.deviceSupported(MacVersionAssessment(osPatched: .pass, activelyExploited: false, deviceSupported: .fail)).status, .fail)
        let aging = MacDerivedParsers.deviceSupported(MacVersionAssessment(osPatched: .pass, activelyExploited: false, deviceSupported: .pass, agingDevice: true))
        XCTAssertEqual(aging.status, .pass)
        XCTAssertEqual(aging.note, .agingDevice)
        XCTAssertEqual(MacDerivedParsers.deviceSupported(nil).status, .unknown)
    }

    func testScreenSharingExploitFlag() {
        let exposed = MacVersionAssessment(osPatched: .fail, activelyExploited: true, unpatchedExploitedCVEs: ["CVE-2026-65400"], deviceSupported: .pass)
        XCTAssertTrue(exposed.screenSharingExploitUnpatched)
        let other = MacVersionAssessment(osPatched: .fail, activelyExploited: true, unpatchedExploitedCVEs: ["CVE-2026-86950"], deviceSupported: .pass)
        XCTAssertFalse(other.screenSharingExploitUnpatched)
    }

    // MARK: Interim bundled assessor (§5.2 step 5, feed never fetched)

    func identity(_ major: Int, _ minor: Int, _ patch: Int) -> MacDeviceIdentity {
        MacDeviceIdentity(osMajor: major, osMinor: minor, osPatch: patch, boardID: "J704AP", modelID: "Mac17,2")
    }

    func testBundledAssessorBensMacIsExploitedFail() {
        let a = BundledMacVersionAssessor.assessment(for: identity(26, 5, 1))
        XCTAssertEqual(a.osPatched, .fail)
        XCTAssertTrue(a.activelyExploited)
        XCTAssertEqual(MacDerivedParsers.osPatched(a).tierOverride, .red)
        XCTAssertEqual(a.deviceSupported, .pass)
        XCTAssertNil(a.xprotectFeed)
    }

    func testBundledAssessorNeverPassesOSPatched() {
        for (major, minor, patch) in [(27, 0, 1), (26, 7, 1), (26, 7, 2), (15, 8, 1), (14, 8, 9)] {
            let a = BundledMacVersionAssessor.assessment(for: identity(major, minor, patch))
            XCTAssertEqual(a.osPatched, .unknown, "\(major).\(minor).\(patch): no feed → unknown (H7)")
            XCTAssertEqual(a.deviceSupported, .pass)
        }
    }

    func testBundledAssessorBelowMinimums() {
        let sequoia = BundledMacVersionAssessor.assessment(for: identity(15, 7, 3))
        XCTAssertEqual(sequoia.osPatched, .fail)
        XCTAssertTrue(sequoia.activelyExploited)
        let sonoma = BundledMacVersionAssessor.assessment(for: identity(14, 8, 8))
        XCTAssertEqual(sonoma.osPatched, .fail)
        XCTAssertFalse(sonoma.activelyExploited, "no bundled exploited entry for 14")
        let golden = BundledMacVersionAssessor.assessment(for: identity(27, 0, 0))
        XCTAssertEqual(golden.osPatched, .fail)
        XCTAssertFalse(golden.activelyExploited)
    }

    func testBundledAssessorUnsupportedAndFutureMajors() {
        let ventura = BundledMacVersionAssessor.assessment(for: identity(13, 7, 8))
        XCTAssertEqual(ventura.osPatched, .fail)
        XCTAssertEqual(ventura.deviceSupported, .unknown, "hardware might still upgrade; needs the feed")
        let future = BundledMacVersionAssessor.assessment(for: identity(28, 0, 0))
        XCTAssertEqual(future.osPatched, .unknown)
        XCTAssertEqual(future.deviceSupported, .unknown)
    }
}
