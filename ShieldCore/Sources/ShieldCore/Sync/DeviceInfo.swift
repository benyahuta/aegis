// SHARED CONTRACT (scaffold). Every builder depends on this file.
// One synced device: exactly the §8.2 `Device` record fields, nothing else (H5, §12.1).
// No model, OS version, name or label. Labels live only in Ben's `z_admin` (§8.5).

import Foundation

public struct DeviceInfo: Hashable, Codable, Sendable {
    /// Random UUID v4 created on first launch and kept in the Keychain
    /// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Also the CloudKit recordName.
    public var deviceID: UUID
    /// 0 ios / 1 mac.
    public var platform: Platform
    /// Day of enrollment.
    public var enrolledOn: DateDay
    /// `CheckCatalog` version.
    public var catalogVersion: Int
    /// CFBundleVersion as an integer.
    public var appBuild: Int
    /// Day of the latest report.
    public var lastReport: DateDay

    public init(
        deviceID: UUID,
        platform: Platform,
        enrolledOn: DateDay,
        catalogVersion: Int,
        appBuild: Int,
        lastReport: DateDay
    ) {
        self.deviceID = deviceID
        self.platform = platform
        self.enrolledOn = enrolledOn
        self.catalogVersion = catalogVersion
        self.appBuild = appBuild
        self.lastReport = lastReport
    }

    /// CloudKit recordName: the lowercase device UUID.
    public var recordName: String { deviceID.uuidString.lowercased() }
}
