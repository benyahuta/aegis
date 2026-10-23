import Security
import XCTest
@testable import ShieldCore

/// `-FSNoCloud` / unsigned builds never touch CloudKit; Keychain attributes are right.
/// (No test here touches the real Keychain or creates a CKContainer.)
final class SyncServicesTests: XCTestCase {
    func testNoCloudUsesInMemorySinkWithoutCheckingEntitlements() {
        var checked = false
        let services = SyncServices.make(options: LaunchOptions(arguments: ["app", "-FSNoCloud"])) {
            checked = true
            return true
        }
        XCTAssertFalse(checked, "no entitlement probe, no container")
        XCTAssertTrue(services.sink is InMemoryResultSink)
        XCTAssertNil(services.cloudSink)
        XCTAssertNil(services.owner)
        XCTAssertFalse(services.usesCloud)
    }

    func testDemoStateImpliesNoCloud() {
        let services = SyncServices.make(options: LaunchOptions(arguments: ["app", "-FSDemoState", "homeProtected"])) { true }
        XCTAssertTrue(services.sink is InMemoryResultSink)
    }

    func testMissingEntitlementFallsBackToInMemory() {
        let services = SyncServices.make(options: LaunchOptions(noCloud: false)) { false }
        XCTAssertTrue(services.sink is InMemoryResultSink)
        XCTAssertNil(services.cloudSink)
    }

    func testTestHostIsNotEntitled() {
        // `swift test` runs unsigned: the real probe must say no, so the app would never trap.
        XCTAssertFalse(CloudAvailability.isEntitled())
    }

    func testEntitlementDictionaryCheck() {
        let good: [String: Any] = [
            "com.apple.developer.icloud-container-identifiers": ["iCloud." + AppIdentity.prefix],
            "com.apple.developer.icloud-services": ["CloudKit"],
        ]
        XCTAssertTrue(CloudAvailability.entitlementsAllowCloudKit(good, containerIdentifier: CloudConfig.containerIdentifier))
        var otherContainer = good
        otherContainer["com.apple.developer.icloud-container-identifiers"] = ["iCloud.com.example"]
        XCTAssertFalse(CloudAvailability.entitlementsAllowCloudKit(otherContainer, containerIdentifier: CloudConfig.containerIdentifier))
        var noService = good
        noService["com.apple.developer.icloud-services"] = ["CloudDocuments"]
        XCTAssertFalse(CloudAvailability.entitlementsAllowCloudKit(noService, containerIdentifier: CloudConfig.containerIdentifier))
        XCTAssertFalse(CloudAvailability.entitlementsAllowCloudKit([:], containerIdentifier: CloudConfig.containerIdentifier))
    }

    func testLiveContainerIsLazy() {
        // Constructing the live container and its database views must not create a CKContainer
        // (which would trap in this unentitled process).
        let container = LiveCloudContainer()
        _ = container.privateDatabase
        _ = container.sharedDatabase
        XCTAssertEqual(container.identifier, "iCloud." + AppIdentity.prefix)
    }

    func testKeychainItemAttributes() {
        let id = UUID()
        let query = KeychainDeviceIdentityStore.addQuery(for: id)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false, "never iCloud Keychain")
        XCTAssertEqual(query[kSecAttrService as String] as? String, AppIdentity.prefix + ".device-id")
        XCTAssertEqual(query[kSecValueData as String] as? Data, Data(id.uuidString.lowercased().utf8))
        #if os(macOS)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true, "never the login keychain")
        #endif
    }

    func testCallBenKeychainItemAttributes() {
        let query = KeychainCallBenStore.addQuery(for: "+14155550100")
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false, "never iCloud Keychain")
        XCTAssertEqual(query[kSecAttrService as String] as? String, AppIdentity.prefix + ".callben")
        XCTAssertEqual(query[kSecValueData as String] as? Data, Data("+14155550100".utf8))
        let base = KeychainCallBenStore.baseQuery()
        XCTAssertEqual(base[kSecAttrSynchronizable as String] as? Bool, false)
        #if os(macOS)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true, "never the login keychain")
        XCTAssertEqual(base[kSecUseDataProtectionKeychain as String] as? Bool, true, "read, update and delete too")
        #endif
    }

    func testInMemoryIdentityIsStableAndCanFail() throws {
        let store = InMemoryDeviceIdentityStore()
        let first = try store.deviceID()
        XCTAssertEqual(try store.deviceID(), first)
        store.setFailure(.keychain(-25308))
        XCTAssertThrowsError(try store.deviceID())
        store.setFailure(nil)
        XCTAssertEqual(try store.deviceID(), first)
    }

    func testSettingsRoundTrip() {
        let settings = SyncSettings.inMemory()
        XCTAssertNil(settings.target)
        XCTAssertEqual(settings.connection, .notJoined)
        settings.target = .ownerSelf
        XCTAssertEqual(settings.connection, .connected, "a target without a stored state reads as connected")
        settings.connection = .notConnected
        XCTAssertEqual(settings.connection, .notConnected)
        settings.target = nil
        XCTAssertNil(settings.target)
        XCTAssertFalse(settings.isOwner)
        settings.isOwner = true
        XCTAssertTrue(settings.isOwner)
    }
}

/// §8.4: CloudKit runs `.default` QoS and lower as discretionary work (paused in Low Power Mode on
/// iPhone), so only the periodic report may use `.utility`.
final class CloudPriorityTests: XCTestCase {
    func testLiveDatabaseIsUserInitiatedUnlessAskedForBackground() throws {
        let interactive = LiveCloudDatabase(scope: .private) { fatalError("no CKContainer in tests") }
        XCTAssertEqual(interactive.qualityOfService, .userInitiated)
        let background = try XCTUnwrap(interactive.withPriority(.background) as? LiveCloudDatabase)
        XCTAssertEqual(background.qualityOfService, .utility)
        XCTAssertEqual(background.scope, .private)
    }
}
