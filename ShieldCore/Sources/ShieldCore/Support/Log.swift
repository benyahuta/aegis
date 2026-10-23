// SHARED CONTRACT (scaffold). Every builder depends on this file.
// Logging rules (SPEC §5.6, §12.7):
//   - Use only these loggers. No print(), NSLog, analytics, crash SDKs or remote logging.
//   - Every interpolation is `privacy: .private`, EXCEPT enum raw values (CheckID, Status,
//     Tier, RuleID, event names), which may be `privacy: .public`.
//   - NEVER log message text, OCR text, labels, record contents, URLs from user input,
//     or tool (child-process) output.
//
// Example:
//   Log.feed.notice("feed.rejected major=\(major, privacy: .private)")
//   Log.checks.info("check \(id.rawValue, privacy: .public) -> \(status.rawValue, privacy: .public)")

import Foundation
import os

public enum Log {
    /// The os.Logger subsystem for every Family Shield log line.
    public static let subsystem = AppIdentity.prefix

    /// App lifecycle, launch options, environment wiring.
    public static let app = Logger(subsystem: subsystem, category: "app")
    /// CheckCatalog / catalog.json loading.
    public static let catalog = Logger(subsystem: subsystem, category: "catalog")
    /// VersionEvaluator decisions.
    public static let version = Logger(subsystem: subsystem, category: "version")
    /// FeedStore fetch / cache / raise-only (e.g. the `feed.rejected` event).
    public static let feed = Logger(subsystem: subsystem, category: "feed")
    /// Scam rules and OCR. Never log the input text or OCR output.
    public static let scam = Logger(subsystem: subsystem, category: "scam")
    /// ResultSink / CloudKit / SyncQueue. Never log record contents.
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    /// StatusEngine, pacing, self-reports.
    public static let status = Logger(subsystem: subsystem, category: "status")
    /// Local notifications.
    public static let notify = Logger(subsystem: subsystem, category: "notify")
    /// Device checks (iOSChecks, MacChecks, ProcessRunner). Never log tool output.
    public static let checks = Logger(subsystem: subsystem, category: "checks")
    /// UI events.
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// A logger for a category not listed above.
    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
