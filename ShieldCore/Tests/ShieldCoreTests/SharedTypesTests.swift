import XCTest
@testable import ShieldCore

final class CheckIDTests: XCTestCase {
    /// Every ID in SPEC §6.1–§6.4, verbatim.
    static let specIDs: Set<String> = [
        // §6.1
        "os_patched", "device_supported", "passcode_set", "biometrics_enrolled", "app_build_fresh",
        // §6.2
        "os_update_stuck", "beta_catalog", "auto_updates", "filevault", "gatekeeper", "sip",
        "xprotect_current", "screen_lock", "find_my", "firewall", "remote_access_off", "mdm_unexpected",
        "time_machine", "persistence_new_item", "chrome_ext_forced", "lockdown", "adp",
        // §6.3
        "stolen_device_protection", "recovery_contact", "screen_unknown", "family_code_word",
        "carrier_lock", "credit_freeze_equifax", "credit_freeze_experian", "credit_freeze_transunion",
        "passwords_alerts_clear", "fraud_website_warning", "safety_check_quarterly", "advanced_data_protection",
        // §6.4
        "accounts_email", "accounts_money", "accounts_social", "accounts_shopping",
        "accounts_government", "accounts_health",
    ]

    func testEnumMatchesSpecExactly() {
        XCTAssertEqual(Set(CheckID.allCases.map(\.rawValue)), Self.specIDs)
        XCTAssertEqual(CheckID.allCases.count, Self.specIDs.count, "duplicate raw values")
    }

    func testRawValuesMatchWirePattern() {
        for id in CheckID.allCases {
            XCTAssertNotNil(id.rawValue.range(of: CheckID.wirePattern, options: .regularExpression), id.rawValue)
        }
    }

    func testAllowlist() {
        XCTAssertEqual(CheckID.allowlisted("filevault"), .filevault)
        XCTAssertNil(CheckID.allowlisted("feed_fresh"))
        XCTAssertNil(CheckID.allowlisted("FILEVAULT"))
        XCTAssertNil(CheckID.allowlisted("gmail"))
        XCTAssertNil(CheckID.allowlisted(""))
    }

    func testRollups() {
        XCTAssertEqual(CheckID.accountRollups.map(\.rawValue), [
            "accounts_email", "accounts_money", "accounts_social",
            "accounts_shopping", "accounts_government", "accounts_health",
        ])
        XCTAssertTrue(CheckID.accountsHealth.isAccountRollup)
        XCTAssertFalse(CheckID.osPatched.isAccountRollup)
        XCTAssertEqual(CheckID.allCases.filter(\.isAccountRollup).count, 6)
    }

    func testLocalInfoIDsAreNeverAllowlisted() {
        for id in LocalInfoID.allCases {
            XCTAssertNil(CheckID(rawValue: id.rawValue), id.rawValue)
        }
    }

    func testCodableUsesWireValue() throws {
        let data = try JSONEncoder().encode([CheckID.remoteAccessOff])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["remote_access_off"]"#)
        XCTAssertThrowsError(try JSONDecoder().decode([CheckID].self, from: Data(#"["nope"]"#.utf8)))
    }
}

final class StatusSourceTierPlatformTests: XCTestCase {
    func testWireValues() {
        XCTAssertEqual(Status.unknown.rawValue, 0)
        XCTAssertEqual(Status.pass.rawValue, 1)
        XCTAssertEqual(Status.fail.rawValue, 2)
        XCTAssertEqual(Source.measured.rawValue, 0)
        XCTAssertEqual(Source.selfReported.rawValue, 1)
        XCTAssertEqual(Platform.ios.rawValue, 0)
        XCTAssertEqual(Platform.mac.rawValue, 1)
        XCTAssertEqual(Status.fail.wireValue, Int64(2))
    }

    func testInvalidWireValuesAreRejectedNotCoerced() {
        XCTAssertNil(Status(wireValue: 3))
        XCTAssertNil(Status(wireValue: -1))
        XCTAssertNil(Source(wireValue: 2))
        XCTAssertNil(Platform(wireValue: 2))
        XCTAssertEqual(Status(wireValue: 1), .pass)
    }

    func testWorstStatus() {
        XCTAssertEqual(Status.worst(of: [.pass, .unknown, .pass]), .unknown)
        XCTAssertEqual(Status.worst(of: [.pass, .fail, .unknown]), .fail)
        XCTAssertEqual(Status.worst(of: [.pass]), .pass)
        XCTAssertEqual(Status.worst(of: []), .unknown, "no data is never green (H7)")
    }

    func testTierOrdering() {
        XCTAssertEqual([Tier.info, .red, .yellow, .amber].max(), .red)
        XCTAssertTrue(Tier.amber > .yellow)
        XCTAssertEqual(Tier(rawValue: "amber"), .amber)
    }

    func testPlatformCurrent() {
        #if os(macOS)
        XCTAssertEqual(Platform.current, .mac)
        #else
        XCTAssertEqual(Platform.current, .ios)
        #endif
    }

    func testVerdictMax() {
        XCTAssertEqual(max(Verdict.noCommonSignsFound, .beCareful), .beCareful)
        XCTAssertEqual([Verdict.beCareful, .danger, .noCommonSignsFound].max(), .danger)
        XCTAssertEqual(Verdict.allCases.count, 3, "there is never a 'safe' verdict")
    }
}

final class DateDayTests: XCTestCase {
    func testTruncatesToUTCDay() throws {
        // 2026-10-22T23:59:59Z
        let late = Date(timeIntervalSince1970: 1_792_713_599)
        let day = DateDay(late)
        XCTAssertEqual(day.iso8601, "2026-10-22")
        XCTAssertEqual(day.date.timeIntervalSince1970, 1_792_627_200)
        XCTAssertEqual(late.truncatedToUTCDay, day.date)
        XCTAssertEqual(DateDay(late.addingTimeInterval(1)).iso8601, "2026-10-23")
    }

    func testBeforeEpochFloors() {
        XCTAssertEqual(DateDay(Date(timeIntervalSince1970: -1)).iso8601, "1969-12-31")
        XCTAssertEqual(DateDay(Date(timeIntervalSince1970: 0)).daysSinceEpoch, 0)
    }

    func testComponentsAndParsing() throws {
        let day = try XCTUnwrap(DateDay(year: 2026, month: 10, day: 22))
        XCTAssertEqual(DateDay(iso8601: "2026-10-22"), day)
        XCTAssertNil(DateDay(year: 2026, month: 2, day: 30))
        XCTAssertNil(DateDay(iso8601: "2026-10-22T00:00:00Z"))
        XCTAssertNil(DateDay(iso8601: "26-10-22"))
        XCTAssertEqual(day.adding(days: 90).iso8601, "2027-01-20")
        XCTAssertEqual(day.adding(days: 90).days(since: day), 90)
        XCTAssertTrue(day < day.adding(days: 1))
    }

    func testCodableIsDayString() throws {
        let day = try XCTUnwrap(DateDay(year: 2026, month: 1, day: 5))
        let data = try JSONEncoder().encode([day])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["2026-01-05"]"#)
        XCTAssertEqual(try JSONDecoder().decode([DateDay].self, from: data), [day])
    }

    func testClocks() throws {
        let start = try XCTUnwrap(DateDay(year: 2026, month: 10, day: 22))
        let test = TestClock(day: start)
        let clock = test.clock
        XCTAssertEqual(clock.today(), start)
        test.advance(days: 3)
        XCTAssertEqual(clock.today(), start.adding(days: 3))
        XCTAssertEqual(DateDay.today(clock), start.adding(days: 3))
        let fixed = Clock.fixed(start.date)
        XCTAssertEqual(fixed.now(), start.date)
        XCTAssertLessThan(abs(Clock.system.now().timeIntervalSinceNow), 5)
    }
}

final class RecordShapeTests: XCTestCase {
    let deviceID = UUID(uuidString: "0F8E5B1C-2D3A-4B5C-8D9E-0A1B2C3D4E5F")!

    func testRecordNameIsLowercaseUnderscoreAndValid() {
        let result = CheckResult(deviceID: deviceID, checkID: .osPatched, status: .fail,
                                 source: .measured, checkedAt: Date(), catalogVersion: 1)
        XCTAssertEqual(result.recordName, "0f8e5b1c-2d3a-4b5c-8d9e-0a1b2c3d4e5f_os_patched")
        XCTAssertTrue(CheckResult.isValidRecordName(result.recordName))
        for id in CheckID.allCases {
            XCTAssertTrue(CheckResult.isValidRecordName(CheckResult.recordName(deviceID: deviceID, checkID: id)))
        }
    }

    func testRecordNamePatternRejectsBadNames() {
        XCTAssertFalse(CheckResult.isValidRecordName("0F8E5B1C-2D3A-4B5C-8D9E-0A1B2C3D4E5F_os_patched"))
        XCTAssertFalse(CheckResult.isValidRecordName("0f8e5b1c-2d3a-4b5c-8d9e-0a1b2c3d4e5f/os_patched"))
        XCTAssertFalse(CheckResult.isValidRecordName("0f8e5b1c-2d3a-4b5c-8d9e-0a1b2c3d4e5f_"))
        XCTAssertFalse(CheckResult.isValidRecordName("abc_os_patched"))
    }

    func testCheckedAtIsTruncated() {
        let result = CheckResult(deviceID: deviceID, checkID: .sip, status: .pass, source: .measured,
                                 checkedAt: Date(timeIntervalSince1970: 1_792_700_000), catalogVersion: 1)
        XCTAssertEqual(result.checkedOn.date.timeIntervalSince1970, 1_792_627_200)
    }

    /// The payload shapes carry exactly the §8.2 fields (H5, §12.1).
    func testPayloadKeysAreExactlySpecFields() throws {
        let day = DateDay(daysSinceEpoch: 20_748)
        let result = CheckResult(deviceID: deviceID, checkID: .sip, status: .pass, source: .measured,
                                 checkedOn: day, catalogVersion: 1)
        let device = DeviceInfo(deviceID: deviceID, platform: .mac, enrolledOn: day, catalogVersion: 1,
                                appBuild: 7, lastReport: day)
        func keys(_ value: some Encodable) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            return Set((object as? [String: Any] ?? [:]).keys)
        }
        XCTAssertEqual(try keys(result), ["deviceID", "checkID", "status", "source", "checkedOn", "catalogVersion"])
        XCTAssertEqual(try keys(device), ["deviceID", "platform", "enrolledOn", "catalogVersion", "appBuild", "lastReport"])
        XCTAssertEqual(device.recordName, "0f8e5b1c-2d3a-4b5c-8d9e-0a1b2c3d4e5f")
    }
}

final class InMemoryResultSinkTests: XCTestCase {
    let deviceID = UUID()
    var device: DeviceInfo {
        DeviceInfo(deviceID: deviceID, platform: .ios, enrolledOn: DateDay(daysSinceEpoch: 1),
                   catalogVersion: 1, appBuild: 1, lastReport: DateDay(daysSinceEpoch: 2))
    }

    func result(_ id: CheckID, _ status: Status, device: UUID? = nil) -> CheckResult {
        CheckResult(deviceID: device ?? deviceID, checkID: id, status: status, source: .measured,
                    checkedOn: DateDay(daysSinceEpoch: 2), catalogVersion: 1)
    }

    func testUpsertMergesLastStateWins() async throws {
        let sink = InMemoryResultSink()
        try await sink.upsert(device: device, results: [result(.osPatched, .fail), result(.passcodeSet, .pass)])
        try await sink.upsert(device: device, results: [result(.osPatched, .pass)])
        let stored = await sink.results(for: deviceID)
        XCTAssertEqual(stored.map(\.checkID), [.osPatched, .passcodeSet])
        XCTAssertEqual(stored.first?.status, .pass)
        let count = await sink.upsertCount
        XCTAssertEqual(count, 2)
    }

    func testRejectsForeignDeviceResults() async {
        let sink = InMemoryResultSink()
        do {
            try await sink.upsert(device: device, results: [result(.sip, .pass, device: UUID())])
            XCTFail("expected deviceMismatch")
        } catch {
            XCTAssertEqual(error as? ResultSinkError, .deviceMismatch)
        }
        let devices = await sink.devices
        XCTAssertTrue(devices.isEmpty, "nothing is written when validation fails")
    }

    func testLeaveClearsEverything() async throws {
        let sink = InMemoryResultSink()
        try await sink.upsert(device: device, results: [result(.sip, .pass)])
        try await sink.leave()
        let devices = await sink.devices
        let results = await sink.results(for: deviceID)
        XCTAssertTrue(devices.isEmpty)
        XCTAssertTrue(results.isEmpty)
    }

    func testInjectedFailureThrowsOnce() async throws {
        let sink = InMemoryResultSink()
        await sink.failNext(with: .unavailable)
        do {
            try await sink.upsert(device: device, results: [])
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? ResultSinkError, .unavailable)
        }
        try await sink.upsert(device: device, results: [])
    }

    func testUsableAsExistential() async throws {
        let sink: any ResultSink = InMemoryResultSink()
        try await sink.upsert(device: device, results: [result(.findMy, .unknown)])
        try await sink.leave()
    }
}

final class LaunchOptionsTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(LaunchOptions(arguments: ["app"]), LaunchOptions(noCloud: false, demoState: nil))
        XCTAssertTrue(LaunchOptions(arguments: ["app", "-FSNoCloud"]).noCloud)
        XCTAssertTrue(LaunchOptions(arguments: ["app", "-FSNoCloud", "YES"]).noCloud)
        XCTAssertFalse(LaunchOptions(arguments: ["app", "-FSNoCloud", "NO"]).noCloud)
        let demo = LaunchOptions(arguments: ["app", "-FSDemoState", "homeProtected", "-FSNoCloud"])
        XCTAssertEqual(demo.demoState, "homeProtected")
        XCTAssertTrue(demo.noCloud)
    }

    func testDemoStateImpliesNoCloud() {
        let options = LaunchOptions(arguments: ["app", "-FSDemoState", "resultDanger"])
        XCTAssertEqual(options.demoState, "resultDanger")
        XCTAssertTrue(options.noCloud)
    }

    func testMissingDemoNameIsIgnored() {
        XCTAssertNil(LaunchOptions(arguments: ["app", "-FSDemoState"]).demoState)
        XCTAssertNil(LaunchOptions(arguments: ["app", "-FSDemoState", "-FSNoCloud"]).demoState)
        XCTAssertTrue(LaunchOptions(arguments: ["app", "-FSDemoState", "-FSNoCloud"]).noCloud)
    }
}

final class DeepLinkTests: XCTestCase {
    func testOnlyAllowedSchemes() {
        for link in DeepLink.allCases {
            switch link.platform {
            case .ios:
                // Either the app's own Settings page (resolved in UIKit) or the bare Settings
                // home screen. Never a private pane path.
                if link == .iosSettingsHome {
                    XCTAssertEqual(link.urlString, "App-prefs:")
                } else {
                    XCTAssertNil(link.urlString, "iOS app settings resolve through UIKit")
                }
            case .mac:
                let string = link.urlString ?? ""
                XCTAssertTrue(string.hasPrefix("x-apple.systempreferences:com.apple."), string)
                XCTAssertNotNil(link.url)
                XCTAssertFalse(string.lowercased().contains("app-prefs"))
            }
        }
    }
}
