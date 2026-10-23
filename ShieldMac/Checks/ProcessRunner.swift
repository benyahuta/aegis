// The only way the Mac app starts a child process (SPEC §6.2, §12.5).
//
// It accepts a `MacTool` and nothing else: an absolute path on the allowlist (fdesetup, spctl,
// csrutil, sysadminctl, socketfilterfw, profiles, tmutil, defaults) with a fixed argument array.
// No shell, 10 s timeout, stdout + stderr each capped at 64 KB. The engine (`BoundedProcess`)
// lives in ShieldCore so `swift test` covers the timeout, cap and stream capture.
// Never runs sudo or sfltool, never asks for admin. Tool output is never logged (§5.6).

import Foundation
import ShieldCore

struct ProcessRunner: ToolRunning {
    private let engine = BoundedProcess()

    func run(_ tool: MacTool) async -> ToolOutput {
        let output = await engine.run(tool)
        Log.checks.info("tool \(tool.rawValue, privacy: .public) end=\(output.termination.logName, privacy: .private) truncated=\(output.truncated, privacy: .private)")
        return output
    }
}
