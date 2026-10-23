// One place that decides between CloudKit and the in-memory sink (SPEC §13.2).
//
// - `-FSNoCloud` / `-FSDemoState`: InMemoryResultSink, no OwnerStore, no CKContainer, no Keychain.
// - A build without the iCloud entitlement (unsigned dev build): same as above, so it never traps.
// - Otherwise: CloudKitSink + OwnerStore over one LiveCloudContainer, whose CKContainer is created
//   lazily on the first CloudKit call. No iCloud account just means writes queue as transient.

import Foundation

public struct SyncServices: Sendable {
    /// Where this device's results go.
    public let sink: any ResultSink
    /// The CloudKit sink (share acceptance, connection state, leave), or nil when in-memory.
    public let cloudSink: CloudKitSink?
    /// Ben's owner features, or nil when in-memory.
    public let owner: OwnerStore?
    /// This device's ID.
    public let deviceIdentity: any DeviceIdentityStore
    /// Local, non-secret sync state.
    public let settings: SyncSettings

    public init(sink: any ResultSink, cloudSink: CloudKitSink?, owner: OwnerStore?,
                deviceIdentity: any DeviceIdentityStore, settings: SyncSettings) {
        self.sink = sink
        self.cloudSink = cloudSink
        self.owner = owner
        self.deviceIdentity = deviceIdentity
        self.settings = settings
    }

    /// True when results really leave the device.
    public var usesCloud: Bool { cloudSink != nil }

    /// The in-memory configuration (tests, previews, `-FSNoCloud`, `-FSDemoState`).
    public static func inMemory(deviceID: UUID = UUID()) -> SyncServices {
        SyncServices(sink: InMemoryResultSink(), cloudSink: nil, owner: nil,
                     deviceIdentity: InMemoryDeviceIdentityStore(deviceID), settings: .inMemory())
    }

    /// The services for this launch.
    /// - Parameter isEntitled: injectable for tests; defaults to the real entitlement check.
    public static func make(
        options: LaunchOptions,
        clock: Clock = .system,
        isEntitled: () -> Bool = { CloudAvailability.isEntitled() }
    ) -> SyncServices {
        guard !options.noCloud else {
            Log.sync.info("sync.mode inMemory reason=noCloud")
            return .inMemory()
        }
        guard isEntitled() else {
            Log.sync.notice("sync.mode inMemory reason=notEntitled")
            return .inMemory()
        }
        let container = LiveCloudContainer()
        let settings = SyncSettings(store: UserDefaultsStore())
        let identity = KeychainDeviceIdentityStore()
        let sink = CloudKitSink(container: container, identity: identity, settings: settings, clock: clock)
        #if DEBUG
        // Debug builds are signed for the Development CloudKit environment (§14.2 step 2).
        let seedsSchema = true
        #else
        let seedsSchema = false
        #endif
        let owner = OwnerStore(container: container, settings: settings, clock: clock, seedsSchema: seedsSchema)
        Log.sync.info("sync.mode cloudKit")
        return SyncServices(sink: sink, cloudSink: sink, owner: owner, deviceIdentity: identity, settings: settings)
    }
}
