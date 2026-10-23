// The device's random UUID (SPEC §8.2 `Device` recordName): UUID v4 created on first launch and
// kept in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it never
// moves to another device through a backup or iCloud Keychain. It is not a secret, but it must
// be stable: a new ID would show up on Ben's dashboard as a new device.

import Foundation
import os
import Security

public protocol DeviceIdentityStore: Sendable {
    /// Loads this device's ID, creating and storing it on first use.
    func deviceID() throws -> UUID
}

public enum DeviceIdentityError: Error, Sendable, Equatable {
    /// A Keychain call failed (for example before first unlock, or a missing entitlement in an
    /// unsigned build). Callers must not invent a replacement ID for syncing.
    case keychain(OSStatus)
    /// The stored item is not a UUID.
    case corrupt
}

/// The Keychain-backed store used by the apps.
///
/// On macOS it uses the data-protection keychain (`kSecUseDataProtectionKeychain`), never the
/// legacy login keychain, so it can never show a "wants to use your keychain" prompt.
public final class KeychainDeviceIdentityStore: DeviceIdentityStore {
    public static let service = AppIdentity.prefix + ".device-id"
    public static let account = "device"

    private let cache = OSAllocatedUnfairLock<UUID?>(initialState: nil)

    public init() {}

    public func deviceID() throws -> UUID {
        if let cached = cache.withLock({ $0 }) { return cached }
        let id = try loadOrCreate()
        cache.withLock { $0 = id }
        return id
    }

    /// The attributes that identify the item (shared by read, add).
    static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// The attributes for a new item.
    static func addQuery(for id: UUID) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = Data(id.uuidString.lowercased().utf8)
        return query
    }

    private func loadOrCreate() throws -> UUID {
        if let existing = try read() { return existing }
        let id = UUID()
        let status = SecItemAdd(Self.addQuery(for: id) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            Log.sync.info("device.id.created")
            return id
        case errSecDuplicateItem:
            // Another thread won the race; use the stored one.
            if let existing = try read() { return existing }
            throw DeviceIdentityError.corrupt
        default:
            Log.sync.error("device.id.add.failed status=\(status, privacy: .public)")
            throw DeviceIdentityError.keychain(status)
        }
    }

    private func read() throws -> UUID? {
        var query = Self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8),
                  let id = UUID(uuidString: string)
            else { throw DeviceIdentityError.corrupt }
            return id
        case errSecItemNotFound:
            return nil
        default:
            Log.sync.error("device.id.read.failed status=\(status, privacy: .public)")
            throw DeviceIdentityError.keychain(status)
        }
    }
}

/// An in-memory identity for tests, previews and `-FSNoCloud`. Never synced anywhere.
public final class InMemoryDeviceIdentityStore: DeviceIdentityStore {
    private let id: UUID
    private let failure = OSAllocatedUnfairLock<DeviceIdentityError?>(initialState: nil)

    public init(_ id: UUID = UUID()) {
        self.id = id
    }

    /// Makes `deviceID()` throw `error` until cleared with nil (to test a locked Keychain).
    public func setFailure(_ error: DeviceIdentityError?) {
        failure.withLock { $0 = error }
    }

    public func deviceID() throws -> UUID {
        if let error = failure.withLock({ $0 }) { throw error }
        return id
    }
}
