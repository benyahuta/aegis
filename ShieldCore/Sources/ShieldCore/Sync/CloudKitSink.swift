// CloudKitSink (SPEC §5.5, §8.4): writes this device's `Device` and `CheckResult` records.
//
// - Family device: into its person zone in the SHARED database (after accepting Ben's link).
// - Ben's own device: into `z_self` in his PRIVATE database.
//
// Rules:
// - Only §8.2 fields, only allowlisted check IDs, `checkedOn` at 00:00 UTC, record names that
//   match §8.3 (Records.swift + `validateForSink`).
// - Report: one `CKModifyRecordsOperation` with every current result plus `Device.lastReport`,
//   `savePolicy = .changedKeys`, `qualityOfService = .utility`, `isAtomic = false`. Everything
//   a person waits on (enroll, leave) runs `.userInitiated` (`CloudPriority.interactive`).
//   Skipped when nothing changed and `lastReport` is already today.
// - Transient errors → `SyncQueue` (last-state-wins) + retry after `retryAfterSeconds` or
//   exponential backoff (1 min … 6 h). Zone / share gone → "Not connected to Ben", keep working.
//   Errors no retry can fix (schema not in Production, bad container…) → kept for the next report,
//   no timer, "Not sending to Ben" in About, and the CKError code is logged.
// - A share link never silently re-targets an enrolled device: only a person-zone, zone-wide
//   share is accepted, and a device already reporting to Ben (or one of Ben's own) refuses others.
// - Right after accepting, the shared zone may still be materializing server-side
//   (CKAcceptSharesOperation docs): `.zoneNotFound` on the first `Device` save is retried briefly.
//   `.serverRecordChanged` → overwrite with ours (this device is the only author).
// - A device NEVER reads its own status back. This type has no read path for results.

import CloudKit
import CryptoKit
import Foundation

public actor CloudKitSink: ResultSink {
    private let container: any CloudContainer
    private let identity: any DeviceIdentityStore
    private let settings: SyncSettings
    private let clock: Clock
    private let scheduler: any RetryScheduler

    private let enrollSettleDelays: [TimeInterval]

    private var queue: SyncQueue
    private var isFlushing = false
    private var retryScheduled = false

    /// - Parameter enrollSettleDelays: waits between retries of the first `Device` save into a
    ///   just-accepted shared zone that the server reports as not found yet.
    public init(
        container: any CloudContainer,
        identity: any DeviceIdentityStore,
        settings: SyncSettings,
        clock: Clock = .system,
        scheduler: any RetryScheduler = TaskRetryScheduler(),
        backoff: Backoff = Backoff(),
        enrollSettleDelays: [TimeInterval] = [1, 2, 4]
    ) {
        self.container = container
        self.identity = identity
        self.settings = settings
        self.clock = clock
        self.scheduler = scheduler
        self.queue = SyncQueue(backoff: backoff)
        self.enrollSettleDelays = enrollSettleDelays
    }

    // MARK: State for the UI

    /// "Connected to Ben" / "Not connected" (About screen).
    public var connectionState: SyncConnectionState { settings.connection }

    /// The latest state still waiting to be delivered.
    public var pendingBatch: SyncBatch? { queue.pending }

    /// When the next automatic retry is due, if one is scheduled.
    public var nextRetryDate: Date? { queue.nextAttempt }

    // MARK: Enroll (§8.4)

    /// The share link was tapped: accept it, remember the zone, save the `Device` record.
    /// Throws `.invalidShare` / `.alreadyConnected` (nothing accepted) when `acceptance` refuses it.
    public func acceptShare(_ metadata: CKShare.Metadata, device: DeviceInfo) async throws {
        let shareID = metadata.share.recordID
        try acceptance(zoneID: shareID.zoneID, shareRecordName: shareID.recordName)
        let zoneID: CKRecordZone.ID
        do {
            zoneID = try await container.acceptShare(metadata)
        } catch {
            Log.sync.error("share.accept.failed code=\(Self.errorCode(error), privacy: .public)")
            throw Self.sinkError(for: SyncFailure.classify(error))
        }
        guard Records.isPersonZoneName(zoneID.zoneName) else { throw ResultSinkError.invalidShare }
        try await enroll(zoneID: zoneID, device: device)
    }

    /// Whether a share for `zoneID` may (re)target this device. Only a zone-wide share of a person
    /// zone is accepted. Re-accepting the zone this device already uses is fine; a different one
    /// is refused while this device reports to Ben (or is one of Ben's own devices), so a link
    /// can never silently move a device's reports elsewhere. A device whose share is gone
    /// ("Not connected to Ben") may join again.
    public func acceptance(zoneID: CKRecordZone.ID, shareRecordName: String) throws(ResultSinkError) {
        guard Records.isPersonZoneName(zoneID.zoneName), shareRecordName == CKRecordNameZoneWideShare else {
            Log.sync.notice("share.refused reason=invalid")
            throw .invalidShare
        }
        if settings.isOwner || settings.target?.kind == .ownerSelf {
            Log.sync.notice("share.refused reason=owner")
            throw .alreadyConnected
        }
        guard let current = settings.target, current != .shared(zoneID) else { return }
        switch settings.connection {
        case .connected, .notDelivering:
            Log.sync.notice("share.refused reason=alreadyConnected")
            throw .alreadyConnected
        case .notConnected, .notJoined:
            return
        }
    }

    /// Records the accepted zone and saves `Device` with `.allKeys` into the shared database.
    public func enroll(zoneID: CKRecordZone.ID, device: DeviceInfo) async throws {
        try await enroll(target: .shared(zoneID), device: device)
    }

    /// Ben's own device: write into `z_self` in the private database (OwnerStore sets this up).
    public func enrollAsOwnerDevice(device: DeviceInfo) async throws {
        try await enroll(target: .ownerSelf, device: device)
    }

    private func enroll(target: SyncTarget, device: DeviceInfo) async throws {
        try checkIdentity(device.deviceID)
        settings.target = target
        settings.connection = .connected
        settings.lastSent = nil
        queue.resetBackoff()
        Log.sync.info("enroll kind=\(target.kind.rawValue, privacy: .public)")

        var enrolled = device
        enrolled.lastReport = clock.today()
        let record = Records.record(for: enrolled, in: target.zoneID)
        var settleAttempt = 0
        while true {
            do {
                let result = try await database(for: target).modifyRecords(
                    saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
                if let error = result.failures[record.recordID] {
                    if await settle(after: error, target: target, attempt: &settleAttempt) { continue }
                    try await handleEnrollFailure(error, record: record, target: target, device: enrolled)
                }
            } catch let error as ResultSinkError {
                throw error
            } catch {
                if await settle(after: error, target: target, attempt: &settleAttempt) { continue }
                try handle(failure: SyncFailure.classify(error), device: enrolled, results: [])
            }
            break
        }
        // Deliver any report that was waiting for the share.
        if !queue.isEmpty {
            try await flush()
        }
    }

    /// True (after waiting) when a `Device` save into a just-joined shared zone failed only because
    /// the zone is not there yet and another try is allowed.
    private func settle(after error: any Error, target: SyncTarget, attempt: inout Int) async -> Bool {
        guard target.kind == .sharedZone, Self.isZoneMissing(error), attempt < enrollSettleDelays.count else {
            return false
        }
        let delay = enrollSettleDelays[attempt]
        attempt += 1
        let number = attempt
        Log.sync.notice("enroll.zoneNotReady attempt=\(number, privacy: .public)")
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        return true
    }

    static func isZoneMissing(_ error: any Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .zoneNotFound { return true }
        if ckError.code == .partialFailure {
            return (ckError.partialErrorsByItemID ?? [:]).values.contains { ($0 as? CKError)?.code == .zoneNotFound }
        }
        return false
    }

    private func handleEnrollFailure(_ error: CKError, record: CKRecord, target: SyncTarget, device: DeviceInfo) async throws {
        let failure = SyncFailure.classify(error)
        if failure == .serverRecordChanged, let server = error.serverRecord {
            // Re-enrolling an existing device: overwrite with ours.
            let merged = Records.overwrite(server, with: record)
            do {
                let retry = try await database(for: target).modifyRecords(
                    saving: [merged], deleting: [], savePolicy: .allKeys, atomically: false)
                if let again = retry.failures[merged.recordID] {
                    try handle(failure: SyncFailure.classify(again), device: device, results: [])
                }
            } catch {
                try handle(failure: SyncFailure.classify(error), device: device, results: [])
            }
            return
        }
        try handle(failure: failure, device: device, results: [])
    }

    // MARK: Report (ResultSink)

    /// Queues the latest state and tries to deliver it now. A new report is a fresh attempt: our
    /// own backoff from earlier failures doesn't hold it back (a server `retryAfterSeconds` does).
    /// Throws `.unavailable` when it was queued for a retry (it will be delivered later),
    /// `.notConnected` when there is no share (or it is gone), `.deviceMismatch` /
    /// `.invalidRecordName` for payloads that break §8.3.
    public func upsert(device: DeviceInfo, results: [CheckResult]) async throws {
        try validateForSink(device: device, results: results)
        try checkIdentity(device.deviceID)
        queue.enqueue(device: device, results: results)
        queue.allowFreshAttempt(at: clock.now())
        try await flush()
    }

    /// Delivers whatever is queued now, ignoring backoff (for example on app foreground).
    public func flushPending() async throws {
        queue.resetBackoff()
        try await flush()
    }

    private func flush() async throws {
        // A flush already in flight picks up the merged state when it finishes.
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        var rounds = 0
        while let batch = queue.pending, rounds < 3 {
            rounds += 1
            guard let target = settings.target else {
                throw ResultSinkError.notConnected
            }
            guard queue.isDue(at: clock.now()) else {
                throw ResultSinkError.unavailable
            }
            let today = clock.today()
            let fingerprint = Self.fingerprint(batch)
            if let last = settings.lastSent, last.fingerprint == fingerprint, last.day == today, last.target == target {
                Log.sync.debug("report.skip unchanged")
                queue.markSucceeded(sent: batch)
                continue
            }
            try await send(batch, to: target, today: today)
            settings.lastSent = SyncSettings.LastSent(fingerprint: fingerprint, day: today, target: target)
            settings.connection = .connected
            queue.markSucceeded(sent: batch)
            Log.sync.info("report.sent count=\(batch.results.count, privacy: .public)")
        }
    }

    /// One modify operation for the batch. Throws a `ResultSinkError` after handling.
    private func send(_ batch: SyncBatch, to target: SyncTarget, today: DateDay) async throws {
        var device = batch.device
        device.lastReport = today
        let zoneID = target.zoneID
        var records = [Records.record(for: device, in: zoneID)]
        for result in batch.sortedResults {
            records.append(try Records.record(for: result, in: zoneID))
        }
        // The periodic report is the one discretionary write (§8.4 `.utility`); enroll and leave
        // are awaited by the person and run `.userInitiated`.
        let database = database(for: target).withPriority(.background)

        let outcome: ModifyRecordsResult
        do {
            outcome = try await database.modifyRecords(saving: records, deleting: [],
                                                       savePolicy: .changedKeys, atomically: false)
        } catch {
            try handle(failure: SyncFailure.classify(error), device: batch.device, results: [])
            return
        }
        guard !outcome.failures.isEmpty else { return }

        // `.serverRecordChanged`: this device is the only author, so overwrite with ours (once).
        var conflictRetries: [CKRecord] = []
        var otherFailures: [SyncFailure] = []
        let byID = Dictionary(records.map { ($0.recordID, $0) }, uniquingKeysWith: { $1 })
        for (id, error) in outcome.failures {
            let failure = SyncFailure.classify(error)
            if failure == .serverRecordChanged, let server = error.serverRecord, let ours = byID[id] {
                conflictRetries.append(Records.overwrite(server, with: ours))
            } else {
                otherFailures.append(failure)
            }
        }
        if !conflictRetries.isEmpty {
            Log.sync.info("report.overwrite count=\(conflictRetries.count, privacy: .public)")
            do {
                let retry = try await database.modifyRecords(saving: conflictRetries, deleting: [],
                                                             savePolicy: .allKeys, atomically: false)
                otherFailures += retry.failures.values.map { error in
                    // A second conflict in a row is retried later like a transient error.
                    let failure = SyncFailure.classify(error)
                    return failure == .serverRecordChanged ? .transient(retryAfter: nil) : failure
                }
            } catch {
                otherFailures.append(SyncFailure.classify(error))
            }
        }
        if let worst = SyncFailure.worst(otherFailures) {
            try handle(failure: worst, device: batch.device, results: [])
        }
    }

    /// Applies the §8.4 reaction and throws the matching `ResultSinkError`.
    /// Returns normally only for failures that need no action.
    private func handle(failure: SyncFailure, device: DeviceInfo, results: [CheckResult]) throws {
        switch failure {
        case .transient(let retryAfter):
            try queueForRetry(device: device, results: results, retryAfter: retryAfter)
        case .accountBlocked(let code, let retryAfter):
            // Signed out of iCloud, or the iCloud storage is full: keep retrying, but don't
            // keep saying "Connected to Ben" while nothing arrives. The next delivery that
            // works sets `.connected` again.
            Log.sync.error("sync.accountBlocked code=\(code, privacy: .public)")
            if settings.connection == .connected { settings.connection = .notDelivering }
            try queueForRetry(device: device, results: results, retryAfter: retryAfter)
        case .notConnected:
            if settings.connection != .notConnected {
                Log.sync.notice("sync.notConnected")
            }
            settings.connection = .notConnected
            queue.resetBackoff()
            throw ResultSinkError.notConnected
        case .serverRecordChanged, .changeTokenExpired:
            // Not expected for a write; retry later rather than report delivery.
            try handle(failure: .transient(retryAfter: nil), device: device, results: results)
        case .permanent(let code):
            // No timer can fix this. Keep the latest state for the next report (a fixed server
            // then gets it) and tell the person their results aren't reaching Ben.
            Log.sync.error("sync.rejected code=\(code, privacy: .public)")
            if queue.pending == nil || queue.pending?.device.deviceID != device.deviceID {
                queue.enqueue(device: device, results: results)
            }
            queue.resetBackoff()
            settings.connection = .notDelivering
            throw ResultSinkError.rejected
        case .alreadyGone:
            return
        }
    }

    private func queueForRetry(device: DeviceInfo, results: [CheckResult], retryAfter: TimeInterval?) throws -> Never {
        if queue.pending == nil || queue.pending?.device.deviceID != device.deviceID {
            queue.enqueue(device: device, results: results)
        }
        let delay = queue.markFailed(retryAfter: retryAfter, now: clock.now())
        Log.sync.notice("sync.queued delay=\(Int(delay), privacy: .public)")
        scheduleRetry(after: delay)
        throw ResultSinkError.unavailable
    }

    private func scheduleRetry(after delay: TimeInterval) {
        guard !retryScheduled else { return }
        retryScheduled = true
        scheduler.schedule(after: delay) { [weak self] in
            await self?.runScheduledRetry()
        }
    }

    /// Called by the scheduler.
    func runScheduledRetry() async {
        retryScheduled = false
        guard !queue.isEmpty, settings.connection != .notConnected else { return }
        do {
            try await flush()
        } catch {
            // `flush` already re-queued and re-scheduled transient failures.
        }
    }

    // MARK: Leave (§8.4)

    /// "Stop sharing with Ben": delete this device's `Device` and `CheckResult` records, then
    /// leave the share by deleting the shared zone from the shared database.
    /// Throws `.unavailable` (nothing changed locally) if CloudKit can't be reached.
    public func leave() async throws {
        defer { Log.sync.info("leave") }
        guard let target = settings.target else {
            resetLocalState()
            return
        }
        let deviceID: UUID
        do {
            deviceID = try identity.deviceID()
        } catch {
            throw ResultSinkError.unavailable
        }
        let zoneID = target.zoneID
        let ids = [CKRecord.ID(recordName: Records.deviceRecordName(deviceID), zoneID: zoneID)]
            + CheckID.allCases.map {
                CKRecord.ID(recordName: CheckResult.recordName(deviceID: deviceID, checkID: $0), zoneID: zoneID)
            }
        let database = database(for: target)
        do {
            let outcome = try await database.modifyRecords(saving: [], deleting: ids,
                                                           savePolicy: .changedKeys, atomically: false)
            let failures = outcome.failures.values.map { SyncFailure.classify($0) }
            if SyncFailure.worst(failures)?.isRetryable == true {
                throw ResultSinkError.unavailable
            }
        } catch let error as ResultSinkError {
            throw error
        } catch {
            if SyncFailure.classify(error).isRetryable { throw ResultSinkError.unavailable }
            // Zone already gone: nothing left to delete.
        }
        if target.kind == .sharedZone {
            do {
                try await database.deleteZones([zoneID])
            } catch {
                if SyncFailure.classify(error).isRetryable { throw ResultSinkError.unavailable }
            }
        }
        resetLocalState()
    }

    private func resetLocalState() {
        settings.target = nil
        settings.lastSent = nil
        settings.connection = .notJoined
        queue.clear()
    }

    // MARK: Helpers

    private func database(for target: SyncTarget) -> any CloudDatabase {
        switch target.kind {
        case .sharedZone: container.sharedDatabase
        case .ownerSelf: container.privateDatabase
        }
    }

    private func checkIdentity(_ deviceID: UUID) throws {
        let stored: UUID
        do {
            stored = try identity.deviceID()
        } catch {
            Log.sync.error("device.id.unavailable")
            throw ResultSinkError.unavailable
        }
        guard stored == deviceID else { throw ResultSinkError.deviceMismatch }
    }

    static func sinkError(for failure: SyncFailure) -> ResultSinkError {
        switch failure {
        case .notConnected: .notConnected
        case .permanent: .rejected
        default: .unavailable
        }
    }

    /// The `CKError.Code` raw value for logs (an enum value, never content; §5.6), or -1.
    static func errorCode(_ error: any Error) -> Int {
        (error as? CKError)?.code.rawValue ?? -1
    }

    /// A digest of everything in the batch except `lastReport` (which changes every day).
    static func fingerprint(_ batch: SyncBatch) -> String {
        var device = batch.device
        device.lastReport = DateDay(daysSinceEpoch: 0)
        struct Canonical: Encodable {
            let device: DeviceInfo
            let results: [CheckResult]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(Canonical(device: device, results: batch.sortedResults))) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
