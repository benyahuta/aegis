// An OS version number such as 26.7.1 (SPEC §5.2: "judge by version comparison only").
// Compared numerically part by part, so 18.7.10 > 18.7.8 and 26.7 == 26.7.0.
// Stays on the device: never synced, never logged except with privacy: .private (§12.2).

import Foundation

public struct OSVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Major, minor, patch, ... Always at least one element; trailing zeros are trimmed
    /// (except the major), so `26.7.0` and `26.7` are equal and hash the same.
    public let components: [Int]

    /// Negative parts are clamped to 0.
    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.init(trimming: [max(0, major), max(0, minor), max(0, patch)])
    }

    /// Returns nil for an empty list or any negative component.
    public init?(components: [Int]) {
        guard !components.isEmpty, components.allSatisfy({ $0 >= 0 }) else { return nil }
        self.init(trimming: components)
    }

    private init(trimming components: [Int]) {
        var trimmed = components
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        self.components = trimmed
    }

    /// Parses "26.7.1", "27", "15.8.1 (a)" (a suffix after the numbers is ignored).
    /// Returns nil when the string does not start with a number.
    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        var numbers: [Int] = []
        var current = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character.isASCII, character.isNumber {
                current.append(character)
                guard current.count <= 9 else { return nil }
            } else if character == "." {
                guard let value = Int(current) else { return nil }
                numbers.append(value)
                current = ""
            } else {
                break
            }
            index = trimmed.index(after: index)
        }
        if !current.isEmpty {
            guard let value = Int(current) else { return nil }
            numbers.append(value)
        } else if !numbers.isEmpty {
            // "26." is malformed.
            return nil
        }
        guard !numbers.isEmpty, numbers.count <= 6 else { return nil }
        self.init(components: numbers)
    }

    /// The running OS (`ProcessInfo.processInfo.operatingSystemVersion`).
    public init(_ version: OperatingSystemVersion) {
        self.init(version.majorVersion, version.minorVersion, version.patchVersion)
    }

    /// The version of the OS this process runs on.
    public static var running: OSVersion {
        OSVersion(ProcessInfo.processInfo.operatingSystemVersion)
    }

    public var major: Int { components[0] }
    public var minor: Int { components.count > 1 ? components[1] : 0 }
    public var patch: Int { components.count > 2 ? components[2] : 0 }

    /// "26.7.1". A version with only a major prints as "27.0" (never as a bare "27").
    public var description: String {
        components.count == 1 ? "\(components[0]).0" : components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: OSVersion, rhs: OSVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

extension OSVersion: Codable {
    /// Encoded as a string such as "26.7.1".
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let version = OSVersion(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an OS version")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
