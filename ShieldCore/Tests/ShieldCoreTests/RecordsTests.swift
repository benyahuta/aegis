import CloudKit
import XCTest
@testable import ShieldCore

/// SPEC §13.1 `RecordsTests` + §12.1: record name regex, allowlist, exact payload keys and
/// types, day truncation.
final class RecordsTests: XCTestCase {
    let deviceID = UUID(uuidString: "6F1C2B3A-4D5E-4F60-8A7B-9C0D1E2F3A4B")!
    let zoneID = CKRecordZone.ID(zoneName: "z_0123456789abcdef", ownerName: "_ben")

    func makeResult(_ check: CheckID = .filevault, status: Status = .pass, source: Source = .measured,
                    day: DateDay = DateDay(year: 2026, month: 10, day: 22)!) -> CheckResult {
        CheckResult(deviceID: deviceID, checkID: check, status: status, source: source, checkedOn: day, catalogVersion: 3)
    }

    func makeDevice(platform: Platform = .mac) -> DeviceInfo {
        DeviceInfo(deviceID: deviceID, platform: platform, enrolledOn: DateDay(year: 2026, month: 10, day: 1)!,
                   catalogVersion: 3, appBuild: 42, lastReport: DateDay(year: 2026, month: 10, day: 22)!)
    }

    // MARK: Record names

    func testRecordNameRegexAcceptsEveryAllowlistedID() {
        for check in CheckID.allCases {
            let name = CheckResult.recordName(deviceID: deviceID, checkID: check)
            XCTAssertTrue(CheckResult.isValidRecordName(name), name)
            XCTAssertTrue(name.hasPrefix("6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b_"), "lowercase UUID + underscore")
            let parsed = Records.parseCheckResultRecordName(name)
            XCTAssertEqual(parsed?.deviceID, deviceID)
            XCTAssertEqual(parsed?.checkID, check)
        }
    }

    func testRecordNameRegexRejectsBadNames() {
        let uuid = deviceID.uuidString.lowercased()
        let bad = [
            "\(deviceID.uuidString)_filevault",       // uppercase UUID
            "\(uuid)/filevault",                      // slash, not underscore
            "\(uuid)_FileVault",                      // uppercase check ID
            "\(uuid)_",                               // empty check ID
            "\(uuid)_" + String(repeating: "a", count: 49), // > 48
            "\(uuid)_file vault",
            "\(uuid)_filevault\n",
            "x\(uuid)_filevault",
            "",
        ]
        for name in bad {
            XCTAssertFalse(CheckResult.isValidRecordName(name), name)
            XCTAssertNil(Records.parseCheckResultRecordName(name), name)
        }
        // Matches the regex but the suffix is not allowlisted.
        let unknown = "\(uuid)_gmail"
        XCTAssertTrue(CheckResult.isValidRecordName(unknown))
        XCTAssertNil(Records.parseCheckResultRecordName(unknown))
        // Matches the regex but the UUID part is not a UUID.
        XCTAssertNil(Records.parseCheckResultRecordName(String(repeating: "-", count: 36) + "_filevault"))
    }

    func testDeviceRecordNameIsLowercaseUUID() {
        XCTAssertEqual(Records.deviceRecordName(deviceID), "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b")
        XCTAssertEqual(Records.deviceID(fromRecordName: "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b"), deviceID)
        XCTAssertNil(Records.deviceID(fromRecordName: deviceID.uuidString), "uppercase rejected")
        XCTAssertNil(Records.deviceID(fromRecordName: "not-a-uuid"))
    }

    // MARK: Payload: exactly the §8.2 keys and types

    func testDevicePayloadHasExactlyTheAllowedKeysAndTypes() {
        let record = Records.record(for: makeDevice(), in: zoneID)
        XCTAssertEqual(record.recordType, "Device")
        XCTAssertEqual(record.recordID.recordName, "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b")
        XCTAssertEqual(record.recordID.zoneID, zoneID)
        XCTAssertEqual(Set(record.allKeys()), ["platform", "enrolledOn", "catalogVersion", "appBuild", "lastReport"])
        XCTAssertEqual(Set(record.allKeys()), Records.DeviceField.all)
        assertInt64(record["platform"], 1)
        assertInt64(record["catalogVersion"], 3)
        assertInt64(record["appBuild"], 42)
        assertMidnightUTC(record["enrolledOn"], expected: DateDay(year: 2026, month: 10, day: 1)!)
        assertMidnightUTC(record["lastReport"], expected: DateDay(year: 2026, month: 10, day: 22)!)
        XCTAssertNil(record.parent)
        XCTAssertNil(record.share)
    }

    func testCheckResultPayloadHasExactlyTheAllowedKeysAndTypes() throws {
        let record = try Records.record(for: makeResult(.gatekeeper, status: .fail, source: .selfReported), in: zoneID)
        XCTAssertEqual(record.recordType, "CheckResult")
        XCTAssertEqual(record.recordID.recordName, "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b_gatekeeper")
        XCTAssertEqual(Set(record.allKeys()), ["deviceID", "checkID", "status", "source", "checkedOn", "catalogVersion"])
        XCTAssertEqual(Set(record.allKeys()), Records.CheckResultField.all)
        XCTAssertEqual(record["deviceID"] as? String, "6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b")
        XCTAssertEqual(record["checkID"] as? String, "gatekeeper")
        assertInt64(record["status"], 2)
        assertInt64(record["source"], 1)
        assertInt64(record["catalogVersion"], 3)
        assertMidnightUTC(record["checkedOn"], expected: DateDay(year: 2026, month: 10, day: 22)!)
    }

    func testStatusAndSourceWireValues() throws {
        for status in Status.allCases {
            let record = try Records.record(for: makeResult(status: status), in: zoneID)
            assertInt64(record["status"], Int64(status.rawValue))
            XCTAssertTrue([0, 1, 2].contains((record["status"] as? NSNumber)?.int64Value))
        }
        for source in Source.allCases {
            let record = try Records.record(for: makeResult(source: source), in: zoneID)
            assertInt64(record["source"], Int64(source.rawValue))
        }
    }

    func testNoFreeTextOnSharedRecords() throws {
        // The only String fields on shared types are the device UUID and the allowlisted check ID.
        let record = try Records.record(for: makeResult(), in: zoneID)
        for key in record.allKeys() {
            if let string = record[key] as? String {
                XCTAssertTrue(["deviceID", "checkID"].contains(key), key)
                XCTAssertTrue(string == deviceID.uuidString.lowercased() || CheckID.allowlisted(string) != nil)
            }
        }
        let device = Records.record(for: makeDevice(), in: zoneID)
        XCTAssertFalse(device.allKeys().contains { device[$0] is String }, "Device has no String field")
    }

    func testLabelPayloads() {
        let admin = CKRecordZone.ID(zoneName: "z_admin", ownerName: CKCurrentUserDefaultName)
        let person = Records.record(for: PersonLabel(zoneName: "z_0123456789abcdef", label: "Mom",
                                                     createdOn: Date(timeIntervalSince1970: 1_800_000_000)), in: admin)
        XCTAssertEqual(person.recordType, "PersonLabel")
        XCTAssertEqual(person.recordID.recordName, "z_0123456789abcdef")
        XCTAssertEqual(Set(person.allKeys()), ["label", "createdOn"])
        XCTAssertTrue(person["label"] is String)
        XCTAssertTrue(person["createdOn"] is Date)

        let device = Records.record(for: DeviceLabel(deviceID: deviceID, label: "Mom's iPhone",
                                                     firstCreatorRecordName: "_abc"), in: admin)
        XCTAssertEqual(device.recordType, "DeviceLabel")
        XCTAssertEqual(device.recordID.recordName, deviceID.uuidString.lowercased())
        XCTAssertEqual(Set(device.allKeys()), ["label", "firstCreatorRecordName"])
        XCTAssertEqual(Records.personLabel(from: person)?.label, "Mom")
        XCTAssertEqual(Records.deviceLabel(from: device)?.firstCreatorRecordName, "_abc")
    }

    // MARK: Day truncation

    func testCheckedOnIsTruncatedToTheUTCDay() throws {
        // 2026-10-22 23:59:30 UTC is still the 22nd.
        let late = DateDay(year: 2026, month: 10, day: 22)!.date.addingTimeInterval(86_399.5)
        let result = CheckResult(deviceID: deviceID, checkID: .sip, status: .pass, source: .measured,
                                 checkedAt: late, catalogVersion: 1)
        let record = try Records.record(for: result, in: zoneID)
        assertMidnightUTC(record["checkedOn"], expected: DateDay(year: 2026, month: 10, day: 22)!)
    }

    func testDecodeTruncatesANonMidnightDate() throws {
        let record = try Records.record(for: makeResult(), in: zoneID)
        record["checkedOn"] = DateDay(year: 2026, month: 10, day: 22)!.date.addingTimeInterval(13 * 3600) as NSDate
        XCTAssertEqual(Records.checkResult(from: record)?.checkedOn, DateDay(year: 2026, month: 10, day: 22)!)
    }

    // MARK: Round trip and strict decode

    func testRoundTrip() throws {
        let result = makeResult(.accountsMoney, status: .unknown, source: .selfReported)
        XCTAssertEqual(Records.checkResult(from: try Records.record(for: result, in: zoneID)), result)
        let device = makeDevice(platform: .ios)
        XCTAssertEqual(Records.deviceInfo(from: Records.record(for: device, in: zoneID)), device)
    }

    func testAllowlistRejectsUnknownCheckIDOnDecode() throws {
        let uuid = deviceID.uuidString.lowercased()
        // A record named for an unknown check.
        let unknown = CKRecord(recordType: "CheckResult",
                               recordID: CKRecord.ID(recordName: "\(uuid)_gmail", zoneID: zoneID))
        Records.apply(makeResult(), to: unknown)
        unknown["checkID"] = "gmail" as NSString
        XCTAssertNil(Records.checkResult(from: unknown))

        // A local-only info item can never be decoded either.
        let info = try Records.record(for: makeResult(), in: zoneID)
        info["checkID"] = "feed_fresh" as NSString
        XCTAssertNil(Records.checkResult(from: info))

        // Field and name disagree.
        let mismatch = try Records.record(for: makeResult(.sip), in: zoneID)
        mismatch["checkID"] = "filevault" as NSString
        XCTAssertNil(Records.checkResult(from: mismatch))

        let otherDevice = try Records.record(for: makeResult(), in: zoneID)
        otherDevice["deviceID"] = UUID().uuidString.lowercased() as NSString
        XCTAssertNil(Records.checkResult(from: otherDevice))
    }

    func testDecodeRejectsOutOfRangeAndMistypedValues() throws {
        let base = try Records.record(for: makeResult(), in: zoneID)
        for (key, value) in [("status", 3 as NSNumber), ("status", -1 as NSNumber), ("source", 2 as NSNumber),
                             ("status", 1.5 as NSNumber)] as [(String, NSNumber)] {
            let record = base.copy() as! CKRecord
            record[key] = value
            XCTAssertNil(Records.checkResult(from: record), "\(key)=\(value)")
        }
        let stringStatus = base.copy() as! CKRecord
        stringStatus["status"] = "1" as NSString
        XCTAssertNil(Records.checkResult(from: stringStatus))
        let missing = base.copy() as! CKRecord
        missing["checkedOn"] = nil
        XCTAssertNil(Records.checkResult(from: missing))

        let device = Records.record(for: makeDevice(), in: zoneID)
        device["platform"] = 7 as NSNumber
        XCTAssertNil(Records.deviceInfo(from: device))
    }

    func testEncodeRejectsAnInvalidRecordName() {
        // The typed API cannot express a bad name, so check the guard with a hand-made type
        // mismatch: wrong record type on decode, and validateForSink's device check.
        let device = makeDevice()
        var foreign = makeResult()
        foreign.deviceID = UUID()
        XCTAssertThrowsError(try validateForSink(device: device, results: [foreign])) { error in
            XCTAssertEqual(error as? ResultSinkError, .deviceMismatch)
        }
        let wrongType = CKRecord(recordType: "Device", recordID: CKRecord.ID(recordName: "x", zoneID: zoneID))
        XCTAssertNil(Records.checkResult(from: wrongType))
        XCTAssertNil(Records.deviceInfo(from: wrongType))
    }

    func testOverwriteCopiesOnlyAllowedFields() throws {
        let ours = try Records.record(for: makeResult(status: .fail), in: zoneID)
        let server = try Records.record(for: makeResult(status: .pass), in: zoneID)
        server["extra"] = "should stay untouched" as NSString
        let merged = Records.overwrite(server, with: ours)
        XCTAssertTrue(merged === server)
        assertInt64(merged["status"], 2)
        XCTAssertEqual(merged["extra"] as? String, "should stay untouched")
    }

    // MARK: Zones and labels

    func testZoneNames() {
        var generator = SeededGenerator(seed: 7)
        let name = Records.makePersonZoneName(using: &generator)
        XCTAssertTrue(Records.isPersonZoneName(name), name)
        XCTAssertEqual(name.count, 18)
        for _ in 0..<50 { XCTAssertTrue(Records.isPersonZoneName(Records.makePersonZoneName())) }
        XCTAssertFalse(Records.isPersonZoneName("z_admin"))
        XCTAssertFalse(Records.isPersonZoneName("z_self"))
        XCTAssertFalse(Records.isPersonZoneName("z_Mom"))
        XCTAssertFalse(Records.isPersonZoneName("z_0123456789ABCDEF"))
        XCTAssertTrue(Records.isStatusZoneName("z_self"))
        XCTAssertFalse(Records.isStatusZoneName("z_admin"))
        XCTAssertFalse(Records.isStatusZoneName(CKRecordZone.ID.defaultZoneName))
    }

    func testLabelSanitizing() {
        XCTAssertEqual(Records.sanitizeLabel("  Mom  "), "Mom")
        XCTAssertNil(Records.sanitizeLabel("   "))
        XCTAssertNil(Records.sanitizeLabel(nil))
        XCTAssertEqual(Records.sanitizeLabel("Mom\n\t's\u{0007}"), "Mom's")
        XCTAssertEqual(Records.sanitizeLabel(String(repeating: "x", count: 100))?.count, 40)
    }

    // MARK: Helpers

    private func assertInt64(_ value: Any?, _ expected: Int64, file: StaticString = #filePath, line: UInt = #line) {
        guard let number = value as? NSNumber else {
            return XCTFail("not a number", file: file, line: line)
        }
        XCTAssertEqual(number.int64Value, expected, file: file, line: line)
    }

    private func assertMidnightUTC(_ value: Any?, expected: DateDay, file: StaticString = #filePath, line: UInt = #line) {
        guard let date = value as? Date else {
            return XCTFail("not a date", file: file, line: line)
        }
        XCTAssertEqual(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400), 0, file: file, line: line)
        XCTAssertEqual(DateDay(date), expected, file: file, line: line)
    }
}

/// Deterministic generator for tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
