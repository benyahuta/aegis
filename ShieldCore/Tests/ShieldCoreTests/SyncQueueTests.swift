import CloudKit
import XCTest
@testable import ShieldCore

final class BackoffTests: XCTestCase {
    func testExponentialFromOneMinuteToSixHours() {
        let backoff = Backoff()
        XCTAssertEqual(backoff.delay(afterFailures: 1), 60)
        XCTAssertEqual(backoff.delay(afterFailures: 2), 120)
        XCTAssertEqual(backoff.delay(afterFailures: 3), 240)
        XCTAssertEqual(backoff.delay(afterFailures: 9), 15_360)
        XCTAssertEqual(backoff.delay(afterFailures: 10), 21_600, "capped at 6 h")
        XCTAssertEqual(backoff.delay(afterFailures: 1_000), 21_600, "no overflow")
        XCTAssertEqual(backoff.delay(afterFailures: 0), 60)
    }

    func testRetryAfterWinsButIsCapped() {
        let backoff = Backoff()
        XCTAssertEqual(backoff.delay(afterFailures: 5, retryAfter: 30), 30)
        XCTAssertEqual(backoff.delay(afterFailures: 1, retryAfter: 100_000), 21_600)
        XCTAssertEqual(backoff.delay(afterFailures: 2, retryAfter: 0), 120, "non-positive ignored")
        XCTAssertEqual(backoff.delay(afterFailures: 2, retryAfter: .nan), 120)
    }
}

final class SyncQueueTests: XCTestCase {
    let deviceID = UUID()
    let day = DateDay(year: 2026, month: 10, day: 22)!

    func device(build: Int = 1) -> DeviceInfo {
        DeviceInfo(deviceID: deviceID, platform: .ios, enrolledOn: day, catalogVersion: 1, appBuild: build, lastReport: day)
    }

    func result(_ check: CheckID, _ status: Status) -> CheckResult {
        CheckResult(deviceID: deviceID, checkID: check, status: status, source: .measured, checkedOn: day, catalogVersion: 1)
    }

    func testLastStateWinsPerCheck() {
        var queue = SyncQueue()
        queue.enqueue(device: device(build: 1), results: [result(.osPatched, .fail), result(.filevault, .pass)])
        queue.enqueue(device: device(build: 2), results: [result(.osPatched, .pass)])
        queue.enqueue(device: device(build: 3), results: [result(.sip, .unknown)])
        let pending = try! XCTUnwrap(queue.pending)
        XCTAssertEqual(pending.device.appBuild, 3)
        XCTAssertEqual(pending.results.count, 3)
        XCTAssertEqual(pending.results[.osPatched]?.status, .pass, "newest wins")
        XCTAssertEqual(pending.results[.filevault]?.status, .pass, "older checks kept")
        XCTAssertEqual(pending.results[.sip]?.status, .unknown)
        XCTAssertEqual(pending.sortedResults.map(\.checkID), [.filevault, .osPatched, .sip])
    }

    func testDifferentDeviceReplacesBatch() {
        var queue = SyncQueue()
        queue.enqueue(device: device(), results: [result(.osPatched, .fail)])
        let other = DeviceInfo(deviceID: UUID(), platform: .mac, enrolledOn: day, catalogVersion: 1, appBuild: 1, lastReport: day)
        queue.enqueue(device: other, results: [])
        XCTAssertEqual(queue.pending?.device.deviceID, other.deviceID)
        XCTAssertEqual(queue.pending?.results.isEmpty, true)
    }

    func testBackoffBookkeeping() {
        var queue = SyncQueue()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(queue.isDue(at: now))
        queue.enqueue(device: device(), results: [result(.osPatched, .fail)])
        XCTAssertEqual(queue.markFailed(retryAfter: nil, now: now), 60)
        XCTAssertFalse(queue.isDue(at: now.addingTimeInterval(59)))
        XCTAssertTrue(queue.isDue(at: now.addingTimeInterval(60)))
        XCTAssertEqual(queue.markFailed(retryAfter: nil, now: now), 120)
        XCTAssertEqual(queue.markFailed(retryAfter: 7, now: now), 7)
        XCTAssertEqual(queue.consecutiveFailures, 3)
        XCTAssertEqual(queue.nextAttempt, now.addingTimeInterval(7))
        XCTAssertEqual(queue.markFailed(retryAfter: nil, now: now), 480, "exponent keeps counting")
    }

    func testSuccessClearsOnlyTheBatchThatWasSent() {
        var queue = SyncQueue()
        queue.enqueue(device: device(), results: [result(.osPatched, .fail)])
        let sent = queue.pending!
        queue.markFailed(retryAfter: nil, now: Date())
        // A newer state arrives while the write is in flight.
        queue.enqueue(device: device(), results: [result(.osPatched, .pass)])
        XCTAssertFalse(queue.markSucceeded(sent: sent))
        XCTAssertEqual(queue.pending?.results[.osPatched]?.status, .pass, "newer state still queued")
        XCTAssertEqual(queue.consecutiveFailures, 0)
        XCTAssertNil(queue.nextAttempt)
        XCTAssertTrue(queue.markSucceeded(sent: queue.pending!))
        XCTAssertTrue(queue.isEmpty)
    }

    func testFreshAttemptSkipsOurBackoffButNotTheServers() {
        var queue = SyncQueue()
        let now = Date(timeIntervalSince1970: 1_000_000)
        queue.enqueue(device: device(), results: [result(.osPatched, .fail)])
        queue.markFailed(retryAfter: nil, now: now)
        queue.markFailed(retryAfter: nil, now: now)
        XCTAssertFalse(queue.isDue(at: now.addingTimeInterval(60)))
        queue.allowFreshAttempt(at: now.addingTimeInterval(60))
        XCTAssertTrue(queue.isDue(at: now.addingTimeInterval(60)), "a new report goes out now")
        XCTAssertEqual(queue.consecutiveFailures, 2, "the timer keeps backing off")

        queue.markFailed(retryAfter: 300, now: now)
        queue.allowFreshAttempt(at: now.addingTimeInterval(10))
        XCTAssertFalse(queue.isDue(at: now.addingTimeInterval(10)), "the server's retryAfterSeconds still holds")
        queue.allowFreshAttempt(at: now.addingTimeInterval(301))
        XCTAssertTrue(queue.isDue(at: now.addingTimeInterval(301)))
    }

    func testClear() {
        var queue = SyncQueue()
        queue.enqueue(device: device(), results: [result(.osPatched, .fail)])
        queue.markFailed(retryAfter: nil, now: Date())
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.consecutiveFailures, 0)
    }
}

final class SyncFailureTests: XCTestCase {
    func testTransientCodes() {
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
                     .zoneBusy, .accountTemporarilyUnavailable, .internalError] {
            XCTAssertEqual(SyncFailure.classify(CKError(code)), .transient(retryAfter: nil), "\(code.rawValue)")
        }
        let limited = CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 42.0])
        XCTAssertEqual(SyncFailure.classify(limited), .transient(retryAfter: 42))
        XCTAssertEqual(SyncFailure.classify(URLError(.notConnectedToInternet)), .transient(retryAfter: nil))
    }

    func testSignedOutAndStorageFullNeedAPerson() {
        // No timer fixes these: retried like transient, but said in About (not "Connected").
        for code in [CKError.Code.notAuthenticated, .quotaExceeded] {
            let failure = SyncFailure.classify(CKError(code))
            XCTAssertEqual(failure, .accountBlocked(code: code.rawValue, retryAfter: nil), "\(code.rawValue)")
            XCTAssertTrue(failure.isRetryable)
        }
        XCTAssertEqual(SyncFailure.worst([.transient(retryAfter: 5), .accountBlocked(code: 25, retryAfter: nil)]),
                       .accountBlocked(code: 25, retryAfter: 5))
        XCTAssertEqual(SyncFailure.worst([.accountBlocked(code: 25, retryAfter: nil), .notConnected]), .notConnected)
        XCTAssertFalse(SyncFailure.permanent(code: 12).isRetryable)
    }

    func testNotConnectedCodes() {
        for code in [CKError.Code.zoneNotFound, .userDeletedZone, .participantMayNeedVerification, .permissionFailure] {
            XCTAssertEqual(SyncFailure.classify(CKError(code)), .notConnected, "\(code.rawValue)")
        }
    }

    func testPermanentCodesAreNotRetried() {
        for code in [CKError.Code.invalidArguments, .serverRejectedRequest, .missingEntitlement, .badContainer,
                     .badDatabase, .incompatibleVersion, .constraintViolation, .managedAccountRestricted, .limitExceeded] {
            XCTAssertEqual(SyncFailure.classify(CKError(code)), .permanent(code: code.rawValue), "\(code.rawValue)")
        }
        XCTAssertEqual(SyncFailure.worst([.permanent(code: 12), .transient(retryAfter: nil)]), .transient(retryAfter: nil),
                       "a transient item may still go through")
        XCTAssertEqual(SyncFailure.worst([.alreadyGone, .permanent(code: 12)]), .permanent(code: 12))
        XCTAssertEqual(SyncFailure.worst([.permanent(code: 12), .notConnected]), .notConnected)
    }

    func testOtherCodes() {
        XCTAssertEqual(SyncFailure.classify(CKError(.serverRecordChanged)), .serverRecordChanged)
        XCTAssertEqual(SyncFailure.classify(CKError(.unknownItem)), .alreadyGone)
        XCTAssertEqual(SyncFailure.classify(CKError(.changeTokenExpired)), .changeTokenExpired)
    }

    func testPartialFailureTakesTheWorstItem() {
        let id1 = CKRecord.ID(recordName: "a")
        let id2 = CKRecord.ID(recordName: "b")
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [
            id1: CKError(.serverRecordChanged),
            id2: CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 9.0]),
        ]])
        XCTAssertEqual(SyncFailure.classify(partial), .transient(retryAfter: 9))
        let gone = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [
            id1: CKError(.networkFailure), id2: CKError(.zoneNotFound),
        ]])
        XCTAssertEqual(SyncFailure.classify(gone), .notConnected)
    }

    func testWorst() {
        XCTAssertNil(SyncFailure.worst([]))
        XCTAssertEqual(SyncFailure.worst([.alreadyGone, .serverRecordChanged]), .serverRecordChanged)
        XCTAssertEqual(SyncFailure.worst([.transient(retryAfter: 5), .transient(retryAfter: 50)]), .transient(retryAfter: 50))
    }
}
