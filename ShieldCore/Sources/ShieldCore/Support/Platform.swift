// SHARED CONTRACT (scaffold). Every builder depends on this file.
// `Platform` is a wire format (CloudKit `Device.platform`, Int64: 0 = ios, 1 = mac; SPEC §8.2).

import Foundation

public enum Platform: Int, CaseIterable, Codable, Sendable, Hashable {
    case ios = 0
    case mac = 1
}

extension Platform {
    /// The platform this binary was compiled for.
    public static var current: Platform {
        #if os(macOS)
        .mac
        #else
        .ios
        #endif
    }

    public init?(wireValue: Int64) {
        guard let value = Int(exactly: wireValue), let platform = Platform(rawValue: value) else { return nil }
        self = platform
    }

    public var wireValue: Int64 { Int64(rawValue) }
}
