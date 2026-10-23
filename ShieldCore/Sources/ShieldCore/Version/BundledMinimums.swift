// The compiled-in minimum patched versions (SPEC §5.2 step 1), dated 2026-10-22.
// These are the floor of the raise-only rule: no feed can ever lower them.
//
// Update this table (and `asOf`) with every app build that ships after an Apple security release,
// then refresh snapshot/ios_min.json and snapshot/mac_min.json from SOFA v2.

import Foundation

public struct BundledMinimums: Sendable, Hashable {
    /// One OS line's minimum. `deviceOverrides` raises (or sets) the minimum for specific identifiers.
    public struct Line: Sendable, Hashable {
        public var minimum: OSVersion
        public var deviceOverrides: [String: OSVersion]

        public init(minimum: OSVersion, deviceOverrides: [String: OSVersion] = [:]) {
            self.minimum = minimum
            self.deviceOverrides = deviceOverrides
        }

        /// The minimum for this device: its override if it has one, else the line minimum.
        public func minimum(for device: DeviceIdentifier) -> OSVersion {
            for id in device.feedIdentifiers {
                if let override = deviceOverrides[id] { return override }
            }
            return minimum
        }

        /// The highest minimum on this line for any device (used to reject rollback feeds).
        public var highest: OSVersion {
            ([minimum] + deviceOverrides.values).max() ?? minimum
        }
    }

    /// The day this table was last checked against Apple and SOFA.
    public var asOf: DateDay
    /// platform → major → line. Majors that are absent are not patched any more (or are newer
    /// than this table; the feed decides those).
    public var lines: [Platform: [Int: Line]]
    /// platform → versions below which an actively exploited bug is known to be unpatched
    /// (each applies to its own major only).
    public var exploitedUnpatchedBelow: [Platform: [OSVersion]]

    public init(asOf: DateDay, lines: [Platform: [Int: Line]], exploitedUnpatchedBelow: [Platform: [OSVersion]]) {
        self.asOf = asOf
        self.lines = lines
        self.exploitedUnpatchedBelow = exploitedUnpatchedBelow
    }

    /// iPhone XS, XS Max (two IDs) and XR: on iOS 18 only, with device-specific 18.7.x releases.
    public static let iPhoneXSFamily: Set<String> = ["iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8"]

    /// The table as of 2026-10-22 (§5.2 step 1).
    public static let current = BundledMinimums(
        asOf: DateDay(year: 2026, month: 10, day: 22)!,
        lines: [
            .ios: [
                27: Line(minimum: OSVersion(27, 0, 1)),
                26: Line(minimum: OSVersion(26, 7, 1)),
                18: Line(
                    minimum: OSVersion(18, 7, 8),
                    deviceOverrides: Dictionary(uniqueKeysWithValues: iPhoneXSFamily.map { ($0, OSVersion(18, 7, 10)) })
                ),
            ],
            .mac: [
                27: Line(minimum: OSVersion(27, 0, 1)),
                26: Line(minimum: OSVersion(26, 7, 1)),
                15: Line(minimum: OSVersion(15, 8, 1)),
                14: Line(minimum: OSVersion(14, 8, 9)),
            ],
        ],
        exploitedUnpatchedBelow: [
            // CVE-2026-86950.
            .ios: [OSVersion(26, 7, 1)],
            .mac: [OSVersion(26, 7, 1), OSVersion(15, 8, 1)],
        ]
    )

    /// The patched majors for `platform`, highest first.
    public func majors(for platform: Platform) -> [Int] {
        (lines[platform] ?? [:]).keys.sorted(by: >)
    }

    /// The newest major in the table ("the current one", §5.2 step 6).
    public func currentMajor(for platform: Platform) -> Int? {
        majors(for: platform).first
    }

    /// The lowest major the table still patches. Anything below is an unsupported OS line.
    public func oldestPatchedMajor(for platform: Platform) -> Int? {
        majors(for: platform).last
    }

    /// `bundledMin[platform][major]` for this device, or nil when the table has no such major.
    public func minimum(platform: Platform, major: Int, device: DeviceIdentifier) -> OSVersion? {
        lines[platform]?[major]?.minimum(for: device)
    }

    /// The highest bundled minimum for `major` on any device (rollback floor).
    public func highestMinimum(platform: Platform, major: Int) -> OSVersion? {
        lines[platform]?[major]?.highest
    }

    /// True when a bundled `exploitedUnpatchedBelow` threshold on the same major is above `version`.
    public func knownExploited(platform: Platform, version: OSVersion) -> Bool {
        (exploitedUnpatchedBelow[platform] ?? []).contains { $0.major == version.major && version < $0 }
    }

    /// What the table alone knows about device support, without a feed.
    public enum DeviceKnowledge: Sendable, Hashable {
        /// Apple no longer ships fixes for this model (iPhone 8/X and older).
        case unsupported
        /// Still patched; `highestMajor` is the newest major it can run.
        case supported(highestMajor: Int)
        /// The table does not know this model.
        case unknown
    }

    /// iOS: `iPhone10,*` and older → unsupported; `iPhone11,*` (XS/XR) → 18 only; `iPhone12,*`+ → current.
    /// macOS: unknown (only the feed's `Models` table knows Mac support).
    public func deviceKnowledge(platform: Platform, device: DeviceIdentifier) -> DeviceKnowledge {
        guard platform == .ios, let model = device.modelIdentifier, model.hasPrefix("iPhone") else { return .unknown }
        let digits = model.dropFirst("iPhone".count).prefix { $0.isASCII && $0.isNumber }
        guard let generation = Int(digits) else { return .unknown }
        if generation <= 10 { return .unsupported }
        if BundledMinimums.iPhoneXSFamily.contains(model) { return .supported(highestMajor: 18) }
        if generation == 11 { return .unknown }
        guard let current = currentMajor(for: .ios) else { return .unknown }
        return .supported(highestMajor: current)
    }
}
