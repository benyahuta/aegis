// How Family Shield reacts to a CloudKit error (SPEC §8.4 "Errors").

import CloudKit
import Foundation

/// The reaction class for a CloudKit error.
public enum SyncFailure: Sendable, Equatable {
    /// Network down, service unavailable, rate limited, account busy for a moment…
    /// Queue the latest state and retry (`retryAfterSeconds`, or exponential backoff).
    case transient(retryAfter: TimeInterval?)
    /// The iCloud account can't take the write until a PERSON fixes it: signed out of iCloud
    /// (`.notAuthenticated`), or the storage it counts against is full (`.quotaExceeded`; shared
    /// zone records count against Ben's quota). Retried like `transient`, but no timer fixes it,
    /// so About says "Not reaching Ben right now" instead of "Connected to Ben".
    case accountBlocked(code: Int, retryAfter: TimeInterval?)
    /// Zone or share gone, or this person is no longer a participant: show "Not connected to
    /// Ben" and keep working locally.
    case notConnected
    /// Another copy of the record is on the server. This device is the only author, so we
    /// overwrite it with ours.
    case serverRecordChanged
    /// The record is already gone (fine when deleting).
    case alreadyGone
    /// The cached change token is no longer valid: refetch the zone from scratch.
    case changeTokenExpired
    /// The server refuses the request and will keep refusing it (schema not deployed to
    /// Production, wrong container or entitlement, invalid arguments, an app too old for the
    /// server…). Retrying on a timer can't help; the state stays queued for the next report, and
    /// the person sees that results aren't reaching Ben. `code` is the `CKError.Code` raw value.
    case permanent(code: Int)

    /// Codes that need the person (or Ben) to act: sign in to iCloud, free up iCloud storage.
    public static let accountBlockedCodes: Set<CKError.Code> = [.notAuthenticated, .quotaExceeded]

    /// Codes that no retry can fix.
    public static let permanentCodes: Set<CKError.Code> = [
        .invalidArguments, .serverRejectedRequest, .missingEntitlement, .badContainer, .badDatabase,
        .incompatibleVersion, .constraintViolation, .managedAccountRestricted, .limitExceeded,
    ]

    /// Classifies any error. Unknown errors are treated as transient: the state stays queued and
    /// is retried with backoff, never dropped and never reported as delivered.
    public static func classify(_ error: any Error) -> SyncFailure {
        guard let ckError = error as? CKError else {
            return .transient(retryAfter: nil)
        }
        switch ckError.code {
        case .zoneNotFound, .userDeletedZone, .participantMayNeedVerification, .permissionFailure:
            return .notConnected
        case .serverRecordChanged:
            return .serverRecordChanged
        case .unknownItem:
            return .alreadyGone
        case .changeTokenExpired:
            return .changeTokenExpired
        case let code where permanentCodes.contains(code):
            return .permanent(code: code.rawValue)
        case let code where accountBlockedCodes.contains(code):
            return .accountBlocked(code: code.rawValue, retryAfter: ckError.retryAfterSeconds)
        case .partialFailure:
            let itemErrors = (ckError.partialErrorsByItemID ?? [:]).values.map { classify($0) }
            return worst(itemErrors) ?? .transient(retryAfter: ckError.retryAfterSeconds)
        default:
            // .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
            // .zoneBusy, .accountTemporarilyUnavailable, …
            return .transient(retryAfter: ckError.retryAfterSeconds)
        }
    }

    /// The failure that decides what to do for a batch: notConnected beats accountBlocked beats
    /// transient beats permanent beats the rest (a transient item may still go through on a
    /// retry; a batch that only fails permanently is not retried; an account problem is said
    /// even when other items only failed for a moment). A conflict or already-gone item alone is
    /// not a reason to retry.
    public static func worst(_ failures: [SyncFailure]) -> SyncFailure? {
        if failures.contains(.notConnected) { return .notConnected }
        var longestRetry: TimeInterval?
        var sawTransient = false
        var blockedCode: Int?
        for failure in failures {
            switch failure {
            case .transient(let retryAfter):
                sawTransient = true
                if let retryAfter { longestRetry = max(longestRetry ?? 0, retryAfter) }
            case .accountBlocked(let code, let retryAfter):
                blockedCode = blockedCode ?? code
                if let retryAfter { longestRetry = max(longestRetry ?? 0, retryAfter) }
            default:
                break
            }
        }
        if let blockedCode { return .accountBlocked(code: blockedCode, retryAfter: longestRetry) }
        if sawTransient { return .transient(retryAfter: longestRetry) }
        for case let .permanent(code) in failures { return .permanent(code: code) }
        if failures.contains(.changeTokenExpired) { return .changeTokenExpired }
        if failures.contains(.serverRecordChanged) { return .serverRecordChanged }
        if failures.contains(.alreadyGone) { return .alreadyGone }
        return nil
    }

    /// True for failures that are retried later (`transient`, `accountBlocked`).
    public var isRetryable: Bool {
        switch self {
        case .transient, .accountBlocked: true
        default: false
        }
    }
}
