// Which hardware this is, in the identifiers SOFA uses (SPEC §5.2 inputs):
//   iOS:   `utsname.machine` (e.g. "iPhone14,5"); on Simulator, `SIMULATOR_MODEL_IDENTIFIER`.
//   macOS: `sysctlbyname("hw.target")` board ID (e.g. "J704AP") for `SupportedDevices`,
//          plus `sysctlbyname("hw.model")` (e.g. "Mac17,2") for `Models`.
//
// §12.2: these identifiers never leave the device. Never sync them; log only with privacy: .private.
// Reading them needs no permission and shows no prompt.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct DeviceIdentifier: Sendable, Hashable {
    /// iOS model identifier ("iPhone14,5") or Mac model identifier ("Mac17,2"). nil if unknown.
    public var modelIdentifier: String?
    /// Mac board ID ("J704AP"). Always nil on iOS.
    public var boardID: String?

    public init(modelIdentifier: String?, boardID: String? = nil) {
        self.modelIdentifier = DeviceIdentifier.clean(modelIdentifier)
        self.boardID = DeviceIdentifier.clean(boardID)
    }

    /// The identifiers to look for in a feed's `SupportedDevices` lists (board ID first).
    public var feedIdentifiers: [String] {
        [boardID, modelIdentifier].compactMap { $0 }
    }

    /// True when nothing is known about the hardware.
    public var isUnknown: Bool { modelIdentifier == nil && boardID == nil }

    /// This device.
    public static var current: DeviceIdentifier {
        resolve(
            platform: .current,
            machine: utsnameMachine(),
            environment: ProcessInfo.processInfo.environment,
            sysctl: sysctlString
        )
    }

    /// Pure resolution logic, injectable for tests.
    /// - Parameters:
    ///   - machine: `utsname.machine`.
    ///   - environment: the process environment (for `SIMULATOR_MODEL_IDENTIFIER`).
    ///   - sysctl: reads a string sysctl such as "hw.target".
    public static func resolve(
        platform: Platform,
        machine: String?,
        environment: [String: String],
        sysctl: (String) -> String?
    ) -> DeviceIdentifier {
        switch platform {
        case .ios:
            if let simulated = clean(environment["SIMULATOR_MODEL_IDENTIFIER"]) {
                return DeviceIdentifier(modelIdentifier: simulated)
            }
            // On Simulator `machine` is the host CPU ("arm64"/"x86_64"), which is not a model.
            guard let machine = clean(machine), !genericMachineNames.contains(machine) else {
                return DeviceIdentifier(modelIdentifier: nil)
            }
            return DeviceIdentifier(modelIdentifier: machine)
        case .mac:
            let model = clean(sysctl("hw.model"))
            let board = clean(sysctl("hw.target"))
            return DeviceIdentifier(
                modelIdentifier: model.flatMap { genericMachineNames.contains($0) ? nil : $0 },
                boardID: board
            )
        }
    }

    /// CPU names that `utsname.machine` / `hw.model` report when they do not name a model.
    static let genericMachineNames: Set<String> = ["arm64", "arm64e", "x86_64", "i386"]

    /// `uname()` → `utsname.machine`.
    public static func utsnameMachine() -> String? {
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { chars in
                // `utsname.machine` is NUL-terminated within its fixed buffer.
                let length = strnlen(chars, capacity)
                let bytes = UnsafeRawBufferPointer(start: chars, count: length)
                return String(decoding: bytes, as: UTF8.self)
            }
        }
    }

    /// `sysctlbyname(name)` as a string, or nil if it does not exist or is empty.
    @Sendable
    public static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size <= 1024 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        let bytes = buffer[..<length].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Trims whitespace and NULs; empty → nil. Rejects anything that is not a plain identifier.
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        guard !trimmed.isEmpty, trimmed.count <= 64,
              trimmed.unicodeScalars.allSatisfy({ allowedScalars.contains($0) })
        else { return nil }
        return trimmed
    }

    private static let allowedScalars = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,-_.")
}
