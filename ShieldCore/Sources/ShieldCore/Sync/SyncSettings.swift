// Non-secret sync state kept on this device (SPEC §8.4: "store the accepted zoneID in
// UserDefaults (non-secret)"). Nothing here is a secret, and nothing here is ever synced.

import CloudKit
import Foundation
import os

/// A tiny key-value store. `UserDefaultsStore` in the app, `InMemoryKeyValueStore` in tests.
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// `UserDefaults`-backed store.
public final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// In-memory store for tests, previews and `-FSNoCloud`.
public final class InMemoryKeyValueStore: KeyValueStore {
    private let storage = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

    public init() {}

    public func data(forKey key: String) -> Data? {
        storage.withLock { $0[key] }
    }

    public func set(_ data: Data?, forKey key: String) {
        storage.withLock { $0[key] = data }
    }

    public var keys: Set<String> { storage.withLock { Set($0.keys) } }
}

/// Where this device writes its records.
public struct SyncTarget: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// A family member's device: the person zone in the shared database.
        case sharedZone
        /// One of Ben's own devices: `z_self` in Ben's private database.
        case ownerSelf
    }

    public var kind: Kind
    public var zoneName: String
    public var ownerName: String

    public init(kind: Kind, zoneName: String, ownerName: String) {
        self.kind = kind
        self.zoneName = zoneName
        self.ownerName = ownerName
    }

    /// The person zone Ben shared with this device's Apple ID.
    public static func shared(_ zoneID: CKRecordZone.ID) -> SyncTarget {
        SyncTarget(kind: .sharedZone, zoneName: zoneID.zoneName, ownerName: zoneID.ownerName)
    }

    /// Ben's own `z_self` zone.
    public static let ownerSelf = SyncTarget(kind: .ownerSelf, zoneName: Records.selfZoneName,
                                             ownerName: CKCurrentUserDefaultName)

    public var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }
}

/// The sync state shown in About (§10.1 item 12).
public enum SyncConnectionState: String, Codable, Sendable, Hashable {
    /// No share accepted yet (and not Ben's own device).
    case notJoined
    /// "Connected to Ben".
    case connected
    /// "Not connected to Ben": zone or share gone. The app keeps working locally.
    case notConnected
    /// Joined, but nothing is getting through: the server refuses this device's records (a setup
    /// problem only Ben can fix, `SyncFailure.permanent`), or the iCloud account can't take them
    /// until someone acts (signed out, storage full: `SyncFailure.accountBlocked`, still retried).
    /// The app keeps working locally; the next delivery that works sets `.connected` again.
    case notDelivering
}

/// Typed access to the sync keys in a `KeyValueStore`.
public struct SyncSettings: Sendable {
    public enum Key {
        public static let target = "fs.sync.target"
        public static let connection = "fs.sync.connection"
        public static let lastSent = "fs.sync.lastSent"
        public static let ownerMode = "fs.owner.mode"
        public static let dashboardCache = "fs.owner.dashboardCache"
    }

    /// What was last delivered, for "skip a write if nothing changed and lastReport is today".
    public struct LastSent: Codable, Sendable, Hashable {
        public var fingerprint: String
        public var day: DateDay
        public var target: SyncTarget

        public init(fingerprint: String, day: DateDay, target: SyncTarget) {
            self.fingerprint = fingerprint
            self.day = day
            self.target = target
        }
    }

    public let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    public static func inMemory() -> SyncSettings {
        SyncSettings(store: InMemoryKeyValueStore())
    }

    public var target: SyncTarget? {
        get { decode(SyncTarget.self, Key.target) }
        nonmutating set { encode(newValue, Key.target) }
    }

    public var connection: SyncConnectionState {
        get { decode(SyncConnectionState.self, Key.connection) ?? (target == nil ? .notJoined : .connected) }
        nonmutating set { encode(newValue, Key.connection) }
    }

    public var lastSent: LastSent? {
        get { decode(LastSent.self, Key.lastSent) }
        nonmutating set { encode(newValue, Key.lastSent) }
    }

    /// Owner mode (cached): true once `z_admin` exists in this Apple ID's private database.
    public var isOwner: Bool {
        get { decode(Bool.self, Key.ownerMode) ?? false }
        nonmutating set { encode(newValue, Key.ownerMode) }
    }

    func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value else {
            store.set(nil, forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        store.set(try? encoder.encode(value), forKey: key)
    }
}
