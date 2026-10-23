// SHARED CONTRACT (scaffold). Every builder depends on this file.
// One synced check result: exactly the §8.2 `CheckResult` record fields, nothing else (H5, §12.1).
// Do NOT add fields. OS versions, models, names, paths, text and verdicts never go here.

import Foundation

public struct CheckResult: Hashable, Codable, Sendable {
    /// The reporting device's random UUID (§8.2 `deviceID`).
    public var deviceID: UUID
    /// Allowlisted check ID (§8.2 `checkID`). Typed, so an unknown ID cannot be represented.
    public var checkID: CheckID
    /// 0 unknown / 1 pass / 2 fail.
    public var status: Status
    /// 0 measured / 1 self-reported.
    public var source: Source
    /// Day precision, written as 00:00 UTC (§8.3).
    public var checkedOn: DateDay
    /// `CheckCatalog` version that produced this result.
    public var catalogVersion: Int

    public init(
        deviceID: UUID,
        checkID: CheckID,
        status: Status,
        source: Source,
        checkedOn: DateDay,
        catalogVersion: Int
    ) {
        self.deviceID = deviceID
        self.checkID = checkID
        self.status = status
        self.source = source
        self.checkedOn = checkedOn
        self.catalogVersion = catalogVersion
    }

    /// Convenience: truncates `checkedAt` to its UTC day.
    public init(
        deviceID: UUID,
        checkID: CheckID,
        status: Status,
        source: Source,
        checkedAt: Date,
        catalogVersion: Int
    ) {
        self.init(deviceID: deviceID, checkID: checkID, status: status, source: source,
                  checkedOn: DateDay(checkedAt), catalogVersion: catalogVersion)
    }

    /// CloudKit recordName: `<deviceUUID>_<checkID>` (lowercase UUID, underscore, §8.2).
    public var recordName: String {
        CheckResult.recordName(deviceID: deviceID, checkID: checkID)
    }

    public static func recordName(deviceID: UUID, checkID: CheckID) -> String {
        "\(deviceID.uuidString.lowercased())_\(checkID.rawValue)"
    }

    /// §8.3 record-name rule.
    public static let recordNamePattern = "^[0-9a-f-]{36}_[a-z0-9_]{1,48}$"

    /// True when `name` matches `^[0-9a-f-]{36}_[a-z0-9_]{1,48}$`.
    public static func isValidRecordName(_ name: String) -> Bool {
        name.range(of: recordNamePattern, options: .regularExpression) != nil
    }
}
