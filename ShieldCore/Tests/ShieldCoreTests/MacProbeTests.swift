// BoundedProcess (ProcessRunner engine) and LoopbackProber. macOS host only.
// These start only harmless binaries (/bin/echo, /bin/sleep, /usr/bin/head, /bin/ls) through the
// internal test entry point, and listen only on 127.0.0.1.
// The live check of the real allowlisted tools runs only with FS_LIVE_MAC_TOOLS=1.

#if os(macOS)
import XCTest
import Network
@testable import ShieldCore

final class MacToolAllowlistTests: XCTestCase {
    func testEveryToolIsAbsoluteAndAllowlisted() {
        for tool in MacTool.allCases {
            XCTAssertTrue(tool.executablePath.hasPrefix("/"), "\(tool)")
            XCTAssertTrue(tool.isAllowlisted, "\(tool)")
            XCTAssertFalse(tool.arguments.isEmpty, "\(tool)")
        }
        XCTAssertEqual(Set(MacTool.allCases.map(\.executablePath)), MacTool.allowedExecutables)
    }

    func testAllowlistMatchesSpec12_5() {
        let names = Set(MacTool.allowedExecutables.map { ($0 as NSString).lastPathComponent })
        XCTAssertEqual(names, ["fdesetup", "spctl", "csrutil", "sysadminctl", "socketfilterfw", "profiles", "tmutil", "defaults"])
    }

    func testNoShellNoSudoNoSfltool() {
        let forbidden = ["sh", "bash", "zsh", "sudo", "sfltool", "osascript", "systemsetup", "env"]
        for path in MacTool.allowedExecutables {
            XCTAssertFalse(forbidden.contains((path as NSString).lastPathComponent), path)
        }
        for tool in MacTool.allCases {
            XCTAssertFalse(tool.arguments.contains { $0.contains(";") || $0.contains("|") || $0.contains("$") }, "\(tool)")
        }
    }

    func testFixedArguments() {
        XCTAssertEqual(MacTool.fdesetupIsActive.arguments, ["isactive"])
        XCTAssertEqual(MacTool.spctlStatus.arguments, ["--status"])
        XCTAssertEqual(MacTool.csrutilStatus.arguments, ["status"])
        XCTAssertEqual(MacTool.sysadminctlScreenLock.arguments, ["-screenLock", "status"])
        XCTAssertEqual(MacTool.firewallGlobalState.arguments, ["--getglobalstate"])
        XCTAssertEqual(MacTool.profilesEnrollment.arguments, ["status", "-type", "enrollment"])
        XCTAssertEqual(MacTool.tmutilDestinationInfo.arguments, ["destinationinfo"])
        XCTAssertEqual(MacTool.defaultsReadCatalogURL.arguments, ["read", "/Library/Preferences/com.apple.SoftwareUpdate", "CatalogURL"])
    }
}

final class BoundedProcessTests: XCTestCase {
    func testDefaultsMatchSpec() {
        XCTAssertEqual(BoundedProcess.defaultTimeout, 10)
        XCTAssertEqual(BoundedProcess.defaultOutputCap, 65_536)
    }

    func testCapturesStdoutAndExitStatus() async {
        let output = await BoundedProcess().run(executablePath: "/bin/echo", arguments: ["hello", "world"])
        XCTAssertEqual(output.termination, .exited(0))
        XCTAssertEqual(output.stdout, "hello world\n")
        XCTAssertEqual(output.stderr, "")
        XCTAssertFalse(output.truncated)
    }

    func testCapturesStderrAndNonZeroExit() async {
        let output = await BoundedProcess().run(executablePath: "/bin/ls", arguments: ["/nonexistent-family-shield-path"])
        XCTAssertNotEqual(output.exitCode, 0)
        XCTAssertNotNil(output.exitCode)
        XCTAssertTrue(output.stderr.contains("nonexistent-family-shield-path"))
        XCTAssertEqual(output.stdout, "")
    }

    func testArgumentsAreNotInterpretedByAShell() async {
        let output = await BoundedProcess().run(executablePath: "/bin/echo", arguments: ["$HOME;", "`id`", "|", "*"])
        XCTAssertEqual(output.stdout, "$HOME; `id` | *\n")
    }

    func testFixedEnvironment() {
        let env = BoundedProcess.childEnvironment
        XCTAssertEqual(Set(env.keys), ["PATH", "HOME", "LANG", "LC_ALL"])
        XCTAssertFalse(env.keys.contains { $0.hasPrefix("DYLD_") })
    }

    func testTimeoutKillsTheChild() async {
        let start = Date()
        let output = await BoundedProcess(timeout: 0.5, outputCap: 1024).run(executablePath: "/bin/sleep", arguments: ["30"])
        XCTAssertEqual(output.termination, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "timeout must not wait for the child")
        XCTAssertEqual(MacToolParsers.fileVault(output).status, .unknown)
    }

    func testOutputIsCappedAndDrained() async {
        // 300 KB of output: the cap keeps 64 KB, the rest is drained so the child still exits.
        let output = await BoundedProcess().run(executablePath: "/usr/bin/head", arguments: ["-c", "300000", "/dev/zero"])
        XCTAssertEqual(output.termination, .exited(0))
        XCTAssertEqual(output.stdout.utf8.count, BoundedProcess.defaultOutputCap)
        XCTAssertTrue(output.stdoutTruncated)
        XCTAssertFalse(output.stderrTruncated)
    }

    func testSmallCap() async {
        let output = await BoundedProcess(timeout: 5, outputCap: 4).run(executablePath: "/bin/echo", arguments: ["abcdefgh"])
        XCTAssertEqual(output.stdout, "abcd")
        XCTAssertTrue(output.stdoutTruncated)
    }

    func testMissingExecutableIsLaunchFailure() async {
        let output = await BoundedProcess().run(executablePath: "/usr/bin/no-such-family-shield-tool", arguments: [])
        XCTAssertEqual(output.termination, .launchFailed)
    }

    func testRelativePathIsRefused() async {
        let output = await BoundedProcess().run(executablePath: "echo", arguments: ["x"])
        XCTAssertEqual(output.termination, .notAllowed)
    }

    func testStreamCollector() {
        let collector = StreamCollector(cap: 5)
        collector.append(Data("abc".utf8))
        collector.append(Data("defg".utf8))
        collector.append(Data("h".utf8))
        let snapshot = collector.snapshot()
        XCTAssertEqual(String(decoding: snapshot.data, as: UTF8.self), "abcde")
        XCTAssertTrue(snapshot.truncated)
        collector.finish()
        collector.finish()   // idempotent
        collector.waitForEOF(timeout: 0.1)
    }

    /// Runs each real allowlisted, read-only tool once and checks that it ends quickly and
    /// parses to something. Opt-in: set FS_LIVE_MAC_TOOLS=1. Prints only check IDs and statuses.
    func testLiveAllowlistedToolsOptIn() async throws {
        guard ProcessInfo.processInfo.environment["FS_LIVE_MAC_TOOLS"] == "1" else {
            throw XCTSkip("set FS_LIVE_MAC_TOOLS=1 to run the real read-only tools")
        }
        let runner = BoundedProcess()
        for tool in MacTool.allCases {
            let start = Date()
            let output = await runner.run(tool)
            XCTAssertNotEqual(output.termination, .timedOut, "\(tool)")
            XCTAssertNotEqual(output.termination, .launchFailed, "\(tool)")
            XCTAssertLessThan(Date().timeIntervalSince(start), 10, "\(tool)")
            let outcome: MacCheckOutcome = switch tool {
            case .fdesetupIsActive: MacToolParsers.fileVault(output)
            case .spctlStatus: MacToolParsers.gatekeeper(output)
            case .csrutilStatus: MacToolParsers.sip(output)
            case .sysadminctlScreenLock: MacToolParsers.screenLock(output)
            case .firewallGlobalState: MacToolParsers.firewall(output)
            case .profilesEnrollment: MacToolParsers.mdmEnrollment(output)
            case .tmutilDestinationInfo: MacToolParsers.timeMachine(output)
            case .defaultsReadCatalogURL: MacToolParsers.betaCatalog(defaultsOutput: output)
            }
            XCTAssertEqual(outcome.note, .measured, "\(tool) did not parse cleanly (\(output.termination.logName))")
            print("live \(outcome.checkID.rawValue) -> \(outcome.status)")
        }
    }
}

final class LoopbackProberTests: XCTestCase {
    func testTimeoutMatchesSpec() {
        XCTAssertEqual(LoopbackProber.perPortTimeout, 0.3, accuracy: 0.0001)
    }

    func testClosedPortIsClosed() async {
        // Port 1 (tcpmux) has no listener on macOS; loopback refuses at once.
        let result = await LoopbackProber.probe(port: 1, timeout: 2)
        XCTAssertEqual(result, .closed)
    }

    func testPortZeroIsIndeterminate() async {
        let result = await LoopbackProber.probe(port: 0, timeout: 0.3)
        XCTAssertEqual(result, .indeterminate)
    }

    func testOpenPortIsOpen() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in connection.cancel() }
        let queue = DispatchQueue(label: "test.listener")
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port?.rawValue)
        defer { listener.cancel() }

        let result = await LoopbackProber.probe(port: port, timeout: 2)
        XCTAssertEqual(result, .open)
    }

    func testProbeRemoteAccessPortsCoversAllFourQuickly() async {
        let start = Date()
        let results = await LoopbackProber().probeRemoteAccessPorts()
        XCTAssertEqual(Set(results.keys), Set(MacDerivedParsers.remoteAccessPorts))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "probes run concurrently with 300 ms timeouts")
    }
}
#endif
