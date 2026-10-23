// What one allowlisted child process produced (SPEC §6.2: stdout and stderr, each capped at 64 KB).
// Tool output is local data: it is parsed into pass/fail/unknown and then dropped. Never log it,
// never sync it (H5, §5.6).

import Foundation

public struct ToolOutput: Sendable, Hashable {
    /// How the process ended.
    public enum Termination: Sendable, Hashable {
        /// Exited normally with this status.
        case exited(Int32)
        /// Killed by this signal (not by our timeout).
        case signaled(Int32)
        /// Still running at the 10 s limit, so it was killed.
        case timedOut
        /// The executable could not be started.
        case launchFailed
        /// The invocation was refused before launch (not allowlisted / not absolute).
        case notAllowed

        /// A stable name for logs (`privacy: .public` is fine: it carries no tool output).
        public var logName: String {
            switch self {
            case .exited(let code): "exit_\(code)"
            case .signaled(let signal): "signal_\(signal)"
            case .timedOut: "timeout"
            case .launchFailed: "launch_failed"
            case .notAllowed: "not_allowed"
            }
        }
    }

    public var termination: Termination
    public var stdout: String
    public var stderr: String
    /// True when stdout passed the cap and the rest was discarded.
    public var stdoutTruncated: Bool
    /// True when stderr passed the cap and the rest was discarded.
    public var stderrTruncated: Bool

    public init(
        termination: Termination,
        stdout: String = "",
        stderr: String = "",
        stdoutTruncated: Bool = false,
        stderrTruncated: Bool = false
    ) {
        self.termination = termination
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
    }

    /// Convenience for a normal exit (used heavily by tests and fixtures).
    public static func exited(_ code: Int32, stdout: String = "", stderr: String = "") -> ToolOutput {
        ToolOutput(termination: .exited(code), stdout: stdout, stderr: stderr)
    }

    /// The exit status, or nil when the process did not exit normally.
    public var exitCode: Int32? {
        if case .exited(let code) = termination { return code }
        return nil
    }

    /// True when either stream was cut at the cap.
    public var truncated: Bool { stdoutTruncated || stderrTruncated }
}
