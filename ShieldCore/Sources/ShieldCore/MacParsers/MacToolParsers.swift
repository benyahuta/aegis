// Pure parsers: allowlisted tool output → pass / fail / unknown (SPEC §6.2, §13.1 MacCheckParserTests).
//
// Rules shared by every parser (H7 "no false green"):
//   - timeout, launch failure, refusal, signal, truncated output → unknown
//   - an exit status the tool does not document for that answer → unknown
//   - text that matches no known shape → unknown
// Only an exact, known "on" shape is `.pass`. Parsers never log or keep the text.

import Foundation

public enum MacToolParsers {

    // MARK: filevault — /usr/bin/fdesetup isactive

    /// Exit 0 + "true" = on; exit 1 + "false" = off [V].
    public static func fileVault(_ output: ToolOutput) -> MacCheckOutcome {
        let id = CheckID.filevault
        if let note = abnormal(output) { return .unknown(id, note) }
        let answer = firstLine(output.stdout)?.lowercased()
        switch (output.exitCode, answer) {
        case (0, "true"): return .pass(id)
        case (1, "false"): return .fail(id)
        case (0, _), (1, _): return .unknown(id, .unparseable)
        default: return .unknown(id, .toolFailed)
        }
    }

    // MARK: gatekeeper — /usr/sbin/spctl --status

    /// "assessments enabled" (exit 0) = on; "assessments disabled" = off. `spctl` may exit 1 when
    /// assessments are disabled, so the exact "disabled" text is accepted with exit 0 or 1.
    public static func gatekeeper(_ output: ToolOutput) -> MacCheckOutcome {
        let id = CheckID.gatekeeper
        if let note = abnormal(output) { return .unknown(id, note) }
        let lines = normalizedLines(output.stdout)
        let enabled = lines.contains("assessments enabled")
        let disabled = lines.contains("assessments disabled")
        switch output.exitCode {
        case 0 where enabled && !disabled: return .pass(id)
        case 0 where disabled && !enabled, 1 where disabled && !enabled: return .fail(id)
        case 0, 1: return .unknown(id, .unparseable)
        default: return .unknown(id, .toolFailed)
        }
    }

    // MARK: sip — /usr/bin/csrutil status

    /// "System Integrity Protection status: enabled." = on; "disabled." = off. A custom
    /// configuration with any protection listed as disabled is off; one with nothing disabled is
    /// not a state we can vouch for, so it is unknown.
    public static func sip(_ output: ToolOutput) -> MacCheckOutcome {
        let id = CheckID.sip
        if let note = abnormal(output) { return .unknown(id, note) }
        guard output.exitCode == 0 else { return .unknown(id, .toolFailed) }
        let lines = normalizedLines(output.stdout)
        let prefix = "system integrity protection status:"
        guard let statusLine = lines.first(where: { $0.hasPrefix(prefix) }) else {
            return .unknown(id, .unparseable)
        }
        let value = statusLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        // In a custom configuration each protection is listed as "<name>: enabled|disabled".
        // "Apple Internal: disabled" is normal on every customer Mac, so it is ignored.
        let anyProtectionDisabled = lines.contains { line in
            line != statusLine && !line.hasPrefix("apple internal")
                && (line.hasSuffix(": disabled") || line.hasSuffix(": disabled."))
        }
        if value.hasPrefix("disabled") || anyProtectionDisabled { return .fail(id) }
        if value == "enabled." || value == "enabled" { return .pass(id) }
        return .unknown(id, .unparseable)
    }

    // MARK: screen_lock — /usr/sbin/sysadminctl -screenLock status (answer on stderr)

    /// The parsed `sysadminctl -screenLock status` answer.
    public enum ScreenLockSetting: Sendable, Hashable {
        case immediate
        case delay(seconds: Int)
        case off
    }

    /// Finds the screen-lock answer in `text` (the NSLog line on stderr, e.g.
    /// "2026-10-22 21:24:38.219 sysadminctl[7557:19628757] screenLock delay is immediate").
    public static func parseScreenLock(_ text: String) -> ScreenLockSetting? {
        for line in normalizedLines(text) {
            if line.contains("screenlock is off") || line.contains("screenlock is disabled") {
                return .off
            }
            guard let range = line.range(of: "screenlock delay is ") else { continue }
            let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("immediate") { return .immediate }
            let digits = rest.prefix(while: \.isNumber)
            guard !digits.isEmpty, let seconds = Int(digits) else { return nil }
            let unit = rest.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
            if unit.hasPrefix("second") { return .delay(seconds: seconds) }
            if unit.hasPrefix("minute") { return .delay(seconds: seconds * 60) }
            return nil
        }
        return nil
    }

    /// "immediate" or ≤ 5 s → pass [V]; a longer delay or "off" → fail. Reads stderr first
    /// (where the tool writes), then stdout in case a future macOS moves the line.
    public static func screenLock(_ output: ToolOutput) -> MacCheckOutcome {
        let id = CheckID.screenLock
        if let note = abnormal(output) { return .unknown(id, note) }
        guard output.exitCode == 0 else { return .unknown(id, .toolFailed) }
        guard let setting = parseScreenLock(output.stderr) ?? parseScreenLock(output.stdout) else {
            return .unknown(id, .unparseable)
        }
        switch setting {
        case .immediate: return .pass(id)
        case .delay(let seconds): return seconds <= 5 ? .pass(id) : .fail(id)
        case .off: return .fail(id)
        }
    }

    // MARK: firewall — /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

    /// The `(State = N)` value, or nil.
    public static func parseFirewallState(_ text: String) -> Int? {
        for line in normalizedLines(text) {
            guard let range = line.range(of: "(state = ") else { continue }
            let digits = line[range.upperBound...].prefix(while: \.isNumber)
            if let state = Int(digits) { return state }
        }
        return nil
    }

    /// State 1 (on) or 2 (on, blocking all) → pass; 0 → fail. Without a state number, the exact
    /// "Firewall is enabled." / "Firewall is disabled." sentence decides.
    public static func firewall(_ output: ToolOutput) -> MacCheckOutcome {
        let id = CheckID.firewall
        if let note = abnormal(output) { return .unknown(id, note) }
        guard output.exitCode == 0 else { return .unknown(id, .toolFailed) }
        if let state = parseFirewallState(output.stdout) {
            switch state {
            case 0: return .fail(id)
            case 1, 2: return .pass(id)
            default: return .unknown(id, .unparseable)
            }
        }
        let lines = normalizedLines(output.stdout)
        if lines.contains(where: { $0.hasPrefix("firewall is disabled") }) { return .fail(id) }
        if lines.contains(where: { $0.hasPrefix("firewall is enabled") }) { return .pass(id) }
        return .unknown(id, .unparseable)
    }

    // MARK: mdm_unexpected — /usr/bin/profiles status -type enrollment

    /// "MDM enrollment: No" → pass; "MDM enrollment: Yes…" → fail (red), unless Ben marked MDM as
    /// expected on his own Mac (`expectedByOwner`), which turns it into a local pass.
    public static func mdmEnrollment(_ output: ToolOutput, expectedByOwner: Bool = false) -> MacCheckOutcome {
        let id = CheckID.mdmUnexpected
        if let note = abnormal(output) { return .unknown(id, note) }
        guard output.exitCode == 0 else { return .unknown(id, .toolFailed) }
        let prefix = "mdm enrollment:"
        guard let line = normalizedLines(output.stdout).first(where: { $0.hasPrefix(prefix) }) else {
            return .unknown(id, .unparseable)
        }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        if value == "no" { return .pass(id) }
        if value.hasPrefix("yes") {
            return expectedByOwner
                ? MacCheckOutcome(checkID: id, status: .pass, note: .expectedByOwner)
                : .fail(id)
        }
        return .unknown(id, .unparseable)
    }

    // MARK: time_machine (P1) — /usr/bin/tmutil destinationinfo

    /// "No destinations configured." → fail; at least one `ID : …` line → pass.
    public static func timeMachine(_ output: ToolOutput) -> MacCheckOutcome {
        let id = CheckID.timeMachine
        if let note = abnormal(output) { return .unknown(id, note) }
        let lines = normalizedLines(output.stdout + "\n" + output.stderr)
        if lines.contains(where: { $0.contains("no destinations configured") }) { return .fail(id) }
        guard output.exitCode == 0 else { return .unknown(id, .toolFailed) }
        let destinations = lines.filter { line in
            guard let colon = line.firstIndex(of: ":") else { return false }
            return line[..<colon].trimmingCharacters(in: .whitespaces) == "id"
        }
        return destinations.isEmpty ? .unknown(id, .unparseable) : .pass(id)
    }

    // MARK: beta_catalog fallback — /usr/bin/defaults read …SoftwareUpdate CatalogURL

    /// The `defaults read` answer: `.some(url)` when set, `.some(nil)` when the key does not exist,
    /// nil when the output can't be trusted.
    public static func parseDefaultsCatalogURL(_ output: ToolOutput) -> String?? {
        guard abnormal(output) == nil else { return nil }
        switch output.exitCode {
        case 0:
            guard let value = firstLine(output.stdout), !value.isEmpty else { return nil }
            return .some(value)
        case 1 where output.stderr.lowercased().contains("does not exist"):
            return .some(nil)
        default:
            return nil
        }
    }

    /// `beta_catalog` from `defaults read`: a URL containing "seed" or "beta" → fail; missing → pass.
    public static func betaCatalog(defaultsOutput output: ToolOutput) -> MacCheckOutcome {
        let id = CheckID.betaCatalog
        if let note = abnormal(output) { return .unknown(id, note) }
        guard let parsed = parseDefaultsCatalogURL(output) else {
            return .unknown(id, output.exitCode == 0 ? .unparseable : .toolFailed)
        }
        guard let url = parsed else { return .pass(id) }
        return MacPreferenceParsers.isBetaCatalog(url) ? .fail(id) : .pass(id)
    }

    // MARK: Helpers

    /// The note for an output that must not be parsed at all, or nil when it may be parsed.
    static func abnormal(_ output: ToolOutput) -> MacCheckNote? {
        switch output.termination {
        case .timedOut: return .timedOut
        case .launchFailed, .notAllowed, .signaled: return .toolFailed
        case .exited: return output.truncated ? .unparseable : nil
        }
    }

    /// Lowercased, trimmed, non-empty lines.
    static func normalizedLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// The first non-empty trimmed line (case preserved).
    static func firstLine(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
