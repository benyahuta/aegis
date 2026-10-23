import CloudKit
import os
import XCTest
@testable import ShieldCore

/// A scheduler that only records retries; tests fire them by hand.
final class ManualScheduler: RetryScheduler {
    private let state = OSAllocatedUnfairLock<[(TimeInterval, @Sendable () async -> Void)]>(initialState: [])

    var delays: [TimeInterval] { state.withLock { $0.map(\.0) } }
    var pendingCount: Int { state.withLock { $0.count } }

    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () async -> Void) {
        state.withLock { $0.append((delay, work)) }
    }

    /// Runs (and removes) the oldest scheduled retry.
    func runNext() async {
        let next = state.withLock { queue -> (@Sendable () async -> Void)? in
            queue.isEmpty ? nil : queue.removeFirst().1
        }
        await next?()
    }
}

final class CloudKitSinkTests: XCTestCase {
    let deviceID = UUID(uuidString: "0B0B0B0B-1111-4222-8333-444455556666")!
    let personZone = "z_00112233aabbccdd"
    lazy var zoneID = CKRecordZone.ID(zoneName: personZone, ownerName: "_ben")
    let start = DateDay(year: 2026, month: 10, day: 22)!

    var backend: InMemoryCloudBackend!
    var settings: SyncSettings!
    var clock: TestClock!
    var scheduler: ManualScheduler!
    var identity: InMemoryDeviceIdentityStore!
    var sink: CloudKitSink!

    override func setUp() async throws {
        backend = InMemoryCloudBackend()
        // Ben created the person zone.
        try await backend.container().privateDatabase.saveZones([CKRecordZone(zoneName: personZone)])
        settings = .inMemory()
        clock = TestClock(start.date.addingTimeInterval(9 * 3600))
        scheduler = ManualScheduler()
        identity = InMemoryDeviceIdentityStore(deviceID)
        sink = CloudKitSink(container: backend.container(actingAs: "_mom"), identity: identity,
                            settings: settings, clock: clock.clock, scheduler: scheduler)
    }

    func device(platform: Platform = .ios, build: Int = 7, lastReport: DateDay? = nil) -> DeviceInfo {
        DeviceInfo(deviceID: deviceID, platform: platform, enrolledOn: start, catalogVersion: 1, appBuild: build,
                   lastReport: lastReport ?? start.adding(days: -3))
    }

    func result(_ check: CheckID, _ status: Status, source: Source = .measured) -> CheckResult {
        CheckResult(deviceID: deviceID, checkID: check, status: status, source: source,
                    checkedAt: clock.now, catalogVersion: 1)
    }

    var reportResults: [CheckResult] {
        [result(.osPatched, .fail), result(.passcodeSet, .pass), result(.stolenDeviceProtection, .unknown, source: .selfReported)]
    }

    func storedStatus(_ check: CheckID) async -> Int64? {
        let record = await backend.record(zoneName: personZone,
                                          recordName: CheckResult.recordName(deviceID: deviceID, checkID: check))
        return (record?["status"] as? NSNumber)?.int64Value
    }

    // MARK: Enroll

    func testUpsertBeforeJoiningThrowsNotConnectedAndKeepsState() async throws {
        await assertThrows(.notConnected) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
        let pending = await sink.pendingBatch
        XCTAssertEqual(pending?.results.count, 3)
        let state = await sink.connectionState
        XCTAssertEqual(state, .notJoined)
        let log = await backend.modifyLog
        XCTAssertTrue(log.isEmpty, "nothing written without a share")
    }

    func testEnrollSavesDeviceWithAllKeysThenFlushesWaitingReport() async throws {
        try? await sink.upsert(device: device(), results: reportResults)
        try await sink.enroll(zoneID: zoneID, device: device())

        let log = await backend.modifyLog
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log[0].scope, .shared)
        XCTAssertEqual(log[0].savePolicy, .allKeys)
        XCTAssertEqual(log[0].savedRecordNames, [Records.deviceRecordName(deviceID)])
        XCTAssertEqual(log[1].savePolicy, .changedKeys)
        XCTAssertEqual(log[1].savedRecordNames.count, 4)

        XCTAssertEqual(settings.target, .shared(zoneID))
        let state = await sink.connectionState
        XCTAssertEqual(state, .connected)
        let pending = await sink.pendingBatch
        XCTAssertNil(pending)
        let osPatched = await storedStatus(.osPatched)
        XCTAssertEqual(osPatched, 2)
    }

    func testReEnrollOverwritesExistingDevice() async throws {
        try await sink.enroll(zoneID: zoneID, device: device(build: 1))
        try await sink.enroll(zoneID: zoneID, device: device(build: 2))
        let record = await backend.record(zoneName: personZone, recordName: Records.deviceRecordName(deviceID))
        XCTAssertEqual((record?["appBuild"] as? NSNumber)?.int64Value, 2)
    }

    // MARK: Report

    func testReportWritesEveryResultPlusDeviceWithChangedKeys() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        try await sink.upsert(device: device(), results: reportResults)

        let callFetched = await backend.modifyLog.last

        let call = try XCTUnwrap(callFetched)
        XCTAssertEqual(call.scope, .shared)
        XCTAssertEqual(call.savePolicy, .changedKeys)
        XCTAssertFalse(call.atomically)
        XCTAssertEqual(Set(call.savedRecordNames), Set([Records.deviceRecordName(deviceID)]
            + reportResults.map(\.recordName)))
        for (name, keys) in call.savedKeys {
            if name == Records.deviceRecordName(deviceID) {
                XCTAssertEqual(keys, Records.DeviceField.all)
            } else {
                XCTAssertEqual(keys, Records.CheckResultField.all)
            }
        }
        let deviceRecord = await backend.record(zoneName: personZone, recordName: Records.deviceRecordName(deviceID))
        XCTAssertEqual(deviceRecord?["lastReport"] as? Date, start.date, "lastReport = today, 00:00 UTC")
        let resultRecord = await backend.record(zoneName: personZone, recordName: reportResults[0].recordName)
        XCTAssertEqual(resultRecord?["checkedOn"] as? Date, start.date, "checkedOn truncated to the day")
        let creator = await backend.creator(zoneName: personZone, recordName: reportResults[0].recordName)
        XCTAssertEqual(creator, "_mom")
    }

    func testSkipsUnchangedReportOnTheSameDayButNotTheNextDay() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        try await sink.upsert(device: device(), results: reportResults)
        let afterFirst = await backend.modifyLog.count

        clock.advance(seconds: 3600)
        try await sink.upsert(device: device(), results: reportResults)
        let afterSame = await backend.modifyLog.count
        XCTAssertEqual(afterSame, afterFirst, "nothing changed and lastReport is today: skipped")

        try await sink.upsert(device: device(), results: [result(.osPatched, .pass)])
        let afterChange = await backend.modifyLog.count
        XCTAssertEqual(afterChange, afterFirst + 1, "a change is written the same day")

        clock.advance(days: 1)
        try await sink.upsert(device: device(), results: [result(.osPatched, .pass)].map {
            var r = $0; r.checkedOn = start; return r
        })
        let afterNextDay = await backend.modifyLog.count
        XCTAssertEqual(afterNextDay, afterChange + 1, "lastReport is not today: written")
        let deviceRecord = await backend.record(zoneName: personZone, recordName: Records.deviceRecordName(deviceID))
        XCTAssertEqual(deviceRecord?["lastReport"] as? Date, start.adding(days: 1).date)
    }

    func testRejectsForeignDeviceAndBadIdentity() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        var other = device()
        other.deviceID = UUID()
        let foreign = CheckResult(deviceID: other.deviceID, checkID: .sip, status: .pass, source: .measured,
                                  checkedOn: start, catalogVersion: 1)
        await assertThrows(.deviceMismatch) { try await self.sink.upsert(device: other, results: [foreign]) }
        await assertThrows(.deviceMismatch) { try await self.sink.upsert(device: self.device(), results: [foreign]) }

        identity.setFailure(.keychain(-25308))
        await assertThrows(.unavailable) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
        identity.setFailure(nil)
    }

    // MARK: Errors, queue and backoff

    func testTransientFailureQueuesAndBacksOffExponentially() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.failNextModify(with: CKError(.networkUnavailable))
        await assertThrows(.unavailable) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
        XCTAssertEqual(scheduler.delays, [60])
        let next = await sink.nextRetryDate
        XCTAssertEqual(next, clock.now.addingTimeInterval(60))

        // Retry fails again: 2 minutes.
        clock.advance(seconds: 60)
        await backend.failNextModify(with: CKError(.serviceUnavailable))
        await scheduler.runNext()
        XCTAssertEqual(scheduler.delays, [120])

        // Rate limited: use the server's retryAfterSeconds.
        clock.advance(seconds: 120)
        await backend.failNextModify(with: CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 30.0]))
        await scheduler.runNext()
        XCTAssertEqual(scheduler.delays, [30])

        // While the server asks us to wait, a new report only updates the queue (last state wins).
        let writesBefore = await backend.modifyLog.count
        try? await sink.upsert(device: device(), results: [result(.osPatched, .pass)])
        let writesDuringHold = await backend.modifyLog.count
        XCTAssertEqual(writesDuringHold, writesBefore, "retryAfterSeconds is honored")
        XCTAssertEqual(scheduler.pendingCount, 1, "one retry scheduled, not two")

        // Then it works, and only the latest state lands.
        clock.advance(seconds: 30)
        await scheduler.runNext()
        let pending = await sink.pendingBatch
        XCTAssertNil(pending)
        let osPatched = await storedStatus(.osPatched)
        XCTAssertEqual(osPatched, 1, "latest state (pass) won over the queued fail")
        let passcode = await storedStatus(.passcodeSet)
        XCTAssertEqual(passcode, 1, "older checks in the queue were kept")
        XCTAssertEqual(scheduler.pendingCount, 0)
        let state = await sink.connectionState
        XCTAssertEqual(state, .connected)
    }

    func testPerRecordTransientFailureKeepsWholeBatchQueued() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.failRecord(named: reportResults[1].recordName, with: CKError(.zoneBusy))
        await assertThrows(.unavailable) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
        let pending = await sink.pendingBatch
        XCTAssertEqual(pending?.results.count, 3)
        clock.advance(seconds: 60)
        await scheduler.runNext()
        let passcode = await storedStatus(.passcodeSet)
        XCTAssertEqual(passcode, 1)
        let after = await sink.pendingBatch
        XCTAssertNil(after)
    }

    func testNewReportIsSentRightAwayDespiteOurBackoff() async throws {
        // An earlier failure must not keep a foreground report (or a changed check) waiting
        // for the backoff timer, which can be up to 6 hours after a night offline.
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.failNextModify(with: CKError(.networkFailure))
        try? await sink.upsert(device: device(), results: reportResults)
        await backend.failNextModify(with: CKError(.networkFailure))
        clock.advance(seconds: 60)
        await scheduler.runNext()
        let retry = await sink.nextRetryDate
        XCTAssertEqual(retry, clock.now.addingTimeInterval(120))

        // The network is back and the person opens the app: delivered now, merged with the queue.
        clock.advance(seconds: 5)
        try await sink.upsert(device: device(), results: [result(.osPatched, .pass)])
        let pending = await sink.pendingBatch
        XCTAssertNil(pending)
        let osPatched = await storedStatus(.osPatched)
        XCTAssertEqual(osPatched, 1)
        let passcode = await storedStatus(.passcodeSet)
        XCTAssertEqual(passcode, 1, "the queued checks went too")
    }

    func testSignedOutOrStorageFullSaysNotReachingBenAndKeepsRetrying() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        for (code, status) in [(CKError.Code.quotaExceeded, Status.fail), (.notAuthenticated, .pass)] {
            await backend.failNextModify(with: CKError(code))
            await assertThrows(.unavailable) {
                try await self.sink.upsert(device: self.device(), results: [self.result(.osPatched, status)])
            }
            let state = await sink.connectionState
            XCTAssertEqual(state, .notDelivering, "not \"Connected to Ben\" while nothing arrives (\(code.rawValue))")
            let pending = await sink.pendingBatch
            XCTAssertNotNil(pending, "kept for the retry")
            clock.advance(seconds: 6 * 3_600)
            await scheduler.runNext()
            let after = await sink.connectionState
            XCTAssertEqual(after, .connected, "the next delivery that works says Connected again")
        }
    }

    func testOnlyThePeriodicReportIsDiscretionary() async throws {
        // §8.4: the report runs at .utility; enroll and leave are awaited by the person and must
        // not be paused by Low Power Mode.
        try await sink.enroll(zoneID: zoneID, device: device())
        try await sink.upsert(device: device(), results: reportResults)
        try await sink.leave()
        let priorities = await backend.modifyLog.map(\.priority)
        XCTAssertEqual(priorities, [.interactive, .background, .interactive])
    }

    func testFlushPendingIgnoresBackoff() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.failNextModify(with: CKError(.networkFailure))
        try? await sink.upsert(device: device(), results: reportResults)
        try await sink.flushPending()   // app came to the foreground
        let pending = await sink.pendingBatch
        XCTAssertNil(pending)
    }

    func testZoneGoneMarksNotConnectedAndKeepsWorking() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.removeZone(personZone)
        await assertThrows(.notConnected) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
        let state = await sink.connectionState
        XCTAssertEqual(state, .notConnected)
        XCTAssertEqual(settings.connection, .notConnected, "persisted for About")
        XCTAssertEqual(scheduler.pendingCount, 0, "no retry loop for a revoked share")

        for code in [CKError.Code.userDeletedZone, .participantMayNeedVerification, .permissionFailure] {
            await backend.failNextModify(with: CKError(code))
            await assertThrows(.notConnected) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
        }

        // Ben re-invites: enrolling again reconnects and delivers the latest state.
        try await backend.container().privateDatabase.saveZones([CKRecordZone(zoneName: personZone)])
        try await sink.enroll(zoneID: zoneID, device: device())
        let reconnected = await sink.connectionState
        XCTAssertEqual(reconnected, .connected)
        let osPatched = await storedStatus(.osPatched)
        XCTAssertEqual(osPatched, 2)
    }

    func testServerRecordChangedIsOverwrittenWithOurs() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        try await sink.upsert(device: device(), results: reportResults)
        let name = reportResults[0].recordName
        let serverFetched = await backend.record(zoneName: personZone, recordName: name)
        let server = try XCTUnwrap(serverFetched)
        server["status"] = 1 as NSNumber
        await backend.put(server, as: "_mom")
        let serverCopyFetched = await backend.record(zoneName: personZone, recordName: name)
        let serverCopy = try XCTUnwrap(serverCopyFetched)
        await backend.failRecord(named: name, with: CKError(.serverRecordChanged,
                                                            userInfo: [CKRecordChangedErrorServerRecordKey: serverCopy]))

        try await sink.upsert(device: device(), results: [result(.osPatched, .unknown)])
        let status = await storedStatus(.osPatched)
        XCTAssertEqual(status, 0, "ours (unknown) overwrote the server copy")
        let lastFetched = await backend.modifyLog.last
        let last = try XCTUnwrap(lastFetched)
        XCTAssertEqual(last.savedRecordNames, [name])
        XCTAssertEqual(last.savePolicy, .allKeys)
    }

    func testOwnerDeviceWritesToSelfZoneInPrivateDatabase() async throws {
        let ben = CloudKitSink(container: backend.container(), identity: identity, settings: settings,
                               clock: clock.clock, scheduler: scheduler)
        try await backend.container().privateDatabase.saveZones([CKRecordZone(zoneName: "z_self")])
        try await ben.enrollAsOwnerDevice(device: device(platform: .mac))
        try await ben.upsert(device: device(platform: .mac), results: reportResults)
        let log = await backend.modifyLog
        XCTAssertTrue(log.allSatisfy { $0.scope == .private })
        let names = await backend.recordNames(zoneName: "z_self")
        XCTAssertEqual(names.count, 4)
        XCTAssertEqual(settings.target, .ownerSelf)
    }

    func testDeviceNeverReadsItsOwnStatusBack() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        try await sink.upsert(device: device(), results: reportResults)
        await backend.failNextModify(with: CKError(.networkFailure))
        try? await sink.upsert(device: device(), results: [result(.sip, .pass)])
        try? await sink.leave()
        let fetches = await backend.fetchCount
        XCTAssertEqual(fetches, 0)
    }

    // MARK: Leave

    func testLeaveDeletesThisDevicesRecordsAndLeavesTheShare() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        try await sink.upsert(device: device(), results: reportResults)
        // Another device of the same person stays.
        let otherID = UUID()
        let other = Records.record(for: DeviceInfo(deviceID: otherID, platform: .mac, enrolledOn: start,
                                                   catalogVersion: 1, appBuild: 1, lastReport: start),
                                   in: zoneID)
        await backend.put(other, as: "_mom")

        try await sink.leave()

        let names = await backend.recordNames(zoneName: personZone)
        XCTAssertEqual(names, [Records.deviceRecordName(otherID)])
        let left = await backend.hasLeft(zoneName: personZone, user: "_mom")
        XCTAssertTrue(left)
        let deleteCallFetched = await backend.modifyLog.last
        let deleteCall = try XCTUnwrap(deleteCallFetched)
        XCTAssertEqual(deleteCall.deletedRecordNames.count, 1 + CheckID.allCases.count)
        XCTAssertNil(settings.target)
        XCTAssertNil(settings.lastSent)
        let state = await sink.connectionState
        XCTAssertEqual(state, .notJoined)
        await assertThrows(.notConnected) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
    }

    func testLeaveWhileOfflineChangesNothing() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.failNextModify(with: CKError(.networkUnavailable))
        await assertThrows(.unavailable) { try await self.sink.leave() }
        XCTAssertEqual(settings.target, .shared(zoneID))
    }

    func testLeaveWhenZoneAlreadyGoneSucceeds() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.removeZone(personZone)
        try await sink.leave()
        XCTAssertNil(settings.target)
    }

    func testLeaveWithoutJoiningIsANoOp() async throws {
        try await sink.leave()
        let log = await backend.modifyLog
        XCTAssertTrue(log.isEmpty)
    }

    func testStopSharingOnOneDeviceDisconnectsTheAccountsOtherDevices() async throws {
        // §8.4 leaves the share by deleting the shared zone, which is account-wide: the person's
        // other device (same Apple Account) is then "Not connected to Ben" and can join again
        // from Ben's link. The confirm sheet says so (about.stopSharing.confirmMessage).
        try await sink.enroll(zoneID: zoneID, device: device())
        let otherID = UUID()
        let otherSettings = SyncSettings.inMemory()
        let other = CloudKitSink(container: backend.container(actingAs: "_mom"),
                                 identity: InMemoryDeviceIdentityStore(otherID), settings: otherSettings,
                                 clock: clock.clock, scheduler: ManualScheduler(), enrollSettleDelays: [])
        let otherDevice = DeviceInfo(deviceID: otherID, platform: .mac, enrolledOn: start, catalogVersion: 1,
                                     appBuild: 1, lastReport: start)
        try await other.enroll(zoneID: zoneID, device: otherDevice)

        try await sink.leave()
        do {
            try await other.upsert(device: otherDevice, results: [])
            XCTFail("expected notConnected")
        } catch {
            XCTAssertEqual(error as? ResultSinkError, .notConnected)
        }
        XCTAssertEqual(otherSettings.connection, .notConnected)
        XCTAssertTrue(ShieldStrings.text("about.stopSharing.confirmMessage").contains("other"))
    }

    // MARK: Share acceptance and enrollment (review regressions)

    func testShareAcceptanceNeverSilentlyRetargets() async throws {
        let other = CKRecordZone.ID(zoneName: "z_ffffeeeeddddcccc", ownerName: "_someoneElse")
        // Only a zone-wide share of a person zone.
        await assertAcceptance(.invalidShare, zone: CKRecordZone.ID(zoneName: "z_admin", ownerName: "_ben"))
        await assertAcceptance(.invalidShare, zone: zoneID, recordName: "someRecord")
        // Not joined yet: fine.
        await assertAcceptance(nil, zone: zoneID)

        try await sink.enroll(zoneID: zoneID, device: device())
        await assertAcceptance(nil, zone: zoneID, "re-accepting the same zone is fine")
        await assertAcceptance(.alreadyConnected, zone: other, "a connected device never moves silently")

        // Once the old share is gone, a new invite may be accepted.
        settings.connection = .notConnected
        await assertAcceptance(nil, zone: other)

        // Ben's own devices never join a share.
        settings.target = .ownerSelf
        settings.connection = .connected
        await assertAcceptance(.alreadyConnected, zone: other)
        settings.target = nil
        settings.isOwner = true
        await assertAcceptance(.alreadyConnected, zone: other)
    }

    func testEnrollWaitsForAJustAcceptedZone() async throws {
        let settling = CloudKitSink(container: backend.container(actingAs: "_mom"), identity: identity,
                                    settings: settings, clock: clock.clock, scheduler: scheduler,
                                    enrollSettleDelays: [0, 0, 0])
        let name = Records.deviceRecordName(deviceID)
        await backend.failRecord(named: name, with: CKError(.zoneNotFound), times: 2)
        try await settling.enroll(zoneID: zoneID, device: device())
        let state = await settling.connectionState
        XCTAssertEqual(state, .connected, "a zone still materializing is not 'Not connected to Ben'")
        let saved = await backend.record(zoneName: personZone, recordName: name)
        XCTAssertNotNil(saved)

        // A zone that never appears is still "Not connected" after the bounded retries.
        await backend.failRecord(named: name, with: CKError(.zoneNotFound), times: 4)
        await assertThrows(.notConnected) { try await settling.enroll(zoneID: self.zoneID, device: self.device()) }
        let after = await settling.connectionState
        XCTAssertEqual(after, .notConnected)
    }

    func testPermanentRejectionStopsRetryingAndSaysNotDelivering() async throws {
        try await sink.enroll(zoneID: zoneID, device: device())
        await backend.failNextModify(with: CKError(.serverRejectedRequest))
        await assertThrows(.rejected) { try await self.sink.upsert(device: self.device(), results: self.reportResults) }
        XCTAssertEqual(settings.connection, .notDelivering, "About no longer claims the reports arrive")
        XCTAssertEqual(scheduler.pendingCount, 0, "no retry timer for an error no retry can fix")
        let pending = await sink.pendingBatch
        XCTAssertEqual(pending?.results.count, 3, "kept for the next report")

        // The next report (for example after Ben deploys the schema) delivers it and reconnects.
        try await sink.upsert(device: device(), results: reportResults)
        XCTAssertEqual(settings.connection, .connected)
        let osPatched = await storedStatus(.osPatched)
        XCTAssertEqual(osPatched, 2)
    }

    // MARK: Helpers

    func assertAcceptance(_ expected: ResultSinkError?, zone: CKRecordZone.ID, recordName: String = CKRecordNameZoneWideShare,
                          _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await sink.acceptance(zoneID: zone, shareRecordName: recordName)
            XCTAssertNil(expected, message, file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        }
    }

    func assertThrows(_ expected: ResultSinkError, file: StaticString = #filePath, line: UInt = #line,
                      _ body: @escaping () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ResultSinkError, expected, file: file, line: line)
        }
    }
}
