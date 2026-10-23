// SHARED CONTRACT. The reverse-DNS prefix every identifier the apps own starts with: Keychain
// item names, the iCloud container, the background task and the log subsystem. It is set once
// in Config/Identity.xcconfig (FS_ID_PREFIX) and reaches the apps as Info.plist `FSIDPrefix`.
// Tests and command-line tools have no such key and use the placeholder.

import Foundation

public enum AppIdentity {
    public static let placeholderPrefix = "org.example.aegis"

    public static let prefix: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FSIDPrefix") as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return placeholderPrefix }
        return value
    }()
}
