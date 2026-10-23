// SHARED CONTRACT (scaffold). Every builder depends on this file.
// Where a device's results go (SPEC §5.5). `CloudKitSink` (Sync builder) and the fallback
// `SupabaseSink` (§9) implement this. `InMemoryResultSink` is used for `-FSNoCloud`,
// `-FSDemoState`, unsigned builds, previews and tests, so the app never needs CloudKit to run.
//
// A device never reads its own status back from a sink (§8.4). Local evaluation is the truth.

import Foundation

public protocol ResultSink: Sendable {
    /// Upserts this device's `Device` record and the given `CheckResult`s (last state wins).
    func upsert(device: DeviceInfo, results: [CheckResult]) async throws
    /// "Stop sharing with Ben": deletes this device's records and leaves the share.
    func leave() async throws
}

public enum ResultSinkError: Error, Sendable, Equatable {
    /// A result's `deviceID` differs from the device being upserted.
    case deviceMismatch
    /// A record name failed the §8.3 pattern.
    case invalidRecordName
    /// Zone or share is gone: show "Not connected to Ben" and keep working locally (§8.4).
    case notConnected
    /// Temporarily unavailable (network, rate limit, no iCloud account): queue and retry.
    case unavailable
    /// The server refuses the records and will keep refusing them (`SyncFailure.permanent`):
    /// kept for the next report, not retried on a timer.
    case rejected
    /// Share link refused: this device already reports to Ben (a different zone, or it is one of
    /// Ben's own devices). "Stop sharing with Ben" first.
    case alreadyConnected
    /// Share link refused: not a Family Shield person-zone share.
    case invalidShare
}

/// Checks the §8.3 client-side rules every sink must enforce before writing.
/// (Status, source and check ID are typed, so only the cross-field rules remain.)
public func validateForSink(device: DeviceInfo, results: [CheckResult]) throws(ResultSinkError) {
    for result in results {
        guard result.deviceID == device.deviceID else { throw .deviceMismatch }
        guard CheckResult.isValidRecordName(result.recordName) else { throw .invalidRecordName }
    }
}

/// An in-memory sink. Nothing leaves the process.
public actor InMemoryResultSink: ResultSink {
    public private(set) var devices: [UUID: DeviceInfo] = [:]
    public private(set) var results: [UUID: [CheckID: CheckResult]] = [:]
    public private(set) var upsertCount = 0
    public private(set) var leaveCount = 0
    private var queuedError: ResultSinkError?

    public init() {}

    /// Makes the next `upsert` or `leave` throw `error` (for tests of error handling).
    public func failNext(with error: ResultSinkError) {
        queuedError = error
    }

    public func upsert(device: DeviceInfo, results newResults: [CheckResult]) async throws {
        if let error = queuedError {
            queuedError = nil
            throw error
        }
        try validateForSink(device: device, results: newResults)
        devices[device.deviceID] = device
        var current = results[device.deviceID] ?? [:]
        for result in newResults {
            current[result.checkID] = result
        }
        results[device.deviceID] = current
        upsertCount += 1
    }

    public func leave() async throws {
        if let error = queuedError {
            queuedError = nil
            throw error
        }
        devices.removeAll()
        results.removeAll()
        leaveCount += 1
    }

    /// The stored results for one device, sorted by check ID wire value.
    public func results(for deviceID: UUID) -> [CheckResult] {
        (results[deviceID] ?? [:]).values.sorted { $0.checkID.rawValue < $1.checkID.rawValue }
    }
}
