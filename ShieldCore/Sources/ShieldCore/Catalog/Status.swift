// SHARED CONTRACT (scaffold). Every builder depends on this file.
// `Status` and `Source` are wire formats (SPEC §5.1, §8.2). Never renumber.

import Foundation

/// The result of one check. The raw value is the wire value (CloudKit `status`, Int64).
///
/// H7 "No false green": errors, timeouts, missing data and stale data map to `.unknown`,
/// never to `.pass`. A self-report of "Not sure" is kept locally as its own answer and
/// written as `.unknown`.
public enum Status: Int, CaseIterable, Codable, Sendable, Hashable {
    case unknown = 0
    case pass = 1
    case fail = 2
}

extension Status {
    /// Decodes a wire value. Anything outside {0, 1, 2} is rejected (nil), never coerced to pass.
    public init?(wireValue: Int64) {
        guard let value = Int(exactly: wireValue), let status = Status(rawValue: value) else { return nil }
        self = status
    }

    /// The Int64 written to CloudKit.
    public var wireValue: Int64 { Int64(rawValue) }

    /// Severity for "worst status" roll-ups: fail > unknown > pass.
    public var severity: Int {
        switch self {
        case .pass: 0
        case .unknown: 1
        case .fail: 2
        }
    }

    /// The worst status in a collection (fail > unknown > pass). An empty collection is `.unknown`
    /// (no data is never green, H7).
    public static func worst<S: Sequence>(of statuses: S) -> Status where S.Element == Status {
        var result: Status?
        for status in statuses where status.severity > (result?.severity ?? -1) {
            result = status
        }
        return result ?? .unknown
    }
}

/// Where a result came from. The raw value is the wire value (CloudKit `source`, Int64).
public enum Source: Int, CaseIterable, Codable, Sendable, Hashable {
    /// Measured by the app on the device ("measured" badge).
    case measured = 0
    /// Answered by the person ("confirmed by you" badge).
    case selfReported = 1
}

extension Source {
    public init?(wireValue: Int64) {
        guard let value = Int(exactly: wireValue), let source = Source(rawValue: value) else { return nil }
        self = source
    }

    public var wireValue: Int64 { Int64(rawValue) }
}
