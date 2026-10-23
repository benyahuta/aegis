// CKRecord mapping for the whole CloudKit schema (SPEC §8.2). This file is the only place that
// knows record types and field names. `RecordsTests` asserts every field name and type (§12.1).
//
// Shared record types (person zones / z_self): `Device`, `CheckResult`. They carry only the
// §8.2 fields, never a label, name, OS version, model or free text (H5).
// Ben-only record types (z_admin, never shared): `PersonLabel`, `DeviceLabel`.

import CloudKit
import Foundation

/// The CloudKit schema: record types, field keys, zone names and the encode/decode rules.
public enum Records {

    // MARK: Record types

    public enum RecordType {
        public static let device = "Device"
        public static let checkResult = "CheckResult"
        public static let personLabel = "PersonLabel"
        public static let deviceLabel = "DeviceLabel"
    }

    // MARK: Field keys (§8.2)

    public enum DeviceField {
        public static let platform = "platform"
        public static let enrolledOn = "enrolledOn"
        public static let catalogVersion = "catalogVersion"
        public static let appBuild = "appBuild"
        public static let lastReport = "lastReport"
        public static let all: Set<String> = [platform, enrolledOn, catalogVersion, appBuild, lastReport]
    }

    public enum CheckResultField {
        public static let deviceID = "deviceID"
        public static let checkID = "checkID"
        public static let status = "status"
        public static let source = "source"
        public static let checkedOn = "checkedOn"
        public static let catalogVersion = "catalogVersion"
        public static let all: Set<String> = [deviceID, checkID, status, source, checkedOn, catalogVersion]
    }

    public enum PersonLabelField {
        public static let label = "label"
        public static let createdOn = "createdOn"
        public static let all: Set<String> = [label, createdOn]
    }

    public enum DeviceLabelField {
        public static let label = "label"
        public static let firstCreatorRecordName = "firstCreatorRecordName"
        public static let all: Set<String> = [label, firstCreatorRecordName]
    }

    // MARK: Zones (§8.1)

    /// Ben-only zone. Never shared. Its existence turns owner mode on.
    public static let adminZoneName = "z_admin"
    /// Ben's own devices write here. Never shared.
    public static let selfZoneName = "z_self"
    /// Person zones: `z_` + 16 lowercase hex characters. No name ever appears in a zone name.
    public static let personZonePattern = "^z_[0-9a-f]{16}$"
    /// The share title Ben's code sets (§8.1). No person's name.
    public static let shareTitle = "Family Shield"
    /// Labels are at most 40 characters (§8.2).
    public static let maxLabelLength = 40
    /// The names `OwnerStore.seedAdminSchema()` uses for its save-then-delete records (Development
    /// only). No real zone or device ever gets them.
    public static let schemaSeedZoneName = "z_0000000000000000"
    public static let schemaSeedDeviceID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    public static func isPersonZoneName(_ name: String) -> Bool {
        name.range(of: personZonePattern, options: .regularExpression) != nil
    }

    /// A zone that holds `Device` / `CheckResult` records: a person zone or `z_self`.
    public static func isStatusZoneName(_ name: String) -> Bool {
        name == selfZoneName || isPersonZoneName(name)
    }

    /// `z_` + 16 random lowercase hex characters.
    public static func makePersonZoneName<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let value = generator.next() as UInt64
        let hex = String(value, radix: 16)
        return "z_" + String(repeating: "0", count: 16 - hex.count) + hex
    }

    public static func makePersonZoneName() -> String {
        var generator = SystemRandomNumberGenerator()
        return makePersonZoneName(using: &generator)
    }

    // MARK: Record names

    /// `Device` / `DeviceLabel` record name: the lowercase UUID.
    public static func deviceRecordName(_ deviceID: UUID) -> String {
        deviceID.uuidString.lowercased()
    }

    /// Parses a lowercase device record name. Uppercase or malformed names are rejected.
    public static func deviceID(fromRecordName name: String) -> UUID? {
        guard name.count == 36, name == name.lowercased(), let uuid = UUID(uuidString: name),
              uuid.uuidString.lowercased() == name
        else { return nil }
        return uuid
    }

    /// Splits `<deviceUUID>_<checkID>` into its parts. Nil unless the name matches the §8.3
    /// pattern, the UUID parses and the check ID is allowlisted.
    public static func parseCheckResultRecordName(_ name: String) -> (deviceID: UUID, checkID: CheckID)? {
        guard CheckResult.isValidRecordName(name) else { return nil }
        let uuidPart = String(name.prefix(36))
        let checkPart = String(name.dropFirst(37))
        guard let deviceID = deviceID(fromRecordName: uuidPart),
              let checkID = CheckID.allowlisted(checkPart)
        else { return nil }
        return (deviceID, checkID)
    }

    // MARK: Labels

    /// Trims whitespace, removes control characters and caps at 40 characters.
    /// Returns nil when nothing is left.
    public static func sanitizeLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maxLabelLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Encode: Device

    /// A `Device` record with exactly the five §8.2 fields. Dates are written at 00:00 UTC.
    public static func record(for device: DeviceInfo, in zoneID: CKRecordZone.ID) -> CKRecord {
        let id = CKRecord.ID(recordName: device.recordName, zoneID: zoneID)
        let record = CKRecord(recordType: RecordType.device, recordID: id)
        apply(device, to: record)
        return record
    }

    /// Writes the five §8.2 `Device` fields onto `record` (used for "overwrite with ours").
    public static func apply(_ device: DeviceInfo, to record: CKRecord) {
        record[DeviceField.platform] = device.platform.wireValue as NSNumber
        record[DeviceField.enrolledOn] = device.enrolledOn.date as NSDate
        record[DeviceField.catalogVersion] = Int64(device.catalogVersion) as NSNumber
        record[DeviceField.appBuild] = Int64(device.appBuild) as NSNumber
        record[DeviceField.lastReport] = device.lastReport.date as NSDate
    }

    // MARK: Encode: CheckResult

    /// A `CheckResult` record with exactly the six §8.2 fields. Throws `.invalidRecordName`
    /// if the name fails the §8.3 pattern. `checkedOn` is written at 00:00 UTC.
    public static func record(for result: CheckResult, in zoneID: CKRecordZone.ID) throws(ResultSinkError) -> CKRecord {
        let name = result.recordName
        guard CheckResult.isValidRecordName(name),
              CheckID.allowlisted(result.checkID.rawValue) == result.checkID
        else { throw .invalidRecordName }
        let record = CKRecord(recordType: RecordType.checkResult,
                              recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        apply(result, to: record)
        return record
    }

    /// Writes the six §8.2 `CheckResult` fields onto `record`.
    public static func apply(_ result: CheckResult, to record: CKRecord) {
        record[CheckResultField.deviceID] = deviceRecordName(result.deviceID) as NSString
        record[CheckResultField.checkID] = result.checkID.rawValue as NSString
        record[CheckResultField.status] = result.status.wireValue as NSNumber
        record[CheckResultField.source] = result.source.wireValue as NSNumber
        record[CheckResultField.checkedOn] = result.checkedOn.date as NSDate
        record[CheckResultField.catalogVersion] = Int64(result.catalogVersion) as NSNumber
    }

    // MARK: Encode: labels (z_admin only)

    public static func record(for label: PersonLabel, in adminZoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: RecordType.personLabel,
                              recordID: CKRecord.ID(recordName: label.zoneName, zoneID: adminZoneID))
        record[PersonLabelField.label] = label.label as NSString
        record[PersonLabelField.createdOn] = label.createdOn as NSDate
        return record
    }

    public static func record(for label: DeviceLabel, in adminZoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: RecordType.deviceLabel,
                              recordID: CKRecord.ID(recordName: deviceRecordName(label.deviceID), zoneID: adminZoneID))
        record[DeviceLabelField.label] = label.label as NSString
        record[DeviceLabelField.firstCreatorRecordName] = label.firstCreatorRecordName as NSString
        return record
    }

    /// Copies the allowlisted fields of `ours` onto `server` (the server's copy, which carries the
    /// change tag), so a save overwrites the server with our values (§8.4 `.serverRecordChanged`).
    public static func overwrite(_ server: CKRecord, with ours: CKRecord) -> CKRecord {
        let keys: Set<String>
        switch ours.recordType {
        case RecordType.device: keys = DeviceField.all
        case RecordType.checkResult: keys = CheckResultField.all
        case RecordType.personLabel: keys = PersonLabelField.all
        case RecordType.deviceLabel: keys = DeviceLabelField.all
        default: keys = []
        }
        for key in keys {
            server[key] = ours[key]
        }
        return server
    }

    // MARK: Decode (strict: anything off-schema is dropped, which shows as grey, H7)

    /// Decodes a `Device` record. Nil for a wrong type, a bad record name, or a missing or
    /// mistyped field.
    public static func deviceInfo(from record: CKRecord) -> DeviceInfo? {
        guard record.recordType == RecordType.device,
              let deviceID = deviceID(fromRecordName: record.recordID.recordName),
              let platformValue = int64(record[DeviceField.platform]),
              let platform = Platform(wireValue: platformValue),
              let enrolledOn = date(record[DeviceField.enrolledOn]),
              let catalogVersion = int(record[DeviceField.catalogVersion]),
              let appBuild = int(record[DeviceField.appBuild]),
              let lastReport = date(record[DeviceField.lastReport])
        else { return nil }
        return DeviceInfo(deviceID: deviceID, platform: platform, enrolledOn: DateDay(enrolledOn),
                          catalogVersion: catalogVersion, appBuild: appBuild, lastReport: DateDay(lastReport))
    }

    /// Decodes a `CheckResult` record. Nil unless the record name matches §8.3, the check ID
    /// is allowlisted, the fields agree with the record name, and status/source are in range.
    /// `checkedOn` is truncated to its UTC day.
    public static func checkResult(from record: CKRecord) -> CheckResult? {
        guard record.recordType == RecordType.checkResult,
              let parsed = parseCheckResultRecordName(record.recordID.recordName),
              let deviceString = record[CheckResultField.deviceID] as? String,
              deviceID(fromRecordName: deviceString) == parsed.deviceID,
              let checkString = record[CheckResultField.checkID] as? String,
              let checkID = CheckID.allowlisted(checkString), checkID == parsed.checkID,
              let statusValue = int64(record[CheckResultField.status]),
              let status = Status(wireValue: statusValue),
              let sourceValue = int64(record[CheckResultField.source]),
              let source = Source(wireValue: sourceValue),
              let checkedOn = date(record[CheckResultField.checkedOn]),
              let catalogVersion = int(record[CheckResultField.catalogVersion])
        else { return nil }
        return CheckResult(deviceID: parsed.deviceID, checkID: checkID, status: status, source: source,
                           checkedOn: DateDay(checkedOn), catalogVersion: catalogVersion)
    }

    public static func personLabel(from record: CKRecord) -> PersonLabel? {
        guard record.recordType == RecordType.personLabel,
              isPersonZoneName(record.recordID.recordName),
              let label = record[PersonLabelField.label] as? String,
              let createdOn = date(record[PersonLabelField.createdOn])
        else { return nil }
        return PersonLabel(zoneName: record.recordID.recordName,
                           label: String(label.prefix(maxLabelLength)), createdOn: createdOn)
    }

    public static func deviceLabel(from record: CKRecord) -> DeviceLabel? {
        guard record.recordType == RecordType.deviceLabel,
              let deviceID = deviceID(fromRecordName: record.recordID.recordName),
              let label = record[DeviceLabelField.label] as? String,
              let creator = record[DeviceLabelField.firstCreatorRecordName] as? String
        else { return nil }
        return DeviceLabel(deviceID: deviceID, label: String(label.prefix(maxLabelLength)),
                           firstCreatorRecordName: creator)
    }

    // MARK: Field helpers

    private static func int64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else { return nil }
        // Reject non-integral numbers (a Double field would be off-schema).
        let int = number.int64Value
        guard NSNumber(value: int) == number else { return nil }
        return int
    }

    private static func int(_ value: Any?) -> Int? {
        int64(value).flatMap { Int(exactly: $0) }
    }

    private static func date(_ value: Any?) -> Date? {
        value as? Date
    }
}

// MARK: - Ben-only label models (z_admin)

/// `PersonLabel` (§8.2): Ben's name for a person zone. Lives only in `z_admin`.
public struct PersonLabel: Hashable, Codable, Sendable {
    /// The person zone's name (`z_<16 hex>`); also the record name.
    public var zoneName: String
    /// At most 40 characters.
    public var label: String
    public var createdOn: Date

    public init(zoneName: String, label: String, createdOn: Date) {
        self.zoneName = zoneName
        self.label = label
        self.createdOn = createdOn
    }
}

/// `DeviceLabel` (§8.2): Ben's name for a device plus the creator seen at enrollment.
public struct DeviceLabel: Hashable, Codable, Sendable {
    public var deviceID: UUID
    /// At most 40 characters. Empty until Ben names the device.
    public var label: String
    /// The `creatorUserRecordID.recordName` seen when Ben's app first saw this device.
    public var firstCreatorRecordName: String

    public init(deviceID: UUID, label: String, firstCreatorRecordName: String) {
        self.deviceID = deviceID
        self.label = label
        self.firstCreatorRecordName = firstCreatorRecordName
    }
}
