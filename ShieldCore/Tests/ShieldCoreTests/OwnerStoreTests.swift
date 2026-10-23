import CloudKit
import os
import XCTest
@testable import ShieldCore

final class StalenessRulesTests: XCTestCase {
    let today = DateDay(year: 2026, month: 10, day: 22)!

    func testIPhoneLimits() {
        XCTAssertEqual(StalenessRules.staleness(platform: .ios, lastReport: today, today: today), .fresh)
        XCTAssertEqual(StalenessRules.staleness(platform: .ios, lastReport: today.adding(days: -7), today: today), .fresh)
        XCTAssertEqual(StalenessRules.staleness(platform: .ios, lastReport: today.adding(days: -8), today: today), .notReporting)
        XCTAssertEqual(StalenessRules.staleness(platform: .ios, lastReport: today.adding(days: -14), today: today), .notReporting)
        XCTAssertEqual(StalenessRules.staleness(platform: .ios, lastReport: today.adding(days: -15), today: today), .expired)
    }

    func testMacLimits() {
        XCTAssertEqual(StalenessRules.staleness(platform: .mac, lastReport: today.adding(days: -2), today: today), .fresh)
        XCTAssertEqual(StalenessRules.staleness(platform: .mac, lastReport: today.adding(days: -3), today: today), .notReporting)
        XCTAssertEqual(StalenessRules.staleness(platform: .mac, lastReport: today.adding(days: -15), today: today), .expired)
    }

    func testNoReportAndFutureReport() {
        XCTAssertEqual(StalenessRules.staleness(platform: .mac, lastReport: nil, today: today), .expired)
        XCTAssertEqual(StalenessRules.staleness(platform: .ios, lastReport: today.adding(days: 2), today: today), .fresh)
    }
}

final class DashboardAggregatorTests: XCTestCase {
    let today = DateDay(year: 2026, month: 10, day: 22)!
    let phone = UUID()
    let mac = UUID()

    func info(_ id: UUID, _ platform: Platform, daysAgo: Int) -> DeviceSnapshot {
        DeviceSnapshot(info: DeviceInfo(deviceID: id, platform: platform, enrolledOn: today.adding(days: -30),
                                        catalogVersion: 1, appBuild: 5, lastReport: today.adding(days: -daysAgo)),
                       authorship: RecordAuthorship(creator: "_mom", lastModifier: "_mom"))
    }

    func result(_ id: UUID, _ check: CheckID, _ status: Status, writer: String = "_mom") -> (String, ResultSnapshot) {
        let r = CheckResult(deviceID: id, checkID: check, status: status, source: .measured, checkedOn: today, catalogVersion: 1)
        return (r.recordName, ResultSnapshot(result: r, authorship: RecordAuthorship(creator: writer, lastModifier: writer)))
    }

    func zone(phoneDaysAgo: Int = 0, macDaysAgo: Int = 0, results: [(String, ResultSnapshot)]) -> ZoneSnapshot {
        ZoneSnapshot(zoneName: "z_00000000000000aa",
                     devices: [phone: info(phone, .ios, daysAgo: phoneDaysAgo), mac: info(mac, .mac, daysAgo: macDaysAgo)],
                     results: Dictionary(results, uniquingKeysWith: { $1 }))
    }

    var labels: [UUID: DeviceLabel] {
        [phone: DeviceLabel(deviceID: phone, label: "Mom's iPhone", firstCreatorRecordName: "_mom"),
         mac: DeviceLabel(deviceID: mac, label: "Mom's Mac", firstCreatorRecordName: "_mom")]
    }

    func build(_ zones: [ZoneSnapshot], deviceLabels: [UUID: DeviceLabel]? = nil,
               personLabels: [String: PersonLabel] = [:]) -> FamilyDashboard {
        DashboardAggregator.build(zones: zones, personLabels: personLabels, deviceLabels: deviceLabels ?? labels, today: today)
    }

    func testWorstStatusPerDeviceAndPerson() throws {
        let dashboard = build([zone(results: [
            result(phone, .osPatched, .pass), result(phone, .passcodeSet, .pass),
            result(mac, .filevault, .pass), result(mac, .gatekeeper, .fail),
        ])])
        let person = try XCTUnwrap(dashboard.people.first)
        XCTAssertEqual(person.devices.map(\.label), ["Mom's iPhone", "Mom's Mac"])
        XCTAssertEqual(person.devices[0].worstStatus, .pass)
        XCTAssertEqual(person.devices[1].worstStatus, .fail)
        XCTAssertEqual(person.worstStatus, .fail)
        XCTAssertEqual(person.devices[1].checks.map(\.checkID), [.filevault, .gatekeeper])
    }

    func testUnknownBeatsPassAndEmptyIsUnknown() {
        let dashboard = build([zone(results: [result(phone, .osPatched, .pass), result(phone, .findMy, .unknown)])])
        XCTAssertEqual(dashboard.people[0].devices[0].worstStatus, .unknown)
        XCTAssertEqual(dashboard.people[0].devices[1].worstStatus, .unknown, "Mac with no results is grey, never green")
        let empty = build([ZoneSnapshot(zoneName: "z_00000000000000bb")])
        XCTAssertEqual(empty.people[0].worstStatus, .unknown)
        XCTAssertTrue(empty.people[0].devices.isEmpty)
    }

    func testNeverFailsChecksDoNotCountAgainstStatus() {
        let dashboard = build([zone(results: [result(mac, .filevault, .pass), result(mac, .lockdown, .unknown),
                                              result(mac, .adp, .fail)])])
        XCTAssertEqual(dashboard.people[0].devices[1].worstStatus, .pass)
    }

    func testNotReportingGreysTheChipButKeepsChecks() {
        let dashboard = build([zone(phoneDaysAgo: 8, macDaysAgo: 3, results: [
            result(phone, .osPatched, .fail), result(mac, .filevault, .pass),
        ])])
        let devices = dashboard.people[0].devices
        XCTAssertEqual(devices[0].staleness, .notReporting)
        XCTAssertEqual(devices[0].worstStatus, .unknown)
        XCTAssertEqual(devices[0].checks[0].status, .fail, "check keeps its last value until 14 days")
        XCTAssertEqual(devices[0].daysSinceReport, 8)
        XCTAssertEqual(devices[1].staleness, .notReporting, "Mac limit is 2 days")
        XCTAssertEqual(dashboard.people[0].worstStatus, .unknown)
    }

    func testOverFourteenDaysEveryChipGrey() {
        let dashboard = build([zone(phoneDaysAgo: 15, macDaysAgo: 0, results: [
            result(phone, .osPatched, .pass), result(phone, .passcodeSet, .fail), result(mac, .sip, .pass),
        ])])
        let phoneRow = dashboard.people[0].devices[0]
        XCTAssertEqual(phoneRow.staleness, .expired)
        XCTAssertEqual(phoneRow.checks.map(\.status), [.unknown, .unknown])
        XCTAssertEqual(phoneRow.checks.map(\.reportedStatus), [.pass, .fail])
        XCTAssertEqual(dashboard.people[0].devices[1].worstStatus, .pass)
    }

    func testResultsWithoutDeviceRecordAreGrey() {
        let orphan = UUID()
        var z = zone(results: [result(orphan, .osPatched, .pass)])
        z.devices = [:]
        let row = build([z]).people[0].devices[0]
        XCTAssertNil(row.platform)
        XCTAssertEqual(row.staleness, .expired)
        XCTAssertEqual(row.worstStatus, .unknown)
    }

    func testCreatorMismatchFlag() {
        let dashboard = build([zone(results: [
            result(phone, .osPatched, .pass), result(phone, .passcodeSet, .pass, writer: "_stranger"),
            result(mac, .filevault, .pass),
        ])])
        let devices = dashboard.people[0].devices
        XCTAssertTrue(devices[0].creatorMismatch)
        XCTAssertEqual(devices[0].checks.first { $0.checkID == .passcodeSet }?.writtenBySomeoneElse, true)
        XCTAssertEqual(devices[0].checks.first { $0.checkID == .osPatched }?.writtenBySomeoneElse, false)
        XCTAssertFalse(devices[1].creatorMismatch)

        // Unknown first creator: no flag.
        let unlabeled = build([zone(results: [result(phone, .osPatched, .pass, writer: "_stranger")])], deviceLabels: [:])
        XCTAssertFalse(unlabeled.people[0].devices[0].creatorMismatch)
    }

    func testLabelsAndOrdering() {
        var name = PersonNameComponents()
        name.givenName = "Rosa"
        name.familyName = "Rivera"
        let a = ZoneSnapshot(zoneName: "z_00000000000000aa", participantName: name, participantAccepted: true)
        let b = ZoneSnapshot(zoneName: "z_00000000000000bb")
        let me = ZoneSnapshot(zoneName: "z_self")
        let admin = ZoneSnapshot(zoneName: "z_admin")
        let dashboard = build([b, a, admin, me], personLabels: [
            "z_00000000000000bb": PersonLabel(zoneName: "z_00000000000000bb", label: "Dad", createdOn: Date()),
        ])
        XCTAssertEqual(dashboard.people.map(\.zoneName), ["z_self", "z_00000000000000bb", "z_00000000000000aa"])
        XCTAssertTrue(dashboard.people[0].isSelf)
        XCTAssertNil(dashboard.people[0].inviteAccepted)
        XCTAssertEqual(dashboard.people[1].label, "Dad")
        XCTAssertEqual(dashboard.people[2].label, "Rosa Rivera", "defaults to the participant's name")
        XCTAssertEqual(dashboard.people[2].inviteAccepted, true)
    }
}

final class OwnerStoreTests: XCTestCase {
    var backend: InMemoryCloudBackend!
    var settings: SyncSettings!
    var clock: TestClock!
    var store: OwnerStore!
    let today = DateDay(year: 2026, month: 10, day: 22)!

    override func setUp() async throws {
        backend = InMemoryCloudBackend()
        settings = .inMemory()
        clock = TestClock(day: today)
        let counter = OSAllocatedUnfairLock(initialState: 0)
        store = OwnerStore(container: backend.container(), settings: settings, clock: clock.clock, makeZoneName: {
            let n = counter.withLock { $0 += 1; return $0 }
            return "z_" + String(format: "%016x", n)
        })
    }

    func testStartFamilyCreatesAdminAndSelfZones() async throws {
        let before = await store.isOwner
        XCTAssertFalse(before)
        try await store.startFamily()
        let zones = await backend.zoneNames()
        XCTAssertEqual(zones, ["z_admin", "z_self"])
        let after = await store.isOwner
        XCTAssertTrue(after)
        XCTAssertEqual(settings.target, .ownerSelf)
        XCTAssertEqual(settings.connection, .connected)
    }

    func testOwnerModeFollowsAdminZone() async throws {
        let none = try await store.refreshOwnerMode()
        XCTAssertFalse(none)
        try await backend.container().privateDatabase.saveZones([CKRecordZone(zoneName: "z_admin")])
        let found = try await store.refreshOwnerMode()
        XCTAssertTrue(found)
        XCTAssertEqual(settings.target, .ownerSelf, "Ben's second device writes to z_self too")
    }

    func testCreatePersonRequiresOwnerMode() async {
        do {
            _ = try await store.createPerson(label: "Mom")
            XCTFail("expected notOwner")
        } catch {
            XCTAssertEqual(error as? OwnerStoreError, .notOwner)
        }
    }

    func testCreatePersonMakesPrivateZoneWideShareAndLabel() async throws {
        try await store.startFamily()
        let invite = try await store.createPerson(label: "  Mom  ")
        XCTAssertEqual(invite.zoneID.zoneName, "z_0000000000000001")
        XCTAssertTrue(Records.isPersonZoneName(invite.zoneID.zoneName))
        XCTAssertEqual(invite.share.publicPermission, .none)
        XCTAssertEqual(invite.share[CKShare.SystemFieldKey.title] as? String, "Family Shield")
        XCTAssertEqual(invite.share.recordID.zoneID.zoneName, invite.zoneID.zoneName, "zone-wide share")
        XCTAssertEqual(invite.share.recordID.recordName, CKRecordNameZoneWideShare)

        let shareStored = await backend.record(zoneName: invite.zoneID.zoneName, recordName: CKRecordNameZoneWideShare)
        XCTAssertNotNil(shareStored)
        let label = await backend.record(zoneName: "z_admin", recordName: invite.zoneID.zoneName)
        XCTAssertEqual(label?["label"] as? String, "Mom")
        XCTAssertEqual(label?.recordType, "PersonLabel")
        // No person's name in any zone name.
        let zones = await backend.zoneNames()
        XCTAssertFalse(zones.contains { $0.lowercased().contains("mom") })
    }

    func testCreatePersonCleansUpWhenShareFails() async throws {
        try await store.startFamily()
        await backend.failNextModify(with: CKError(.networkFailure))
        do {
            _ = try await store.createPerson(label: "Mom")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? OwnerStoreError, .unavailable)
        }
        let zones = await backend.zoneNames()
        XCTAssertEqual(zones, ["z_admin", "z_self"])
    }

    /// Simulates a family member's device writing into its zone through the shared DB.
    func report(as user: String, zone: String, deviceID: UUID, platform: Platform, lastReport: DateDay,
                results: [(CheckID, Status)]) async throws {
        let zoneID = CKRecordZone.ID(zoneName: zone, ownerName: "_ben")
        let device = DeviceInfo(deviceID: deviceID, platform: platform, enrolledOn: today.adding(days: -20),
                                catalogVersion: 1, appBuild: 3, lastReport: lastReport)
        var records = [Records.record(for: device, in: zoneID)]
        for (check, status) in results {
            records.append(try Records.record(for: CheckResult(deviceID: deviceID, checkID: check, status: status,
                                                               source: .measured, checkedOn: lastReport,
                                                               catalogVersion: 1), in: zoneID))
        }
        _ = try await backend.container(actingAs: user).sharedDatabase
            .modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: false)
    }

    func testDashboardFetchAggregatesAndCachesTokens() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        let dad = try await store.createPerson(label: nil).zoneID.zoneName
        var dadName = PersonNameComponents()
        dadName.givenName = "Walter"
        await backend.setParticipant(zoneName: dad, name: dadName, accepted: true)

        let momPhone = UUID()
        let dadMac = UUID()
        try await report(as: "_mom", zone: mom, deviceID: momPhone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .fail), (.passcodeSet, .pass)])
        try await report(as: "_dad", zone: dad, deviceID: dadMac, platform: .mac, lastReport: today.adding(days: -3),
                         results: [(.filevault, .pass)])

        let dashboard = try await store.refreshDashboard()
        XCTAssertEqual(dashboard.people.map(\.label), [nil, "Mom", "Walter"], "z_self first, then by label")
        let momRow = try XCTUnwrap(dashboard.people.first { $0.zoneName == mom })
        XCTAssertEqual(momRow.label, "Mom")
        XCTAssertEqual(momRow.worstStatus, .fail)
        XCTAssertEqual(momRow.devices.first?.checks.count, 2)
        let dadRow = try XCTUnwrap(dashboard.people.first { $0.zoneName == dad })
        XCTAssertEqual(dadRow.label, "Walter", "PersonLabel defaults to the participant's name")
        XCTAssertEqual(dadRow.devices.first?.staleness, .notReporting, "Mac > 2 days")
        XCTAssertEqual(dadRow.inviteAccepted, true)
        let selfRow = try XCTUnwrap(dashboard.people.first)
        XCTAssertTrue(selfRow.isSelf)

        // First creators were recorded in z_admin, and the default person label was saved.
        let deviceLabel = await backend.record(zoneName: "z_admin", recordName: Records.deviceRecordName(momPhone))
        XCTAssertEqual(deviceLabel?["firstCreatorRecordName"] as? String, "_mom")
        let dadLabel = await backend.record(zoneName: "z_admin", recordName: dad)
        XCTAssertEqual(dadLabel?["label"] as? String, "Walter")

        // Second refresh uses the cached tokens: only the new change comes back.
        try await report(as: "_mom", zone: mom, deviceID: momPhone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass)])
        let second = try await store.refreshDashboard()
        let momAgain = try XCTUnwrap(second.people.first { $0.zoneName == mom })
        XCTAssertEqual(momAgain.worstStatus, .pass)
        XCTAssertEqual(momAgain.devices.first?.checks.count, 2, "unchanged records come from the cache")

        // The cache survives a relaunch.
        let relaunched = OwnerStore(container: backend.container(), settings: settings, clock: clock.clock)
        let cached = await relaunched.cachedDashboard()
        XCTAssertEqual(cached, second)
    }

    func testStalenessAppliesAsTimePasses() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        let phone = UUID()
        try await report(as: "_mom", zone: mom, deviceID: phone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass)])
        _ = try await store.refreshDashboard()

        clock.advance(days: 8)
        let notReporting = try await store.refreshDashboard()
        let row = try XCTUnwrap(notReporting.people.first { $0.zoneName == mom }?.devices.first)
        XCTAssertEqual(row.staleness, .notReporting)
        XCTAssertEqual(row.worstStatus, .unknown)

        clock.advance(days: 7)
        let expired = await store.cachedDashboard()
        let old = try XCTUnwrap(expired.people.first { $0.zoneName == mom }?.devices.first)
        XCTAssertEqual(old.staleness, .expired)
        XCTAssertEqual(old.checks.map(\.status), [.unknown])
    }

    func testCreatorMismatchIsFlagged() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        let phone = UUID()
        try await report(as: "_mom", zone: mom, deviceID: phone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass)])
        _ = try await store.refreshDashboard()
        // Someone else overwrites a result in Mom's zone.
        try await report(as: "_intruder", zone: mom, deviceID: phone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass)])
        let dashboard = try await store.refreshDashboard()
        let row = try XCTUnwrap(dashboard.people.first { $0.zoneName == mom }?.devices.first)
        XCTAssertTrue(row.creatorMismatch)
        XCTAssertEqual(row.checks.first?.writtenBySomeoneElse, true)
    }

    func testDeletedRecordsAndZonesDisappear() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        let dad = try await store.createPerson(label: "Dad").zoneID.zoneName
        let phone = UUID()
        try await report(as: "_mom", zone: mom, deviceID: phone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass), (.sip, .pass)])
        _ = try await store.refreshDashboard()

        // Mom's device leaves (deletes its records).
        let zoneID = CKRecordZone.ID(zoneName: mom, ownerName: "_ben")
        let ids = [CKRecord.ID(recordName: Records.deviceRecordName(phone), zoneID: zoneID)]
            + [CheckID.osPatched, .sip].map { CKRecord.ID(recordName: CheckResult.recordName(deviceID: phone, checkID: $0), zoneID: zoneID) }
        _ = try await backend.container(actingAs: "_mom").sharedDatabase
            .modifyRecords(saving: [], deleting: ids, savePolicy: .changedKeys, atomically: false)
        await backend.removeZone(dad)

        let dashboard = try await store.refreshDashboard()
        XCTAssertEqual(dashboard.people.first { $0.zoneName == mom }?.devices.count, 0)
        XCTAssertNil(dashboard.people.first { $0.zoneName == dad })
    }

    func testExpiredTokensRefetchFromScratch() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        let phone = UUID()
        try await report(as: "_mom", zone: mom, deviceID: phone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .fail)])
        _ = try await store.refreshDashboard()
        await backend.expireChangeTokens()
        let fetchesBefore = await backend.fetchCount
        let dashboard = try await store.refreshDashboard()
        let fetchesAfter = await backend.fetchCount
        XCTAssertEqual(fetchesAfter - fetchesBefore, 2, "one fetch, then a full refetch of the expired zones")
        let momRow = try XCTUnwrap(dashboard.people.first { $0.zoneName == mom })
        XCTAssertEqual(momRow.worstStatus, .fail)
        XCTAssertEqual(momRow.label, "Mom", "labels refetched too")
    }

    func testExpiredTokenWithFailedRefetchKeepsTheCachedZone() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        try await report(as: "_mom", zone: mom, deviceID: UUID(), platform: .ios, lastReport: today,
                         results: [(.osPatched, .fail)])
        _ = try await store.refreshDashboard()

        // The token expires, and the from-scratch refetch of that zone fails on a flaky network.
        await backend.failNextFetch(ofZone: mom, with: CKError(.changeTokenExpired))
        await backend.failNextFetch(ofZone: mom, with: CKError(.networkFailure))
        let dashboard = try await store.refreshDashboard()
        let row = try XCTUnwrap(dashboard.people.first { $0.zoneName == mom })
        XCTAssertEqual(row.devices.count, 1, "Mom's device does not vanish")
        XCTAssertEqual(row.worstStatus, .fail)
        let relaunched = OwnerStore(container: backend.container(), settings: settings, clock: clock.clock)
        let cached = await relaunched.cachedDashboard()
        XCTAssertEqual(cached.people.first { $0.zoneName == mom }?.devices.count, 1, "nor from the persisted cache")

        // The whole refetch throwing keeps the in-memory cache as well.
        await backend.failNextFetch(ofZone: mom, with: CKError(.changeTokenExpired))
        let fetches = await backend.fetchCount
        await backend.failFetch(number: fetches + 2, with: CKError(.networkUnavailable))
        do {
            _ = try await store.refreshDashboard()
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? OwnerStoreError, .unavailable)
        }
        let inMemory = await store.cachedDashboard()
        XCTAssertEqual(inMemory.people.first { $0.zoneName == mom }?.devices.count, 1)

        // Once the refetch works, the zone is rebuilt from scratch.
        let healed = try await store.refreshDashboard()
        XCTAssertEqual(healed.people.first { $0.zoneName == mom }?.devices.count, 1)
        XCTAssertEqual(healed.people.first { $0.zoneName == mom }?.label, "Mom")
    }

    func testOffSchemaRecordsAreIgnored() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        let phone = UUID()
        try await report(as: "_mom", zone: mom, deviceID: phone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass)])
        let zoneID = CKRecordZone.ID(zoneName: mom, ownerName: "_ben")
        let bogus = CKRecord(recordType: "CheckResult",
                             recordID: CKRecord.ID(recordName: "\(phone.uuidString.lowercased())_gmail", zoneID: zoneID))
        bogus["status"] = 1 as NSNumber
        await backend.put(bogus, as: "_mom")
        let note = CKRecord(recordType: "Note", recordID: CKRecord.ID(recordName: "n", zoneID: zoneID))
        note["text"] = "hello" as NSString
        await backend.put(note, as: "_mom")

        let dashboard = try await store.refreshDashboard()
        let row = try XCTUnwrap(dashboard.people.first { $0.zoneName == mom }?.devices.first)
        XCTAssertEqual(row.checks.map(\.checkID), [.osPatched])
    }

    func testFetchFailureKeepsCacheAndThrows() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        try await report(as: "_mom", zone: mom, deviceID: UUID(), platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass)])
        let first = try await store.refreshDashboard()
        await backend.failNextFetch(with: CKError(.networkUnavailable))
        do {
            _ = try await store.refreshDashboard()
            XCTFail("expected unavailable")
        } catch {
            XCTAssertEqual(error as? OwnerStoreError, .unavailable)
        }
        let cached = await store.cachedDashboard()
        XCTAssertEqual(cached, first)

        // A per-zone failure keeps that zone's cached data, and says the refresh was incomplete
        // (CloudKit reports per-zone errors as a partial failure, not a thrown error).
        await backend.failNextFetch(ofZone: mom, with: CKError(.zoneBusy))
        let partial = try await store.refreshDashboard()
        XCTAssertEqual(partial.people.first { $0.zoneName == mom }?.devices.count, 1)
        XCTAssertTrue(partial.incomplete, "\"Couldn't refresh. Showing the last copy.\"")
        let clean = try await store.refreshDashboard()
        XCTAssertFalse(clean.incomplete)
    }

    func testDevelopmentStartFamilySeedsEveryAdminRecordType() async throws {
        // Production never creates a record type on save; the Development run Ben deploys from
        // must have PersonLabel and DeviceLabel even before he names anyone (§14.2 step 2).
        let seeding = OwnerStore(container: backend.container(), settings: settings, clock: clock.clock, seedsSchema: true)
        try await seeding.startFamily()
        let log = await backend.modifyLog
        let saved = Set(log.flatMap(\.savedRecordNames))
        XCTAssertTrue(saved.contains(Records.schemaSeedZoneName), "a PersonLabel was saved")
        XCTAssertTrue(saved.contains(Records.deviceRecordName(Records.schemaSeedDeviceID)), "a DeviceLabel was saved")
        let keys = log.first { $0.savedRecordNames.contains(Records.schemaSeedZoneName) }?.savedKeys
        XCTAssertEqual(keys?[Records.schemaSeedZoneName], Records.PersonLabelField.all, "every field, so every field exists")
        let left = await backend.recordNames(zoneName: Records.adminZoneName)
        XCTAssertTrue(left.isEmpty, "and deleted again: \(left)")
        let dashboard = try await seeding.refreshDashboard()
        XCTAssertTrue(dashboard.people.allSatisfy { $0.zoneName != Records.schemaSeedZoneName })

        // Release builds don't seed (the default).
        let before = await backend.modifyLog.count
        try await store.startFamily()
        let after = await backend.modifyLog.count
        XCTAssertEqual(after, before)
    }

    func testLabelsAreBenOnlyAndPreserveFirstCreator() async throws {
        try await store.startFamily()
        let mom = try await store.createPerson(label: "Mom").zoneID.zoneName
        let phone = UUID()
        try await report(as: "_mom", zone: mom, deviceID: phone, platform: .ios, lastReport: today,
                         results: [(.osPatched, .pass)])
        _ = try await store.refreshDashboard()
        try await store.setDeviceLabel(deviceID: phone, label: "Mom's iPhone")
        try await store.setPersonLabel(zoneName: mom, label: "Mother")

        let record = await backend.record(zoneName: "z_admin", recordName: Records.deviceRecordName(phone))
        XCTAssertEqual(record?["label"] as? String, "Mom's iPhone")
        XCTAssertEqual(record?["firstCreatorRecordName"] as? String, "_mom")
        // Nothing label-like ever lands in the person zone.
        let names = await backend.recordNames(zoneName: mom)
        for name in names where name != CKRecordNameZoneWideShare {
            let stored = await backend.record(zoneName: mom, recordName: name)
            XCTAssertNil(stored?["label"])
        }
        let dashboard = await store.cachedDashboard()
        let momRow = try XCTUnwrap(dashboard.people.first { $0.zoneName == mom })
        XCTAssertEqual(momRow.label, "Mother")
        XCTAssertEqual(momRow.devices.first?.label, "Mom's iPhone")

        do {
            try await store.setPersonLabel(zoneName: "z_self", label: "x")
            XCTFail("expected invalidZone")
        } catch {
            XCTAssertEqual(error as? OwnerStoreError, .invalidZone)
        }
    }
}
