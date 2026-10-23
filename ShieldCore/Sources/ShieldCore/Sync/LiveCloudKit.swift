// The real CloudKit implementation of `CloudContainer` / `CloudDatabase`.
//
// `CKContainer` is created LAZILY, on the first real database call, never at app launch and
// never in `-FSNoCloud` / `-FSDemoState` runs or tests (those never construct this type).
// `CloudAvailability` refuses CloudKit for builds without the iCloud entitlement (unsigned dev
// builds), because `CKContainer` traps in that case.

import CloudKit
import Foundation
import MachO
import os
#if os(macOS)
import Security
#endif

/// Shared identifiers (§2).
public enum CloudConfig {
    public static let containerIdentifier = "iCloud." + AppIdentity.prefix
}

// MARK: - Entitlement gate

public enum CloudAvailability {
    static let containersEntitlement = "com.apple.developer.icloud-container-identifiers"
    static let servicesEntitlement = "com.apple.developer.icloud-services"

    /// True when this process is entitled to use `containerIdentifier` with CloudKit.
    /// - macOS: reads the signed entitlements of this process (`SecTask`).
    /// - iOS Simulator: reads the simulated-entitlements section Xcode embeds when it signs a
    ///   simulator build (absent in `CODE_SIGNING_ALLOWED=NO` builds).
    /// - iOS device: an installed app is always signed with its entitlements file.
    public static func isEntitled(containerIdentifier: String = CloudConfig.containerIdentifier) -> Bool {
        guard let entitlements = currentEntitlements() else { return false }
        return entitlementsAllowCloudKit(entitlements, containerIdentifier: containerIdentifier)
    }

    /// Pure check over an entitlements dictionary (unit-tested).
    public static func entitlementsAllowCloudKit(_ entitlements: [String: Any], containerIdentifier: String) -> Bool {
        guard let containers = entitlements[containersEntitlement] as? [String],
              containers.contains(containerIdentifier),
              let services = entitlements[servicesEntitlement] as? [String],
              services.contains("CloudKit")
        else { return false }
        return true
    }

    /// Nil means "unknown"; on an iOS device we return a synthetic dictionary (see above).
    static func currentEntitlements() -> [String: Any]? {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        var result: [String: Any] = [:]
        for key in [containersEntitlement, servicesEntitlement] {
            if let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) {
                result[key] = value
            }
        }
        return result.isEmpty ? nil : result
        #elseif targetEnvironment(simulator)
        return simulatorEntitlements()
        #else
        return [containersEntitlement: [CloudConfig.containerIdentifier], servicesEntitlement: ["CloudKit"]]
        #endif
    }

    #if targetEnvironment(simulator)
    private static func simulatorEntitlements() -> [String: Any]? {
        guard let header = _dyld_get_image_header(0) else { return nil }
        var size: UInt = 0
        let data = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) { header64 in
            getsectiondata(header64, "__TEXT", "__entitlements", &size)
        }
        guard let data, size > 0 else { return nil }
        let bytes = Data(bytes: data, count: Int(size))
        return (try? PropertyListSerialization.propertyList(from: bytes, format: nil)) as? [String: Any]
    }
    #endif
}

// MARK: - Container

/// The live container. Holding one of these does NOT create a `CKContainer`.
public final class LiveCloudContainer: CloudContainer {
    public let identifier: String
    private let lazyContainer = OSAllocatedUnfairLock<CKContainer?>(initialState: nil)

    public init(identifier: String = CloudConfig.containerIdentifier) {
        self.identifier = identifier
    }

    /// The `CKContainer`, created on first access. Also needed by the UI for
    /// `UICloudSharingController(share:container:)` / `NSSharingServicePicker`.
    public var container: CKContainer {
        lazyContainer.withLock { stored in
            if let stored { return stored }
            Log.sync.info("container.create")
            let created = CKContainer(identifier: identifier)
            stored = created
            return created
        }
    }

    public var privateDatabase: any CloudDatabase {
        LiveCloudDatabase(scope: .private) { [self] in container }
    }

    public var sharedDatabase: any CloudDatabase {
        LiveCloudDatabase(scope: .shared) { [self] in container }
    }

    public func acceptShare(_ metadata: CKShare.Metadata) async throws -> CKRecordZone.ID {
        let container = self.container
        let accepted = OSAllocatedUnfairLock<Result<CKShare, CKError>?>(initialState: nil)
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.qualityOfService = .userInitiated
            operation.perShareResultBlock = { _, result in
                accepted.withLock { $0 = result.mapError(LiveCloudDatabase.ckError) }
            }
            operation.acceptSharesResultBlock = { result in
                switch (result, accepted.withLock { $0 }) {
                case (_, .success(let share)?):
                    continuation.resume(returning: share.recordID.zoneID)
                case (_, .failure(let error)?):
                    continuation.resume(throwing: error)
                case (.failure(let error), nil):
                    continuation.resume(throwing: error)
                case (.success, nil):
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
            container.add(operation)
        }
    }
}

// MARK: - Database

struct LiveCloudDatabase: CloudDatabase {
    let scope: CKDatabase.Scope
    let containerProvider: @Sendable () -> CKContainer
    var priority: CloudPriority

    init(scope: CKDatabase.Scope, priority: CloudPriority = .interactive,
         containerProvider: @escaping @Sendable () -> CKContainer) {
        self.scope = scope
        self.priority = priority
        self.containerProvider = containerProvider
    }

    func withPriority(_ priority: CloudPriority) -> any CloudDatabase {
        var copy = self
        copy.priority = priority
        return copy
    }

    /// Every operation this database runs uses this QoS (also the zone calls, which the async
    /// `CKDatabase` helpers would run at the discretionary default).
    var qualityOfService: QualityOfService {
        switch priority {
        case .interactive: .userInitiated
        case .background: .utility
        }
    }

    private var database: CKDatabase {
        containerProvider().database(with: scope)
    }

    static func ckError(_ error: any Error) -> CKError {
        (error as? CKError) ?? CKError(.internalError)
    }

    func modifyRecords(
        saving records: [CKRecord],
        deleting recordIDs: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> ModifyRecordsResult {
        let database = self.database
        let box = OSAllocatedUnfairLock(initialState: ModifyRecordsResult())
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: recordIDs)
            operation.savePolicy = savePolicy
            operation.isAtomic = atomically
            operation.qualityOfService = qualityOfService
            operation.perRecordSaveBlock = { id, result in
                box.withLock { state in
                    switch result {
                    case .success(let record): state.saved[id] = record
                    case .failure(let error): state.failures[id] = Self.ckError(error)
                    }
                }
            }
            operation.perRecordDeleteBlock = { id, result in
                box.withLock { state in
                    switch result {
                    case .success: state.deleted.insert(id)
                    case .failure(let error): state.failures[id] = Self.ckError(error)
                    }
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: box.withLock { $0 })
                case .failure(let error):
                    let ckError = Self.ckError(error)
                    if ckError.code == .partialFailure {
                        var state = box.withLock { $0 }
                        // Fill in any item errors the per-record blocks did not report.
                        for (key, value) in ckError.partialErrorsByItemID ?? [:] {
                            if let id = key as? CKRecord.ID, state.failures[id] == nil {
                                state.failures[id] = Self.ckError(value)
                            }
                        }
                        continuation.resume(returning: state)
                    } else {
                        continuation.resume(throwing: ckError)
                    }
                }
            }
            database.add(operation)
        }
    }

    func saveZones(_ zones: [CKRecordZone]) async throws {
        try await modifyZones(saving: zones, deleting: [])
    }

    func deleteZones(_ zoneIDs: [CKRecordZone.ID]) async throws {
        try await modifyZones(saving: [], deleting: zoneIDs)
    }

    /// One `CKModifyRecordZonesOperation` at this database's QoS. Throws the first per-zone error.
    private func modifyZones(saving zones: [CKRecordZone], deleting zoneIDs: [CKRecordZone.ID]) async throws {
        let database = self.database
        let firstFailure = OSAllocatedUnfairLock<CKError?>(initialState: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: zones, recordZoneIDsToDelete: zoneIDs)
            operation.qualityOfService = qualityOfService
            operation.perRecordZoneSaveBlock = { _, result in
                if case .failure(let error) = result { firstFailure.withLock { $0 = $0 ?? Self.ckError(error) } }
            }
            operation.perRecordZoneDeleteBlock = { _, result in
                if case .failure(let error) = result { firstFailure.withLock { $0 = $0 ?? Self.ckError(error) } }
            }
            operation.modifyRecordZonesResultBlock = { result in
                if let failure = firstFailure.withLock({ $0 }) {
                    continuation.resume(throwing: failure)
                    return
                }
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: Self.ckError(error))
                }
            }
            database.add(operation)
        }
    }

    func allZoneIDs() async throws -> [CKRecordZone.ID] {
        let database = self.database
        let zoneIDs = OSAllocatedUnfairLock<[CKRecordZone.ID]>(initialState: [])
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
            operation.qualityOfService = qualityOfService
            operation.perRecordZoneResultBlock = { zoneID, result in
                if case .success = result { zoneIDs.withLock { $0.append(zoneID) } }
            }
            operation.fetchRecordZonesResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: zoneIDs.withLock { $0 })
                case .failure(let error): continuation.resume(throwing: Self.ckError(error))
                }
            }
            database.add(operation)
        }
    }

    func fetchChanges(
        in zoneIDs: [CKRecordZone.ID],
        since tokens: [CKRecordZone.ID: Data]
    ) async throws -> [CKRecordZone.ID: ZoneChanges] {
        guard !zoneIDs.isEmpty else { return [:] }
        let database = self.database
        var configurations: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for zoneID in zoneIDs {
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = tokens[zoneID].flatMap(Self.unarchiveToken)
            configurations[zoneID] = configuration
        }
        let box = OSAllocatedUnfairLock(initialState: [CKRecordZone.ID: ZoneChanges]())
        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs,
                                                              configurationsByRecordZoneID: configurations)
            operation.fetchAllChanges = true
            operation.qualityOfService = qualityOfService
            operation.recordWasChangedBlock = { _, result in
                guard case .success(let record) = result else { return }
                let fetched = Self.fetchedRecord(record)
                box.withLock { $0[record.recordID.zoneID, default: ZoneChanges()].changed.append(fetched) }
            }
            operation.recordWithIDWasDeletedBlock = { id, type in
                box.withLock {
                    $0[id.zoneID, default: ZoneChanges()].deleted.append(DeletedRecord(recordID: id, recordType: type))
                }
            }
            operation.recordZoneChangeTokensUpdatedBlock = { zoneID, token, _ in
                let data = token.flatMap(Self.archiveToken)
                box.withLock { $0[zoneID, default: ZoneChanges()].newToken = data }
            }
            operation.recordZoneFetchResultBlock = { zoneID, result in
                box.withLock { state in
                    switch result {
                    case .success(let success):
                        state[zoneID, default: ZoneChanges()].newToken = Self.archiveToken(success.serverChangeToken)
                    case .failure(let error):
                        state[zoneID, default: ZoneChanges()].newToken = nil
                        state[zoneID, default: ZoneChanges()].failure = Self.ckError(error)
                    }
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                let state = box.withLock { $0 }
                switch result {
                case .success:
                    continuation.resume(returning: state)
                case .failure(let error):
                    let ckError = Self.ckError(error)
                    // Per-zone failures are already in `state`; only a total failure throws.
                    if ckError.code == .partialFailure || state.values.contains(where: { $0.failure != nil }) {
                        continuation.resume(returning: state)
                    } else {
                        continuation.resume(throwing: ckError)
                    }
                }
            }
            database.add(operation)
        }
    }

    static func fetchedRecord(_ record: CKRecord) -> FetchedRecord {
        var fetched = FetchedRecord(record: record,
                                    creatorRecordName: record.creatorUserRecordID?.recordName,
                                    lastModifierRecordName: record.lastModifiedUserRecordID?.recordName)
        if let share = record as? CKShare,
           let participant = share.participants.first(where: { $0.role != .owner }) {
            fetched.participantName = participant.userIdentity.nameComponents
            fetched.participantAccepted = participant.acceptanceStatus == .accepted
        }
        return fetched
    }

    static func archiveToken(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func unarchiveToken(_ data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
}
