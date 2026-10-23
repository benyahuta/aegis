// Local-only persistence for small Codable state (self-reports, reminder bookkeeping).
// Nothing here syncs (H5). No secrets are ever stored here (H2): only enum IDs, answers and days.

import Foundation
import os

/// Where a small blob of local state lives.
public protocol LocalStatePersistence: Sendable {
    func load() -> Data?
    func save(_ data: Data) throws
    func erase()
}

/// `UserDefaults` storage (the default for the apps).
public struct UserDefaultsPersistence: LocalStatePersistence {
    public let key: String
    public let suiteName: String?

    public init(key: String, suiteName: String? = nil) {
        self.key = key
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> Data? { defaults.data(forKey: key) }

    public func save(_ data: Data) throws { defaults.set(data, forKey: key) }

    public func erase() { defaults.removeObject(forKey: key) }
}

/// A JSON file (e.g. in Application Support). Written atomically.
public struct FilePersistence: LocalStatePersistence {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/FamilyShield/<name>`.
    public static func applicationSupport(named name: String) -> FilePersistence? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return FilePersistence(url: base.appendingPathComponent("FamilyShield", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false))
    }

    public func load() -> Data? { try? Data(contentsOf: url) }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    public func erase() { try? FileManager.default.removeItem(at: url) }
}

/// In memory only (tests, previews, `-FSDemoState`).
public final class InMemoryPersistence: LocalStatePersistence {
    private let storage: OSAllocatedUnfairLock<Data?>

    public init(_ data: Data? = nil) {
        storage = OSAllocatedUnfairLock(initialState: data)
    }

    public func load() -> Data? { storage.withLock { $0 } }

    public func save(_ data: Data) throws { storage.withLock { $0 = data } }

    public func erase() { storage.withLock { $0 = nil } }
}
