// Small protocols in front of CloudKit, so CloudKitSink and OwnerStore are unit-testable without
// iCloud. `LiveCloudContainer` (LiveCloudKit.swift) talks to CloudKit; `InMemoryCloudContainer`
// (InMemoryCloudDatabase.swift) is the test/demo double. Values crossing these protocols are
// CKRecord / CKRecordZone.ID (constructible offline) plus plain data.

import CloudKit
import Foundation

/// The per-database operations Family Shield needs.
/// How soon CloudKit should run a database call. CloudKit treats `.default` and lower QoS as
/// discretionary: the system may hold such work for battery, and on iPhone it pauses in Low Power
/// Mode. Anything a person is waiting on must be `.interactive`.
public enum CloudPriority: Sendable, Hashable {
    /// `.userInitiated`: share acceptance, enroll, leave, start a family, add a person, the
    /// Family tab fetch. The default.
    case interactive
    /// `.utility`: the periodic report and its retries (§8.4).
    case background
}

public protocol CloudDatabase: Sendable {
    /// The same database, running its calls at `priority` (the default is `.interactive`).
    func withPriority(_ priority: CloudPriority) -> any CloudDatabase

    /// One `CKModifyRecordsOperation` at this database's priority. Per-record failures come
    /// back in the result; only a whole-operation failure throws.
    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> ModifyRecordsResult

    /// Creates (or keeps) these zones.
    func saveZones(_ zones: [CKRecordZone]) async throws

    /// Deletes these zones. In the shared database this leaves the share.
    func deleteZones(_ zoneIDs: [CKRecordZone.ID]) async throws

    /// Every zone in this database.
    func allZoneIDs() async throws -> [CKRecordZone.ID]

    /// One `CKFetchRecordZoneChangesOperation` over `zoneIDs`, each starting at its cached token
    /// (archived `CKServerChangeToken`; nil fetches everything). Per-zone failures (for example
    /// `.changeTokenExpired`, `.zoneNotFound`) come back in the result.
    func fetchChanges(
        in zoneIDs: [CKRecordZone.ID],
        since tokens: [CKRecordZone.ID: Data]
    ) async throws -> [CKRecordZone.ID: ZoneChanges]
}

/// The container: the two databases Family Shield uses, plus share acceptance.
public protocol CloudContainer: Sendable {
    var privateDatabase: any CloudDatabase { get }
    var sharedDatabase: any CloudDatabase { get }
    /// `CKAcceptSharesOperation` for a share link the person tapped. Returns the shared zone.
    func acceptShare(_ metadata: CKShare.Metadata) async throws -> CKRecordZone.ID
}

/// Per-record outcome of a modify operation.
public struct ModifyRecordsResult: Sendable {
    /// Saved records as the server returned them.
    public var saved: [CKRecord.ID: CKRecord]
    public var deleted: Set<CKRecord.ID>
    /// Per-record failures (save or delete).
    public var failures: [CKRecord.ID: CKError]

    public init(saved: [CKRecord.ID: CKRecord] = [:], deleted: Set<CKRecord.ID> = [],
                failures: [CKRecord.ID: CKError] = [:]) {
        self.saved = saved
        self.deleted = deleted
        self.failures = failures
    }
}

/// A record fetched from the server, with the server-side metadata Ben's dashboard needs.
public struct FetchedRecord: Sendable {
    public var record: CKRecord
    /// `creatorUserRecordID.recordName` (§8.3 creator-mismatch flag).
    public var creatorRecordName: String?
    /// `lastModifiedUserRecordID.recordName`.
    public var lastModifierRecordName: String?
    /// For a zone-wide `CKShare` record only: the first non-owner participant's name, if the
    /// system knows it (the `PersonLabel` default, §8.4).
    public var participantName: PersonNameComponents?
    /// For a zone-wide `CKShare` record only: whether that participant has accepted.
    public var participantAccepted: Bool?

    public init(record: CKRecord, creatorRecordName: String? = nil, lastModifierRecordName: String? = nil,
                participantName: PersonNameComponents? = nil, participantAccepted: Bool? = nil) {
        self.record = record
        self.creatorRecordName = creatorRecordName
        self.lastModifierRecordName = lastModifierRecordName
        self.participantName = participantName
        self.participantAccepted = participantAccepted
    }
}

/// A deleted record seen in a zone-changes fetch.
public struct DeletedRecord: Sendable, Hashable {
    public var recordID: CKRecord.ID
    public var recordType: String

    public init(recordID: CKRecord.ID, recordType: String) {
        self.recordID = recordID
        self.recordType = recordType
    }
}

/// The changes in one zone since a token.
public struct ZoneChanges: Sendable {
    public var changed: [FetchedRecord]
    public var deleted: [DeletedRecord]
    /// The archived token to cache for the next fetch. Nil when the zone failed.
    public var newToken: Data?
    /// A per-zone failure, for example `.changeTokenExpired` or `.zoneNotFound`.
    public var failure: CKError?

    public init(changed: [FetchedRecord] = [], deleted: [DeletedRecord] = [], newToken: Data? = nil,
                failure: CKError? = nil) {
        self.changed = changed
        self.deleted = deleted
        self.newToken = newToken
        self.failure = failure
    }
}
