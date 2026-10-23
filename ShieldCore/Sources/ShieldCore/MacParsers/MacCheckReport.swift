// The text printed by the Mac app's hidden `-FSRunChecksAndPrint` smoke run (SPEC §13.3):
// one line per check, `check_id -> status (tier) [note]`, then the menu-bar word.
// It prints only enum raw values (no versions, paths, names or tool output) and goes to the
// terminal that started it; nothing is sent anywhere.

import Foundation

public enum MacCheckReport {
    public static let flag = "-FSRunChecksAndPrint"

    /// The tier a failing check shows: the outcome's override, else the catalog tier.
    /// Passing and unknown checks print their status only.
    public static func tier(_ outcome: MacCheckOutcome, catalog: CheckCatalog) -> Tier? {
        guard outcome.status == .fail else { return nil }
        if let override = outcome.tierOverride { return override }
        return catalog[outcome.checkID]?.tier
    }

    public static func statusWord(_ status: Status) -> String {
        switch status {
        case .pass: "pass"
        case .fail: "fail"
        case .unknown: "unknown"
        }
    }

    public static func line(_ outcome: MacCheckOutcome, catalog: CheckCatalog) -> String {
        var text = "\(outcome.checkID.rawValue) -> \(statusWord(outcome.status))"
        if let tier = tier(outcome, catalog: catalog) { text += " (\(tier.rawValue))" }
        text += " [\(outcome.note.rawValue)]"
        return text
    }

    /// Every line of the report, including the summary.
    public static func lines(_ outcomes: [MacCheckOutcome], catalog: CheckCatalog, menuBarWord: String,
                             elapsed: TimeInterval) -> [String] {
        var lines = ["Family Shield Mac checks (\(outcomes.count))"]
        lines += outcomes.map { line($0, catalog: catalog) }
        lines.append("menubar -> \(menuBarWord)")
        lines.append(String(format: "elapsed -> %.1f s", elapsed))
        return lines
    }
}
