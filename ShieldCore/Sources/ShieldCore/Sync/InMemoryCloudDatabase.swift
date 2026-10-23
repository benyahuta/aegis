// An in-memory stand-in for CloudKit, for unit tests and `-FSDemoState` dashboards.
// It models one container: zones live in the owner's (Ben's) private database, and family
// members see the same zones through their shared database. It tracks creators, change tokens
// and deletions, and lets tests inject CloudKit errors. Nothing leaves the process.

import CloudKit
import Foundation

/// The shared backing store. Make one, then hand out views with `container(actingAs:)`.
public actor InMemoryCloudBackend {
    /// The owner's record name as other participants see it.
    public static let ownerRecordName = CKCurrentUserDefaultName

    struct StoredRecord {
        var record: CKRecord
        var creator: String
        var modifier: String
        var sequence: Int
    }

    struct ZoneState {
        var records: [String: StoredRecord] = [:]
        var deletions: [(sequence: Int, deleted: DeletedRecord)] = []
        var sequence = 0
        /// Participants (by acting user name) that left this zone through their shared DB.
        var leftBy: Set<String> = []
    }

    private var zones: [String: ZoneState] = [:]
    private var participantNames: [String: PersonNameComponents] = [:]
    private var participantAccepted: [String: Bool] = [:]
    private var expiredTokensBefore: [String: Int] = [:]
    private var tokenEpoch = 0

    private var nextModifyErrors: [CKError] = []
    private var nextFetchErrors: [CKError] = []
    private var recordErrors: [String: [CKError]] = [:]
    private var zoneFetchErrors: [String: [CKError]] = [:]
    private var numberedFetchErrors: [Int: CKError] = [:]

    /// Every modify call, for assertions.
    public private(set) var modifyLog: [ModifyCall] = []
    public private(set) var fetchCount = 0

    public struct ModifyCall: Sendable {
        public var scope: CKDatabase.Scope
        public var savedRecordNames: [String]
        public var deletedRecordNames: [String]
        public var savePolicy: CKModifyRecordsOperation.RecordSavePolicy
        public var atomically: Bool
        public var savedKeys: [String: Set<String>]
        /// The `CloudPriority` the caller asked for.
        public var priority: CloudPriority = .interactive
    }

    public init() {}

    // MARK: Views

    /// A container as seen by `userRecordName` (`ownerRecordName` for Ben).
    public nonisolated func container(actingAs userRecordName: String = InMemoryCloudBackend.ownerRecordName) -> InMemoryCloudContainer {
        InMemoryCloudContainer(backend: self, user: userRecordName)
    }

    // MARK: Test hooks

    public func failNextModify(with error: CKError) { nextModifyErrors.append(error) }
    public func failNextFetch(with error: CKError) { nextFetchErrors.append(error) }
    /// The next save or delete of this record name fails with `error` (repeatable).
    public func failRecord(named name: String, with error: CKError, times: Int = 1) {
        recordErrors[name, default: []].append(contentsOf: Array(repeating: error, count: times))
    }
    /// The `number`th fetch-changes call (counting from 1, as `fetchCount` does) throws `error`.
    public func failFetch(number: Int, with error: CKError) { numberedFetchErrors[number] = error }
    public func failNextFetch(ofZone zoneName: String, with error: CKError) {
        zoneFetchErrors[zoneName, default: []].append(error)
    }
    /// Every token handed out so far becomes invalid (`.changeTokenExpired`).
    public func expireChangeTokens() {
        tokenEpoch += 1
    }
    public func setParticipant(zoneName: String, name: PersonNameComponents?, accepted: Bool) {
        participantNames[zoneName] = name
        participantAccepted[zoneName] = accepted
    }
    /// Deletes a zone server-side (as if Ben or the system removed it).
    public func removeZone(_ zoneName: String) { zones[zoneName] = nil }
    public func hasZone(_ zoneName: String) -> Bool { zones[zoneName] != nil }
    public func zoneNames() -> Set<String> { Set(zones.keys) }
    public func hasLeft(zoneName: String, user: String) -> Bool { zones[zoneName]?.leftBy.contains(user) ?? false }

    /// A stored record (a server copy that may be saved back with `.allKeys`), or nil.
    public func record(zoneName: String, recordName: String) -> CKRecord? {
        guard let stored = zones[zoneName]?.records[recordName] else { return nil }
        let copy = stored.record.copy() as! CKRecord
        serve(copy)
        return copy
    }
    public func recordNames(zoneName: String) -> Set<String> {
        Set(zones[zoneName]?.records.keys ?? [:].keys)
    }
    public func creator(zoneName: String, recordName: String) -> String? {
        zones[zoneName]?.records[recordName]?.creator
    }

    /// Writes a record directly, as `user` (seeding demo data or simulating another writer).
    public func put(_ record: CKRecord, as user: String) {
        let zoneName = record.recordID.zoneID.zoneName
        var zone = zones[zoneName] ?? ZoneState()
        zone.sequence += 1
        let name = record.recordID.recordName
        let creator = zone.records[name]?.creator ?? user
        zone.records[name] = StoredRecord(record: record.copy() as! CKRecord, creator: creator,
                                          modifier: user, sequence: zone.sequence)
        zones[zoneName] = zone
    }

    // MARK: Operations

    func modify(scope: CKDatabase.Scope, user: String, saving records: [CKRecord], deleting ids: [CKRecord.ID],
                savePolicy: CKModifyRecordsOperation.RecordSavePolicy, atomically: Bool,
                priority: CloudPriority = .interactive) throws -> ModifyRecordsResult {
        modifyLog.append(ModifyCall(
            scope: scope,
            savedRecordNames: records.map(\.recordID.recordName),
            deletedRecordNames: ids.map(\.recordName),
            savePolicy: savePolicy, atomically: atomically,
            savedKeys: Dictionary(records.map { ($0.recordID.recordName, Set($0.allKeys())) },
                                  uniquingKeysWith: { $1 }),
            priority: priority))
        if !nextModifyErrors.isEmpty { throw nextModifyErrors.removeFirst() }
        var result = ModifyRecordsResult()
        for record in records {
            let name = record.recordID.recordName
            if let error = popRecordError(name) {
                result.failures[record.recordID] = error
                continue
            }
            let zoneName = record.recordID.zoneID.zoneName
            guard var zone = zones[zoneName], !(scope == .shared && zone.leftBy.contains(user)) else {
                result.failures[record.recordID] = CKError(.zoneNotFound)
                continue
            }
            let existing = zone.records[name]
            let stored: CKRecord
            if let existing, savePolicy == .changedKeys {
                stored = existing.record.copy() as! CKRecord
                for key in record.changedKeys() { stored[key] = record[key] }
            } else if let existing, savePolicy == .allKeys, !servedRecords.contains(ObjectIdentifier(record)) {
                // A save without the server's change tag conflicts (as CloudKit does).
                let server = existing.record.copy() as! CKRecord
                serve(server)
                result.failures[record.recordID] = CKError(.serverRecordChanged,
                                                           userInfo: [CKRecordChangedErrorServerRecordKey: server])
                continue
            } else {
                stored = record.copy() as! CKRecord
            }
            zone.sequence += 1
            zone.records[name] = StoredRecord(record: stored, creator: existing?.creator ?? user,
                                              modifier: user, sequence: zone.sequence)
            zones[zoneName] = zone
            let returned = stored.copy() as! CKRecord
            serve(returned)
            result.saved[record.recordID] = returned
        }
        for id in ids {
            if let error = popRecordError(id.recordName) {
                result.failures[id] = error
                continue
            }
            let zoneName = id.zoneID.zoneName
            guard var zone = zones[zoneName], !(scope == .shared && zone.leftBy.contains(user)) else {
                result.failures[id] = CKError(.zoneNotFound)
                continue
            }
            guard let existing = zone.records.removeValue(forKey: id.recordName) else {
                result.failures[id] = CKError(.unknownItem)
                continue
            }
            zone.sequence += 1
            zone.deletions.append((zone.sequence, DeletedRecord(recordID: id, recordType: existing.record.recordType)))
            zones[zoneName] = zone
            result.deleted.insert(id)
        }
        return result
    }

    func saveZones(_ newZones: [CKRecordZone]) {
        for zone in newZones where zones[zone.zoneID.zoneName] == nil {
            zones[zone.zoneID.zoneName] = ZoneState()
        }
    }

    func deleteZones(scope: CKDatabase.Scope, user: String, _ ids: [CKRecordZone.ID]) throws {
        if !nextModifyErrors.isEmpty { throw nextModifyErrors.removeFirst() }
        for id in ids {
            guard zones[id.zoneName] != nil else { throw CKError(.zoneNotFound) }
            if scope == .shared {
                zones[id.zoneName]?.leftBy.insert(user)
            } else {
                zones[id.zoneName] = nil
            }
        }
    }

    func allZoneIDs(scope: CKDatabase.Scope, user: String) throws -> [CKRecordZone.ID] {
        if !nextFetchErrors.isEmpty { throw nextFetchErrors.removeFirst() }
        let owner = scope == .private ? CKCurrentUserDefaultName : "_owner"
        return zones.keys.sorted()
            .filter { scope == .private || !(zones[$0]?.leftBy.contains(user) ?? true) }
            .map { CKRecordZone.ID(zoneName: $0, ownerName: owner) }
    }

    func fetchChanges(in zoneIDs: [CKRecordZone.ID], since tokens: [CKRecordZone.ID: Data]) throws -> [CKRecordZone.ID: ZoneChanges] {
        fetchCount += 1
        if let error = numberedFetchErrors.removeValue(forKey: fetchCount) { throw error }
        if !nextFetchErrors.isEmpty { throw nextFetchErrors.removeFirst() }
        var output: [CKRecordZone.ID: ZoneChanges] = [:]
        for zoneID in zoneIDs {
            if var queued = zoneFetchErrors[zoneID.zoneName], !queued.isEmpty {
                let error = queued.removeFirst()
                zoneFetchErrors[zoneID.zoneName] = queued
                output[zoneID] = ZoneChanges(failure: error)
                continue
            }
            guard let zone = zones[zoneID.zoneName] else {
                output[zoneID] = ZoneChanges(failure: CKError(.zoneNotFound))
                continue
            }
            var since = 0
            if let data = tokens[zoneID] {
                guard let token = Self.decodeToken(data), token.epoch == tokenEpoch else {
                    output[zoneID] = ZoneChanges(failure: CKError(.changeTokenExpired))
                    continue
                }
                since = token.sequence
            }
            var changes = ZoneChanges()
            for stored in zone.records.values.sorted(by: { $0.sequence < $1.sequence }) where stored.sequence > since {
                var fetched = FetchedRecord(record: stored.record.copy() as! CKRecord,
                                            creatorRecordName: stored.creator,
                                            lastModifierRecordName: stored.modifier)
                if stored.record.recordType == "cloudkit.share" {
                    fetched.participantName = participantNames[zoneID.zoneName]
                    fetched.participantAccepted = participantAccepted[zoneID.zoneName] ?? false
                }
                changes.changed.append(fetched)
            }
            changes.deleted = zone.deletions.filter { $0.sequence > since }.map(\.deleted)
            changes.newToken = Self.encodeToken(epoch: tokenEpoch, sequence: zone.sequence)
            output[zoneID] = changes
        }
        return output
    }

    // MARK: Helpers

    private var servedRecords: Set<ObjectIdentifier> = []
    private var servedRetain: [CKRecord] = []

    private func serve(_ record: CKRecord) {
        servedRecords.insert(ObjectIdentifier(record))
        servedRetain.append(record)
    }

    private func popRecordError(_ name: String) -> CKError? {
        guard var queued = recordErrors[name], !queued.isEmpty else { return nil }
        let error = queued.removeFirst()
        recordErrors[name] = queued
        return error
    }

    private static func encodeToken(epoch: Int, sequence: Int) -> Data {
        Data("\(epoch):\(sequence)".utf8)
    }

    private static func decodeToken(_ data: Data) -> (epoch: Int, sequence: Int)? {
        let parts = String(decoding: data, as: UTF8.self).split(separator: ":")
        guard parts.count == 2, let epoch = Int(parts[0]), let sequence = Int(parts[1]) else { return nil }
        return (epoch, sequence)
    }
}

/// An `InMemoryCloudBackend` seen by one user.
public struct InMemoryCloudContainer: CloudContainer {
    public let backend: InMemoryCloudBackend
    public let user: String

    public var privateDatabase: any CloudDatabase {
        InMemoryCloudDatabase(backend: backend, scope: .private, user: user)
    }

    public var sharedDatabase: any CloudDatabase {
        InMemoryCloudDatabase(backend: backend, scope: .shared, user: user)
    }

    public func acceptShare(_ metadata: CKShare.Metadata) async throws -> CKRecordZone.ID {
        metadata.share.recordID.zoneID
    }
}

/// One database view of an `InMemoryCloudBackend`.
public struct InMemoryCloudDatabase: CloudDatabase {
    public let backend: InMemoryCloudBackend
    public let scope: CKDatabase.Scope
    public let user: String
    public var priority: CloudPriority = .interactive

    public func withPriority(_ priority: CloudPriority) -> any CloudDatabase {
        var copy = self
        copy.priority = priority
        return copy
    }

    public func modifyRecords(saving records: [CKRecord], deleting recordIDs: [CKRecord.ID],
                              savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
                              atomically: Bool) async throws -> ModifyRecordsResult {
        try await backend.modify(scope: scope, user: user, saving: records, deleting: recordIDs,
                                 savePolicy: savePolicy, atomically: atomically, priority: priority)
    }

    public func saveZones(_ zones: [CKRecordZone]) async throws {
        await backend.saveZones(zones)
    }

    public func deleteZones(_ zoneIDs: [CKRecordZone.ID]) async throws {
        try await backend.deleteZones(scope: scope, user: user, zoneIDs)
    }

    public func allZoneIDs() async throws -> [CKRecordZone.ID] {
        try await backend.allZoneIDs(scope: scope, user: user)
    }

    public func fetchChanges(in zoneIDs: [CKRecordZone.ID], since tokens: [CKRecordZone.ID: Data]) async throws -> [CKRecordZone.ID: ZoneChanges] {
        try await backend.fetchChanges(in: zoneIDs, since: tokens)
    }
}
