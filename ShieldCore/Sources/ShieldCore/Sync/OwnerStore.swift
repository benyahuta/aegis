// OwnerStore (SPEC §8.1, §8.4, §8.5, §10.3): everything only Ben's copy of the app does.
//
// - Start a family: create `z_admin` (owner mode marker, labels) and `z_self` (his own devices).
// - Add a person: zone `z_<16 hex>` + zone-wide `CKShare(recordZoneID:)` with
//   `publicPermission = .none`, title "Family Shield". No name in zone names or share metadata.
//   The returned share is presented with `UICloudSharingController` / `NSSharingServicePicker`
//   by the UI (allowed: read-write, private).
// - Labels: `PersonLabel` / `DeviceLabel`, in `z_admin` only.
// - Dashboard: `CKFetchRecordZoneChangesOperation` over every status zone with cached server
//   change tokens (plus `z_admin` for labels), staleness rules and the creator-mismatch flag.

import CloudKit
import Foundation

/// What Ben needs to send an invite.
public struct PersonInvite: Sendable {
    public var zoneID: CKRecordZone.ID
    /// The saved zone-wide share. Present it with the system sharing UI.
    public var share: CKShare
}

public enum OwnerStoreError: Error, Sendable, Equatable {
    /// Owner mode is off (`z_admin` missing). Call `startFamily()` first.
    case notOwner
    /// CloudKit is temporarily unavailable; try again later.
    case unavailable
    /// A zone name that is not a person zone.
    case invalidZone
}

public actor OwnerStore {
    private let container: any CloudContainer
    private let settings: SyncSettings
    private let clock: Clock
    private let makeZoneName: @Sendable () -> String
    private let seedsSchema: Bool

    private var cache: DashboardCache

    /// - Parameter seedsSchema: Development builds only (SyncServices passes `true` for DEBUG):
    ///   "Start a family" also saves, then deletes, one record of every Ben-only type, so the
    ///   CloudKit Development schema has all of them before Ben deploys it to Production (§14.2).
    ///   Production never creates a record type on save; a type missing there would make every
    ///   later save of it fail.
    public init(
        container: any CloudContainer,
        settings: SyncSettings,
        clock: Clock = .system,
        makeZoneName: @escaping @Sendable () -> String = { Records.makePersonZoneName() },
        seedsSchema: Bool = false
    ) {
        self.container = container
        self.settings = settings
        self.clock = clock
        self.makeZoneName = makeZoneName
        self.seedsSchema = seedsSchema
        self.cache = settings.decode(DashboardCache.self, SyncSettings.Key.dashboardCache) ?? DashboardCache()
    }

    /// The container (the UI needs it for the system sharing controller).
    public nonisolated var cloudContainer: any CloudContainer { container }

    static var adminZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Records.adminZoneName, ownerName: CKCurrentUserDefaultName)
    }

    static var selfZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Records.selfZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var privateDB: any CloudDatabase { container.privateDatabase }

    // MARK: Owner mode

    /// Cached owner mode: true when `z_admin` was seen in this Apple ID's private database.
    public var isOwner: Bool { settings.isOwner }

    /// Checks the server for `z_admin`. When found, this device also writes to `z_self`.
    @discardableResult
    public func refreshOwnerMode() async throws -> Bool {
        let zoneIDs: [CKRecordZone.ID]
        do {
            zoneIDs = try await privateDB.allZoneIDs()
        } catch {
            throw OwnerStoreError.unavailable
        }
        let owner = zoneIDs.contains { $0.zoneName == Records.adminZoneName }
        settings.isOwner = owner
        if owner, settings.target == nil {
            settings.target = .ownerSelf
            settings.connection = .connected
        }
        return owner
    }

    /// "I'm setting this up for my family": creates `z_admin` and `z_self`.
    public func startFamily() async throws {
        do {
            try await privateDB.saveZones([CKRecordZone(zoneID: Self.adminZoneID), CKRecordZone(zoneID: Self.selfZoneID)])
        } catch {
            Log.sync.error("owner.start.failed")
            throw OwnerStoreError.unavailable
        }
        settings.isOwner = true
        if settings.target == nil || settings.target?.kind == .ownerSelf {
            settings.target = .ownerSelf
            settings.connection = .connected
        }
        Log.sync.info("owner.start")
        if seedsSchema { await seedAdminSchema() }
    }

    /// Saves one `PersonLabel` and one `DeviceLabel` with every field set, then deletes them.
    /// `Device` and `CheckResult` come from this device's own first report into `z_self`.
    /// Only for the Development environment (`seedsSchema`); failures are logged and ignored.
    func seedAdminSchema() async {
        let personLabel = Records.record(for: PersonLabel(zoneName: Records.schemaSeedZoneName, label: "Schema",
                                                          createdOn: clock.now()), in: Self.adminZoneID)
        let deviceLabel = Records.record(for: DeviceLabel(deviceID: Records.schemaSeedDeviceID, label: "Schema",
                                                          firstCreatorRecordName: "_schema"), in: Self.adminZoneID)
        let records = [personLabel, deviceLabel]
        do {
            let saved = try await privateDB.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: false)
            if let error = saved.failures.values.first {
                Log.sync.error("owner.schemaSeed.failed code=\(error.code.rawValue, privacy: .public)")
            }
            _ = try await privateDB.modifyRecords(saving: [], deleting: records.map(\.recordID), savePolicy: .changedKeys, atomically: false)
            Log.sync.info("owner.schemaSeed done")
        } catch {
            Log.sync.error("owner.schemaSeed.failed code=\((error as? CKError)?.code.rawValue ?? -1, privacy: .public)")
        }
    }

    // MARK: People

    /// Creates a person zone and its zone-wide share, and saves the label (if any) in `z_admin`.
    /// When `label` is nil the dashboard later defaults it to the participant's name.
    public func createPerson(label: String?) async throws -> PersonInvite {
        guard settings.isOwner else { throw OwnerStoreError.notOwner }
        let zoneName = makeZoneName()
        guard Records.isPersonZoneName(zoneName) else { throw OwnerStoreError.invalidZone }
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        do {
            try await privateDB.saveZones([CKRecordZone(zoneID: zoneID)])
        } catch {
            throw OwnerStoreError.unavailable
        }

        let share = CKShare(recordZoneID: zoneID)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = Records.shareTitle as NSString
        let savedShare: CKShare
        do {
            let result = try await privateDB.modifyRecords(saving: [share], deleting: [],
                                                           savePolicy: .allKeys, atomically: true)
            if let failure = result.failures[share.recordID] { throw failure }
            savedShare = (result.saved[share.recordID] as? CKShare) ?? share
        } catch {
            // Don't leave an unshared, unlabeled zone behind.
            try? await privateDB.deleteZones([zoneID])
            throw OwnerStoreError.unavailable
        }

        cache.zones[zoneName] = cache.zones[zoneName] ?? ZoneSnapshot(zoneName: zoneName)
        if let clean = Records.sanitizeLabel(label) {
            let personLabel = PersonLabel(zoneName: zoneName, label: clean, createdOn: clock.now())
            do {
                try await savePersonLabel(personLabel)
            } catch {
                // The invite still works; keep the label locally and save it on the next refresh.
                cache.personLabels[zoneName] = personLabel
                cache.unsavedPersonLabels.insert(zoneName)
            }
        }
        persist()
        Log.sync.info("owner.person.created")
        return PersonInvite(zoneID: zoneID, share: savedShare)
    }

    /// Renames a person (Ben-only, `z_admin`). An empty label clears it.
    public func setPersonLabel(zoneName: String, label: String?) async throws {
        guard Records.isPersonZoneName(zoneName) else { throw OwnerStoreError.invalidZone }
        guard let clean = Records.sanitizeLabel(label) else {
            try await deleteAdminRecord(named: zoneName)
            cache.personLabels[zoneName] = nil
            persist()
            return
        }
        let createdOn = cache.personLabels[zoneName]?.createdOn ?? clock.now()
        try await savePersonLabel(PersonLabel(zoneName: zoneName, label: clean, createdOn: createdOn))
        persist()
    }

    /// Renames a device (Ben-only, `z_admin`). Keeps the creator seen at enrollment.
    public func setDeviceLabel(deviceID: UUID, label: String?) async throws {
        let clean = Records.sanitizeLabel(label) ?? ""
        let firstCreator = cache.deviceLabels[deviceID]?.firstCreatorRecordName
            ?? creatorOfDevice(deviceID) ?? ""
        try await saveDeviceLabels([DeviceLabel(deviceID: deviceID, label: clean, firstCreatorRecordName: firstCreator)])
        persist()
    }

    // MARK: Dashboard

    /// The Family tab from the local cache (no network).
    public func cachedDashboard() -> FamilyDashboard {
        build()
    }

    /// Fetches changes in every status zone (and `z_admin` for labels) using cached change
    /// tokens, applies them, records first creators for new devices, and returns the dashboard.
    /// Throws `.unavailable` when CloudKit can't be reached (the cached dashboard stays valid).
    /// When only some zones fail (`.zoneBusy`, a network blip for one zone…), the zones that
    /// worked are applied, the others keep their last copy, and the dashboard is `incomplete`.
    public func refreshDashboard() async throws -> FamilyDashboard {
        let zoneIDs: [CKRecordZone.ID]
        do {
            zoneIDs = try await privateDB.allZoneIDs()
        } catch {
            throw OwnerStoreError.unavailable
        }
        let owner = zoneIDs.contains { $0.zoneName == Records.adminZoneName }
        settings.isOwner = owner
        guard owner else { throw OwnerStoreError.notOwner }

        let statusZones = zoneIDs.filter { Records.isStatusZoneName($0.zoneName) }
        let liveNames = Set(statusZones.map(\.zoneName))
        // Zones deleted on the server disappear from the dashboard.
        for name in cache.zones.keys where !liveNames.contains(name) {
            cache.zones[name] = nil
            cache.tokens[name] = nil
        }

        let fetchIDs = statusZones + [Self.adminZoneID]
        var changes = try await fetch(fetchIDs)

        // Expired tokens: refetch that zone from scratch (once). Its cached data is only replaced
        // once the refetch succeeded; if it fails, the old data and the expired token stay, so the
        // next refresh tries the from-scratch fetch again and the dashboard stays valid meanwhile.
        let expired = changes.filter { $0.value.failure?.code == .changeTokenExpired }.map(\.key)
        var refetched: Set<String> = []
        if !expired.isEmpty {
            Log.sync.notice("dashboard.tokenExpired count=\(expired.count, privacy: .public)")
            var expiredTokens: [String: Data] = [:]
            for zoneID in expired {
                expiredTokens[zoneID.zoneName] = cache.tokens[zoneID.zoneName]
                cache.tokens[zoneID.zoneName] = nil
            }
            let retried: [CKRecordZone.ID: ZoneChanges]
            do {
                retried = try await fetch(expired)
            } catch {
                for (name, token) in expiredTokens { cache.tokens[name] = token }
                throw error
            }
            for (key, value) in retried {
                changes[key] = value
                if value.failure == nil { refetched.insert(key.zoneName) }
            }
            for (name, token) in expiredTokens where !refetched.contains(name) { cache.tokens[name] = token }
        }

        var failedZones = 0
        for (zoneID, zoneChanges) in changes {
            let name = zoneID.zoneName
            if zoneChanges.failure == nil, refetched.contains(name) {
                // A full refetch replaces what was cached for this zone.
                if name == Records.adminZoneName {
                    cache.personLabels = [:]
                    cache.deviceLabels = [:]
                } else {
                    cache.zones[name] = ZoneSnapshot(zoneName: name)
                }
            }
            if let failure = zoneChanges.failure {
                if SyncFailure.classify(failure) == .notConnected {
                    // The zone is gone: that is current news, not a failed refresh.
                    cache.zones[name] = nil
                    cache.tokens[name] = nil
                } else {
                    // Other failures keep the cached data and token for the next try.
                    failedZones += 1
                    Log.sync.notice("dashboard.zoneFailed code=\(failure.code.rawValue, privacy: .public)")
                }
                continue
            }
            if name == Records.adminZoneName {
                applyAdmin(zoneChanges)
            } else {
                applyStatusZone(name, zoneChanges)
            }
            cache.tokens[name] = zoneChanges.newToken
        }

        await recordFirstCreatorsAndDefaultLabels()
        persist()
        var dashboard = build()
        dashboard.incomplete = failedZones > 0
        return dashboard
    }

    // MARK: Internals

    private func fetch(_ zoneIDs: [CKRecordZone.ID]) async throws -> [CKRecordZone.ID: ZoneChanges] {
        var tokens: [CKRecordZone.ID: Data] = [:]
        for zoneID in zoneIDs {
            if let token = cache.tokens[zoneID.zoneName] { tokens[zoneID] = token }
        }
        do {
            return try await privateDB.fetchChanges(in: zoneIDs, since: tokens)
        } catch {
            Log.sync.error("dashboard.fetch.failed")
            throw OwnerStoreError.unavailable
        }
    }

    private func applyAdmin(_ changes: ZoneChanges) {
        for fetched in changes.changed {
            if let label = Records.personLabel(from: fetched.record) {
                guard !cache.unsavedPersonLabels.contains(label.zoneName) else { continue }
                cache.personLabels[label.zoneName] = label
            } else if let label = Records.deviceLabel(from: fetched.record) {
                cache.deviceLabels[label.deviceID] = label
            }
        }
        for deleted in changes.deleted {
            let name = deleted.recordID.recordName
            switch deleted.recordType {
            case Records.RecordType.personLabel:
                cache.personLabels[name] = nil
            case Records.RecordType.deviceLabel:
                if let id = Records.deviceID(fromRecordName: name) { cache.deviceLabels[id] = nil }
            default:
                break
            }
        }
    }

    private func applyStatusZone(_ zoneName: String, _ changes: ZoneChanges) {
        var zone = cache.zones[zoneName] ?? ZoneSnapshot(zoneName: zoneName)
        var dropped = 0
        for fetched in changes.changed {
            let record = fetched.record
            let authorship = RecordAuthorship(creator: fetched.creatorRecordName,
                                              lastModifier: fetched.lastModifierRecordName)
            switch record.recordType {
            case Records.RecordType.device:
                if let info = Records.deviceInfo(from: record) {
                    zone.devices[info.deviceID] = DeviceSnapshot(info: info, authorship: authorship)
                } else {
                    dropped += 1
                }
            case Records.RecordType.checkResult:
                if let result = Records.checkResult(from: record) {
                    zone.results[record.recordID.recordName] = ResultSnapshot(result: result, authorship: authorship)
                } else {
                    // Off-schema (unknown check ID, bad status, bad name): ignored, shows grey.
                    zone.results[record.recordID.recordName] = nil
                    dropped += 1
                }
            case CKRecord.SystemType.share:
                zone.participantName = fetched.participantName
                zone.participantAccepted = fetched.participantAccepted
            default:
                dropped += 1
            }
        }
        for deleted in changes.deleted {
            let name = deleted.recordID.recordName
            if let id = Records.deviceID(fromRecordName: name) {
                zone.devices[id] = nil
                // A device that left takes its results with it.
                zone.results = zone.results.filter { $0.value.result.deviceID != id }
            } else {
                zone.results[name] = nil
            }
        }
        if dropped > 0 {
            Log.sync.notice("dashboard.dropped count=\(dropped, privacy: .public)")
        }
        cache.zones[zoneName] = zone
    }

    /// §8.2 `DeviceLabel.firstCreatorRecordName`: remember who created each new device's record.
    /// §8.4: default a missing `PersonLabel` to the participant's name.
    private func recordFirstCreatorsAndDefaultLabels() async {
        var newDeviceLabels: [DeviceLabel] = []
        for zone in cache.zones.values {
            for (id, device) in zone.devices where (cache.deviceLabels[id]?.firstCreatorRecordName ?? "").isEmpty {
                guard let creator = device.authorship.creator, !creator.isEmpty else { continue }
                let label = cache.deviceLabels[id]?.label ?? ""
                newDeviceLabels.append(DeviceLabel(deviceID: id, label: label, firstCreatorRecordName: creator))
            }
        }
        if !newDeviceLabels.isEmpty {
            try? await saveDeviceLabels(newDeviceLabels)
        }
        for zoneName in cache.unsavedPersonLabels {
            guard let label = cache.personLabels[zoneName] else {
                cache.unsavedPersonLabels.remove(zoneName)
                continue
            }
            if (try? await savePersonLabel(label)) != nil {
                cache.unsavedPersonLabels.remove(zoneName)
            }
        }
        for zone in cache.zones.values where zone.zoneName != Records.selfZoneName {
            guard cache.personLabels[zone.zoneName] == nil,
                  let name = zone.participantName.flatMap(DashboardAggregator.formatName)
            else { continue }
            try? await savePersonLabel(PersonLabel(zoneName: zone.zoneName, label: name, createdOn: clock.now()))
        }
    }

    private func savePersonLabel(_ label: PersonLabel) async throws {
        let record = Records.record(for: label, in: Self.adminZoneID)
        try await saveAdmin([record])
        cache.personLabels[label.zoneName] = label
    }

    private func saveDeviceLabels(_ labels: [DeviceLabel]) async throws {
        let records = labels.map { Records.record(for: $0, in: Self.adminZoneID) }
        let saved = try await saveAdmin(records)
        for label in labels where saved.contains(Records.deviceRecordName(label.deviceID)) {
            cache.deviceLabels[label.deviceID] = label
        }
    }

    /// Saves Ben-only records with `.changedKeys` (overwrites, never conflicts). Returns the
    /// record names that were saved.
    @discardableResult
    private func saveAdmin(_ records: [CKRecord]) async throws -> Set<String> {
        do {
            let result = try await privateDB.modifyRecords(saving: records, deleting: [],
                                                           savePolicy: .changedKeys, atomically: false)
            if let error = result.failures.values.first, result.saved.isEmpty {
                throw error
            }
            return Set(result.saved.keys.map(\.recordName))
        } catch {
            // The code tells a network blip from a refusal no retry fixes (for example a record
            // type missing from the Production schema: `.serverRejectedRequest`/`.invalidArguments`).
            let code = (error as? CKError)?.code.rawValue ?? -1
            if case .permanent = SyncFailure.classify(error) {
                Log.sync.error("owner.admin.rejected code=\(code, privacy: .public)")
            } else {
                Log.sync.notice("owner.admin.failed code=\(code, privacy: .public)")
            }
            throw OwnerStoreError.unavailable
        }
    }

    private func deleteAdminRecord(named name: String) async throws {
        let id = CKRecord.ID(recordName: name, zoneID: Self.adminZoneID)
        do {
            let result = try await privateDB.modifyRecords(saving: [], deleting: [id],
                                                           savePolicy: .changedKeys, atomically: false)
            if let error = result.failures[id], SyncFailure.classify(error) != .alreadyGone {
                throw error
            }
        } catch {
            throw OwnerStoreError.unavailable
        }
    }

    private func creatorOfDevice(_ deviceID: UUID) -> String? {
        for zone in cache.zones.values {
            if let creator = zone.devices[deviceID]?.authorship.creator { return creator }
        }
        return nil
    }

    private func build() -> FamilyDashboard {
        DashboardAggregator.build(zones: Array(cache.zones.values), personLabels: cache.personLabels,
                                  deviceLabels: cache.deviceLabels, today: clock.today())
    }

    private func persist() {
        settings.encode(cache, SyncSettings.Key.dashboardCache)
    }
}

/// What OwnerStore keeps between launches on Ben's device (never synced anywhere).
struct DashboardCache: Codable, Sendable {
    var version = 1
    var zones: [String: ZoneSnapshot] = [:]
    /// Archived server change tokens by zone name (including `z_admin`).
    var tokens: [String: Data] = [:]
    var personLabels: [String: PersonLabel] = [:]
    var deviceLabels: [UUID: DeviceLabel] = [:]
    /// Labels Ben typed that could not be saved yet.
    var unsavedPersonLabels: Set<String> = []
}
