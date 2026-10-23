// The child-process engine behind ShieldMac's ProcessRunner (SPEC §6.2, §12.5).
//
// - Only `MacTool` cases can be run from outside ShieldCore: absolute allowlisted path, fixed
//   arguments, no shell (Process execs the binary directly).
// - 10 s timeout; then SIGTERM, then SIGKILL.
// - stdout and stderr are both captured and each capped at 64 KB; past the cap the pipe is still
//   drained (so the child never blocks) but the bytes are discarded.
// - stdin is /dev/null; the environment is a fixed minimal one (no inherited DYLD_* etc.).
// It lives in ShieldCore so `swift test` can exercise the timeout and cap.

#if os(macOS)
import Foundation
import Darwin
import os

public struct BoundedProcess: Sendable {
    /// §6.2: 10 s.
    public static let defaultTimeout: TimeInterval = 10
    /// §6.2: 64 KB per stream.
    public static let defaultOutputCap = 64 * 1024
    /// After SIGTERM, how long to wait before SIGKILL.
    static let killGrace: TimeInterval = 1
    /// After exit, how long to wait for the pipes to reach EOF (a grandchild could hold them open).
    static let drainGrace: TimeInterval = 1

    let timeout: TimeInterval
    let outputCap: Int

    public init() {
        self.init(timeout: Self.defaultTimeout, outputCap: Self.defaultOutputCap)
    }

    /// Tests only (shorter timeout / smaller cap).
    init(timeout: TimeInterval, outputCap: Int) {
        self.timeout = timeout
        self.outputCap = outputCap
    }

    /// Runs one allowlisted tool. Never throws; every failure is reflected in `termination`.
    public func run(_ tool: MacTool) async -> ToolOutput {
        guard tool.isAllowlisted else { return ToolOutput(termination: .notAllowed) }
        return await run(executablePath: tool.executablePath, arguments: tool.arguments)
    }

    /// Internal: tests use it with harmless binaries (`/bin/sleep`, `/usr/bin/head`). Not reachable
    /// from the app, which can only pass a `MacTool`.
    func run(executablePath: String, arguments: [String]) async -> ToolOutput {
        let timeout = self.timeout
        let outputCap = self.outputCap
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runBlocking(
                    executablePath: executablePath, arguments: arguments,
                    timeout: timeout, outputCap: outputCap
                ))
            }
        }
    }

    /// The fixed child environment.
    static var childEnvironment: [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "LANG": "C",
            "LC_ALL": "C",
        ]
    }

    static func runBlocking(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        outputCap: Int
    ) -> ToolOutput {
        guard executablePath.hasPrefix("/") else { return ToolOutput(termination: .notAllowed) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = childEnvironment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutCollector = StreamCollector(cap: outputCap)
        let stderrCollector = StreamCollector(cap: outputCap)
        stdoutPipe.fileHandleForReading.readabilityHandler = { stdoutCollector.consume($0) }
        stderrPipe.fileHandleForReading.readabilityHandler = { stderrCollector.consume($0) }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        func detachReaders() {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }

        do {
            try process.run()
        } catch {
            detachReaders()
            return ToolOutput(termination: .launchFailed)
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + killGrace)
            }
        }

        stdoutCollector.waitForEOF(timeout: drainGrace)
        stderrCollector.waitForEOF(timeout: drainGrace)
        detachReaders()

        let termination: ToolOutput.Termination
        if timedOut || process.isRunning {
            termination = .timedOut
        } else {
            switch process.terminationReason {
            case .exit: termination = .exited(process.terminationStatus)
            case .uncaughtSignal: termination = .signaled(process.terminationStatus)
            @unknown default: termination = .signaled(process.terminationStatus)
            }
        }

        let out = stdoutCollector.snapshot()
        let err = stderrCollector.snapshot()
        return ToolOutput(
            termination: termination,
            stdout: String(decoding: out.data, as: UTF8.self),
            stderr: String(decoding: err.data, as: UTF8.self),
            stdoutTruncated: out.truncated,
            stderrTruncated: err.truncated
        )
    }
}

/// Collects one pipe's bytes up to a cap. Thread-safe: the readability handler runs on a
/// Foundation-owned queue.
final class StreamCollector: Sendable {
    private struct State {
        var data = Data()
        var truncated = false
        var finished = false
    }

    private let cap: Int
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let eof = DispatchSemaphore(value: 0)

    init(cap: Int) {
        self.cap = cap
    }

    /// Called from `readabilityHandler`. An empty read is EOF.
    func consume(_ handle: FileHandle) {
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            finish()
        } else {
            append(chunk)
        }
    }

    func append(_ chunk: Data) {
        state.withLock { state in
            let room = cap - state.data.count
            if room <= 0 {
                state.truncated = true
            } else if chunk.count > room {
                state.data.append(chunk.prefix(room))
                state.truncated = true
            } else {
                state.data.append(chunk)
            }
        }
    }

    func finish() {
        let first = state.withLock { state -> Bool in
            defer { state.finished = true }
            return !state.finished
        }
        if first { eof.signal() }
    }

    func waitForEOF(timeout: TimeInterval) {
        let finished = state.withLock { $0.finished }
        if !finished { _ = eof.wait(timeout: .now() + timeout) }
    }

    func snapshot() -> (data: Data, truncated: Bool) {
        state.withLock { ($0.data, $0.truncated) }
    }
}
#endif
