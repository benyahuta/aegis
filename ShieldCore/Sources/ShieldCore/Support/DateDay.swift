// SHARED CONTRACT (scaffold). Every builder depends on this file.
// `DateDay` is a calendar day in UTC. Every synced date is day precision at 00:00 UTC
// (SPEC §8.2 `checkedOn`, `enrolledOn`, `lastReport`; §8.3 "checkedOn truncated to the day").

import Foundation

/// A whole UTC day. Stored as days since 1970-01-01 UTC, so it can never carry a time of day.
public struct DateDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Days since 1970-01-01 (UTC). Negative for earlier days.
    public let daysSinceEpoch: Int

    public init(daysSinceEpoch: Int) {
        self.daysSinceEpoch = daysSinceEpoch
    }

    /// The UTC day that contains `date` (truncates the time of day).
    public init(_ date: Date) {
        let seconds = date.timeIntervalSince1970
        self.daysSinceEpoch = Int((seconds / 86_400).rounded(.down))
    }

    /// A specific day. Returns nil for an invalid date such as 2026-02-30.
    public init?(year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = DateDay.utcCalendar.date(from: components) else { return nil }
        let back = DateDay.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        self.init(date)
    }

    /// Parses "yyyy-MM-dd". Returns nil for anything else.
    public init?(iso8601 string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// 00:00:00 UTC on this day. This is the value written to CloudKit.
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(daysSinceEpoch) * 86_400)
    }

    /// The day `count` days later (or earlier, if negative).
    public func adding(days count: Int) -> DateDay {
        DateDay(daysSinceEpoch: daysSinceEpoch + count)
    }

    /// Whole days from `earlier` to `self` (positive when `self` is later).
    public func days(since earlier: DateDay) -> Int {
        daysSinceEpoch - earlier.daysSinceEpoch
    }

    /// The current UTC day according to `clock`.
    public static func today(_ clock: Clock = .system) -> DateDay {
        DateDay(clock.now())
    }

    /// "yyyy-MM-dd".
    public var iso8601: String {
        let c = DateDay.utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public var description: String { iso8601 }

    public static func < (lhs: DateDay, rhs: DateDay) -> Bool {
        lhs.daysSinceEpoch < rhs.daysSinceEpoch
    }

    /// Gregorian calendar fixed to UTC.
    public static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}

extension DateDay: Codable {
    /// Encoded as "yyyy-MM-dd".
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let day = DateDay(iso8601: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected yyyy-MM-dd")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601)
    }
}

extension Date {
    /// This date truncated to 00:00:00 UTC (§8.3).
    public var truncatedToUTCDay: Date { DateDay(self).date }
}
