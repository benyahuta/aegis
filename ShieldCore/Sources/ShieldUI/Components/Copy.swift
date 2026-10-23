// Every family-visible word comes from ShieldCore's String Catalog (§11 "Localizable strings in
// .xcstrings"; H6). `L` is the only way screens read copy. ShieldUITests scans these call sites and
// fails if a key is missing from the catalog.
//
// The catalog lint allows no "%" except %lld, so values with a runtime part use `{token}`
// placeholders filled by `L.fill`.

import Foundation
import SwiftUI
import ShieldCore

public enum L {
    /// Plain text for `key`.
    public static func t(_ key: String) -> String { ShieldStrings.text(key) }

    /// Text with `**bold**` / `*italic*` Markdown rendered.
    public static func a(_ key: String) -> AttributedString { ShieldStrings.attributed(key) }

    /// Text without Markdown markers (VoiceOver labels, share text).
    public static func plain(_ key: String) -> String { ShieldStrings.plain(key) }

    /// A plural string (`%lld`).
    public static func plural(_ key: String, _ count: Int) -> String { ShieldStrings.plural(key, count: count) }

    /// Replaces `{name}` placeholders.
    public static func fill(_ key: String, _ values: [String: String]) -> String {
        var text = ShieldStrings.text(key)
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }

    /// The platform-specific key: `<base>.ios` / `<base>.mac`.
    public static func platformKey(_ base: String, _ platform: Platform) -> String {
        base + (platform == .ios ? ".ios" : ".mac")
    }

    /// The reason text for a scam rule, from the catalog (falls back to the compiled English).
    public static func reason(_ rule: RuleID) -> String {
        ShieldStrings.contains(rule.reasonKey) ? ShieldStrings.text(rule.reasonKey) : rule.reasonText
    }

    public static func reason(_ reason: CallQuiz.Reason) -> String {
        ShieldStrings.contains(reason.reasonKey) ? ShieldStrings.text(reason.reasonKey) : reason.text
    }

    public static func label(_ caller: CallQuiz.Caller) -> String {
        let key = "scam.call.caller.\(caller.rawValue)"
        return ShieldStrings.contains(key) ? ShieldStrings.text(key) : caller.label
    }

    public static func label(_ want: CallQuiz.Want) -> String {
        let key = "scam.call.want.\(want.rawValue)"
        return ShieldStrings.contains(key) ? ShieldStrings.text(key) : want.label
    }

    /// The §10 status word for VoiceOver and Ben's ✓/✗/? lists.
    public static func statusWord(_ status: Status) -> String {
        switch status {
        case .pass: t("a11y.status.done")
        case .fail: t("a11y.status.notDone")
        case .unknown: t("a11y.status.unknown")
        }
    }

    /// "Measured" / "Confirmed by you".
    public static func badge(_ source: Source) -> String {
        source == .measured ? t("badge.measured") : t("badge.confirmedByYou")
    }
}

/// Short time and date formatting for "Checked today at 9:14 AM."
public enum ShieldDates {
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    public static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// A UTC day shown as a date ("Oct 22, 2026").
    public static func day(_ day: DateDay) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .current
        return day.date.formatted(style)
    }

    /// "Checked today at 9:14 AM." / "Checked Oct 20, 2026." / "Checking now."
    public static func checkedLine(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return L.t("home.notCheckedYet") }
        if calendar.isDate(date, inSameDayAs: now) {
            return L.fill("home.checkedToday", ["time": time(date)])
        }
        return L.fill("home.checkedOn", ["date": day(date)])
    }
}
