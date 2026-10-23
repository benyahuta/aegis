// SyncQueue (SPEC §8.4): when a report can't be written right now, keep only the LATEST state
// (last-state-wins per check ID) and retry with `retryAfterSeconds`, or exponential backoff from
// 1 minute to 6 hours. Older states are never replayed: the newest local evaluation is the truth.
//
// The queue is in memory. If the app quits with something queued, nothing is lost that matters:
// the next report (foreground, BGAppRefresh, Mac 24 h / wake) sends the current state again.

import Foundation

/// Exponential backoff: 60 s, 120 s, 240 s, … capped at 6 h. A server `retryAfterSeconds`
/// replaces the computed delay (still capped at 6 h).
public struct Backoff: Sendable, Hashable {
    public static let minimumDelay: TimeInterval = 60
    public static let maximumDelay: TimeInterval = 6 * 60 * 60

    public var base: TimeInterval
    public var cap: TimeInterval

    public init(base: TimeInterval = Backoff.minimumDelay, cap: TimeInterval = Backoff.maximumDelay) {
        self.base = base
        self.cap = cap
    }

    /// The delay after `failures` consecutive failures (1 = first failure).
    public func delay(afterFailures failures: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        if let retryAfter, retryAfter.isFinite, retryAfter > 0 {
            return min(retryAfter, cap)
        }
        let exponent = max(0, failures - 1)
        // 2^exponent overflows to inf for big exponents; min() then caps it.
        let delay = base * pow(2, Double(min(exponent, 62)))
        return min(delay, cap)
    }
}

/// The latest unsent report for this device.
public struct SyncBatch: Sendable, Hashable {
    public var device: DeviceInfo
    public var results: [CheckID: CheckResult]

    public init(device: DeviceInfo, results: [CheckID: CheckResult]) {
        self.device = device
        self.results = results
    }

    /// Results in a stable order (by wire value).
    public var sortedResults: [CheckResult] {
        results.values.sorted { $0.checkID.rawValue < $1.checkID.rawValue }
    }
}

/// Last-state-wins queue with backoff bookkeeping. A value type owned by `CloudKitSink`.
public struct SyncQueue: Sendable {
    public private(set) var pending: SyncBatch?
    public private(set) var consecutiveFailures = 0
    public private(set) var nextAttempt: Date?
    /// Until when the SERVER asked us to wait (`retryAfterSeconds`). Unlike our own backoff, a
    /// new report does not skip it.
    public private(set) var serverHoldUntil: Date?
    public let backoff: Backoff

    public init(backoff: Backoff = Backoff()) {
        self.backoff = backoff
    }

    public var isEmpty: Bool { pending == nil }

    /// Merges a new report into the pending one. The device info is replaced; results merge per
    /// check ID with the newest winning. A different device ID replaces the batch entirely.
    public mutating func enqueue(device: DeviceInfo, results: [CheckResult]) {
        var merged: [CheckID: CheckResult] = [:]
        if let pending, pending.device.deviceID == device.deviceID {
            merged = pending.results
        }
        for result in results {
            merged[result.checkID] = result
        }
        pending = SyncBatch(device: device, results: merged)
    }

    /// True when no backoff is in force at `now`.
    public func isDue(at now: Date) -> Bool {
        guard let nextAttempt else { return true }
        return now >= nextAttempt
    }

    /// Records a transient failure and returns the delay until the next attempt.
    @discardableResult
    public mutating func markFailed(retryAfter: TimeInterval?, now: Date) -> TimeInterval {
        consecutiveFailures += 1
        let delay = backoff.delay(afterFailures: consecutiveFailures, retryAfter: retryAfter)
        nextAttempt = now.addingTimeInterval(delay)
        if let retryAfter, retryAfter.isFinite, retryAfter > 0 {
            serverHoldUntil = nextAttempt
        } else {
            serverHoldUntil = nil
        }
        return delay
    }

    /// A NEW report (app foreground, a check changed, an answer) is a fresh attempt: our own
    /// exponential backoff only paces the timer retries, so it no longer holds this one back. A
    /// server's `retryAfterSeconds` still does. The failure count is kept, so the timer keeps
    /// backing off while the device stays offline.
    public mutating func allowFreshAttempt(at now: Date) {
        if let serverHoldUntil, now < serverHoldUntil { return }
        serverHoldUntil = nil
        nextAttempt = nil
    }

    /// Records a delivered batch. The pending batch is cleared only if nothing newer was merged
    /// in while the write was in flight. Returns true when the queue is now empty.
    @discardableResult
    public mutating func markSucceeded(sent: SyncBatch) -> Bool {
        consecutiveFailures = 0
        nextAttempt = nil
        serverHoldUntil = nil
        if pending == sent {
            pending = nil
        }
        return pending == nil
    }

    /// Clears the backoff (for example after the person re-joins) but keeps the pending batch.
    public mutating func resetBackoff() {
        consecutiveFailures = 0
        nextAttempt = nil
        serverHoldUntil = nil
    }

    /// Drops everything (after "Stop sharing with Ben").
    public mutating func clear() {
        pending = nil
        resetBackoff()
    }
}

/// Runs a retry later. Injected so tests can fire retries by hand.
public protocol RetryScheduler: Sendable {
    func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () async -> Void)
}

/// The live scheduler: a detached task that sleeps, then runs the work.
public struct TaskRetryScheduler: RetryScheduler {
    public init() {}

    public func schedule(after delay: TimeInterval, _ work: @escaping @Sendable () async -> Void) {
        Task.detached(priority: .utility) {
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await work()
        }
    }
}
