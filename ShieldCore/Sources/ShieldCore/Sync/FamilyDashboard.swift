// Ben's Family tab model (SPEC §8.4 "Ben: dashboard read", "Staleness", §10.3) and the pure
// aggregation rules behind it. Built by OwnerStore from cached CloudKit records; tests build it
// directly from snapshots.

import Foundation

/// How fresh a device's reports are (§8.4 "Staleness (Ben's view)").
public enum DeviceStaleness: String, Sendable, Hashable, Codable {
    /// Reporting normally: show the real statuses.
    case fresh
    /// iPhone > 7 days, Mac > 2 days: grey "Not reporting" chip; checks keep their last values.
    case notReporting
    /// Any device > 14 days (or no `Device` record yet): every chip grey.
    case expired
}

public enum StalenessRules {
    public static let iosNotReportingAfterDays = 7
    public static let macNotReportingAfterDays = 2
    public static let allGreyAfterDays = 14

    /// The staleness for a device whose last report was `lastReport`, seen on `today`.
    public static func staleness(platform: Platform, lastReport: DateDay?, today: DateDay) -> DeviceStaleness {
        guard let lastReport else { return .expired }
        let age = today.days(since: lastReport)
        if age > allGreyAfterDays { return .expired }
        let limit = platform == .ios ? iosNotReportingAfterDays : macNotReportingAfterDays
        return age > limit ? .notReporting : .fresh
    }
}

/// One check on Ben's device detail screen.
public struct DashboardCheck: Sendable, Hashable, Identifiable {
    public var checkID: CheckID
    /// What Ben should see: `.unknown` once the device is `.expired` (H7: stale is grey).
    public var status: Status
    /// What the device last reported.
    public var reportedStatus: Status
    public var source: Source
    public var checkedOn: DateDay
    /// §8.3: the record's creator (or last writer) is not the creator seen at enrollment.
    public var writtenBySomeoneElse: Bool
    /// The tier this check has on Ben's device when it fails (§5.1: computed on the device that
    /// shows it, from `CheckID` plus context; never synced). See `DashboardTiers`.
    public var tier: Tier

    public var id: CheckID { checkID }

    public init(checkID: CheckID, status: Status, reportedStatus: Status, source: Source,
                checkedOn: DateDay, writtenBySomeoneElse: Bool, tier: Tier = .amber) {
        self.checkID = checkID
        self.status = status
        self.reportedStatus = reportedStatus
        self.source = source
        self.checkedOn = checkedOn
        self.writtenBySomeoneElse = writtenBySomeoneElse
        self.tier = tier
    }
}

/// Ben's side of §5.1 "the tier is computed on the device from `CheckID` plus context".
///
/// A relative's device escalates two checks to red from local context that never leaves it (H5):
/// `os_patched` (an actively exploited bug and the fix is out, which needs the OS version) and
/// `remote_access_off` (Screen Sharing open on a Mac unpatched for CVE-2026-65400). Ben's device
/// only gets `CheckID` + `status`, so it rebuilds the context from what it does have: the other
/// statuses of the same device and the compiled `BundledMinimums` table. The rule leans toward
/// red: a red item on the relative's device must never show as amber on Ben's dashboard.
public enum DashboardTiers {
    /// The tier for `checkID` on a device whose current statuses are `statuses`.
    public static func tier(
        for checkID: CheckID,
        statuses: [CheckID: Status],
        platform: Platform?,
        catalog: CheckCatalog = .shared,
        bundled: BundledMinimums = .current
    ) -> Tier {
        guard let entry = catalog[checkID] else { return .amber }
        guard statuses[checkID] == .fail else { return entry.tier }
        switch checkID {
        case .osPatched:
            return entry.effectiveTier(urgent: exploitedFixOut(platform: platform, bundled: bundled))
        case .remoteAccessOff:
            // The CVE-2026-65400 rule needs an unpatched Mac, which on the wire is `os_patched`
            // failing while an exploited fix is out. Ben can't see which port is open, so any open
            // remote-access port on such a Mac counts.
            let unpatched = statuses[.osPatched] == .fail && exploitedFixOut(platform: platform ?? .mac, bundled: bundled)
            return entry.effectiveTier(urgent: unpatched)
        default:
            return entry.tier
        }
    }

    /// True when the compiled table knows an actively exploited bug whose fix is out on an OS line
    /// Apple still patches for `platform` (any platform when nil). A device that fails `os_patched`
    /// is below its line's minimum, so it may be missing that fix.
    public static func exploitedFixOut(platform: Platform?, bundled: BundledMinimums = .current) -> Bool {
        let platforms = platform.map { [$0] } ?? Platform.allCases
        return platforms.contains { platform in
            (bundled.exploitedUnpatchedBelow[platform] ?? []).contains { bundled.lines[platform]?[$0.major] != nil }
        }
    }
}

/// One device row.
public struct DashboardDevice: Sendable, Hashable, Identifiable {
    public var deviceID: UUID
    /// Ben's label (z_admin), or nil when not named yet.
    public var label: String?
    /// Nil only when results arrived before the `Device` record.
    public var platform: Platform?
    public var enrolledOn: DateDay?
    public var lastReport: DateDay?
    public var appBuild: Int?
    public var catalogVersion: Int?
    /// Whole days since `lastReport` (nil without a report).
    public var daysSinceReport: Int?
    public var staleness: DeviceStaleness
    /// The worst-status chip: grey whenever the device is not fresh.
    public var worstStatus: Status
    /// Sorted by check ID wire value.
    public var checks: [DashboardCheck]
    /// §8.3 creator-mismatch flag for the device or any of its records.
    public var creatorMismatch: Bool

    public var id: UUID { deviceID }

    public init(deviceID: UUID, label: String?, platform: Platform?, enrolledOn: DateDay?, lastReport: DateDay?,
                appBuild: Int?, catalogVersion: Int?, daysSinceReport: Int?, staleness: DeviceStaleness,
                worstStatus: Status, checks: [DashboardCheck], creatorMismatch: Bool) {
        self.deviceID = deviceID
        self.label = label
        self.platform = platform
        self.enrolledOn = enrolledOn
        self.lastReport = lastReport
        self.appBuild = appBuild
        self.catalogVersion = catalogVersion
        self.daysSinceReport = daysSinceReport
        self.staleness = staleness
        self.worstStatus = worstStatus
        self.checks = checks
        self.creatorMismatch = creatorMismatch
    }
}

/// One person row (a person zone, or Ben's own `z_self`).
public struct DashboardPerson: Sendable, Hashable, Identifiable {
    public var zoneName: String
    /// True for `z_self` (Ben's own devices).
    public var isSelf: Bool
    /// Ben's label, else the participant's name from the share, else nil.
    public var label: String?
    /// Whether the invited person has accepted the share (nil when unknown; nil for `z_self`).
    public var inviteAccepted: Bool?
    public var devices: [DashboardDevice]
    /// Worst over the person's devices; `.unknown` with no devices.
    public var worstStatus: Status

    public var id: String { zoneName }

    public init(zoneName: String, isSelf: Bool, label: String?, inviteAccepted: Bool?,
                devices: [DashboardDevice], worstStatus: Status) {
        self.zoneName = zoneName
        self.isSelf = isSelf
        self.label = label
        self.inviteAccepted = inviteAccepted
        self.devices = devices
        self.worstStatus = worstStatus
    }
}

/// Everything on the Family tab.
public struct FamilyDashboard: Sendable, Hashable {
    /// People in a stable order: Ben's own devices first, then by label, then zone name.
    public var people: [DashboardPerson]
    public var builtOn: DateDay
    /// The last refresh couldn't fetch some zones; those show their last copy ("Couldn't
    /// refresh. Showing the last copy.").
    public var incomplete: Bool

    public init(people: [DashboardPerson], builtOn: DateDay, incomplete: Bool = false) {
        self.people = people
        self.builtOn = builtOn
        self.incomplete = incomplete
    }

    public static func empty(on day: DateDay) -> FamilyDashboard {
        FamilyDashboard(people: [], builtOn: day)
    }
}

// MARK: - Snapshots (what OwnerStore caches) and aggregation

/// Cached server data for one record: the decoded value plus who wrote it.
public struct RecordAuthorship: Codable, Sendable, Hashable {
    public var creator: String?
    public var lastModifier: String?

    public init(creator: String?, lastModifier: String?) {
        self.creator = creator
        self.lastModifier = lastModifier
    }

    /// True when a known writer differs from `firstCreator`.
    public func differs(from firstCreator: String?) -> Bool {
        guard let firstCreator, !firstCreator.isEmpty else { return false }
        if let creator, creator != firstCreator { return true }
        if let lastModifier, lastModifier != firstCreator { return true }
        return false
    }
}

public struct DeviceSnapshot: Codable, Sendable, Hashable {
    public var info: DeviceInfo
    public var authorship: RecordAuthorship

    public init(info: DeviceInfo, authorship: RecordAuthorship) {
        self.info = info
        self.authorship = authorship
    }
}

public struct ResultSnapshot: Codable, Sendable, Hashable {
    public var result: CheckResult
    public var authorship: RecordAuthorship

    public init(result: CheckResult, authorship: RecordAuthorship) {
        self.result = result
        self.authorship = authorship
    }
}

/// The cached contents of one status zone.
public struct ZoneSnapshot: Codable, Sendable, Hashable {
    public var zoneName: String
    public var devices: [UUID: DeviceSnapshot]
    /// Keyed by record name (`<uuid>_<checkID>`).
    public var results: [String: ResultSnapshot]
    public var participantName: PersonNameComponents?
    public var participantAccepted: Bool?

    public init(zoneName: String, devices: [UUID: DeviceSnapshot] = [:], results: [String: ResultSnapshot] = [:],
                participantName: PersonNameComponents? = nil, participantAccepted: Bool? = nil) {
        self.zoneName = zoneName
        self.devices = devices
        self.results = results
        self.participantName = participantName
        self.participantAccepted = participantAccepted
    }
}

public enum DashboardAggregator {
    /// Builds the Family tab from cached zones and Ben's labels.
    public static func build(
        zones: [ZoneSnapshot],
        personLabels: [String: PersonLabel],
        deviceLabels: [UUID: DeviceLabel],
        today: DateDay,
        catalog: CheckCatalog = .shared
    ) -> FamilyDashboard {
        var people: [DashboardPerson] = []
        for zone in zones where Records.isStatusZoneName(zone.zoneName) {
            let isSelf = zone.zoneName == Records.selfZoneName
            var resultsByDevice: [UUID: [ResultSnapshot]] = [:]
            for snapshot in zone.results.values {
                resultsByDevice[snapshot.result.deviceID, default: []].append(snapshot)
            }
            let deviceIDs = Set(zone.devices.keys).union(resultsByDevice.keys)
            let devices = deviceIDs.map { deviceID in
                device(deviceID: deviceID, snapshot: zone.devices[deviceID],
                       results: resultsByDevice[deviceID] ?? [], label: deviceLabels[deviceID], today: today,
                       catalog: catalog)
            }
            .sorted(by: deviceOrder)

            let label = Records.sanitizeLabel(personLabels[zone.zoneName]?.label)
                ?? zone.participantName.flatMap(formatName)
            people.append(DashboardPerson(
                zoneName: zone.zoneName, isSelf: isSelf, label: label,
                inviteAccepted: isSelf ? nil : zone.participantAccepted,
                devices: devices,
                worstStatus: Status.worst(of: devices.map(\.worstStatus))))
        }
        people.sort { lhs, rhs in
            if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
            let l = lhs.label?.lowercased() ?? "\u{10FFFF}"
            let r = rhs.label?.lowercased() ?? "\u{10FFFF}"
            if l != r { return l < r }
            return lhs.zoneName < rhs.zoneName
        }
        return FamilyDashboard(people: people, builtOn: today)
    }

    static func device(deviceID: UUID, snapshot: DeviceSnapshot?, results: [ResultSnapshot],
                       label: DeviceLabel?, today: DateDay, catalog: CheckCatalog = .shared) -> DashboardDevice {
        let info = snapshot?.info
        let staleness = info.map { StalenessRules.staleness(platform: $0.platform, lastReport: $0.lastReport, today: today) }
            ?? .expired
        let firstCreator = label?.firstCreatorRecordName
        var statuses: [CheckID: Status] = [:]
        for snapshot in results where staleness != .expired {
            statuses[snapshot.result.checkID] = snapshot.result.status
        }
        let checks = results
            .sorted { $0.result.checkID.rawValue < $1.result.checkID.rawValue }
            .map { snapshot in
                DashboardCheck(
                    checkID: snapshot.result.checkID,
                    status: staleness == .expired ? .unknown : snapshot.result.status,
                    reportedStatus: snapshot.result.status,
                    source: snapshot.result.source,
                    checkedOn: snapshot.result.checkedOn,
                    writtenBySomeoneElse: snapshot.authorship.differs(from: firstCreator),
                    tier: DashboardTiers.tier(for: snapshot.result.checkID, statuses: statuses,
                                              platform: info?.platform, catalog: catalog))
            }
        let worst: Status
        if staleness == .fresh {
            worst = Status.worst(of: checks.filter { !CheckID.neverFails.contains($0.checkID) }.map(\.status))
        } else {
            worst = .unknown
        }
        let mismatch = (snapshot?.authorship.differs(from: firstCreator) ?? false)
            || checks.contains(where: \.writtenBySomeoneElse)
        return DashboardDevice(
            deviceID: deviceID,
            label: label.flatMap { Records.sanitizeLabel($0.label) },
            platform: info?.platform,
            enrolledOn: info?.enrolledOn,
            lastReport: info?.lastReport,
            appBuild: info?.appBuild,
            catalogVersion: info?.catalogVersion,
            daysSinceReport: info.map { today.days(since: $0.lastReport) },
            staleness: staleness,
            worstStatus: worst,
            checks: checks,
            creatorMismatch: mismatch)
    }

    private static func deviceOrder(_ lhs: DashboardDevice, _ rhs: DashboardDevice) -> Bool {
        let l = lhs.label?.lowercased() ?? "\u{10FFFF}"
        let r = rhs.label?.lowercased() ?? "\u{10FFFF}"
        if l != r { return l < r }
        let lp = lhs.platform?.rawValue ?? Int.max
        let rp = rhs.platform?.rawValue ?? Int.max
        if lp != rp { return lp < rp }
        return lhs.deviceID.uuidString < rhs.deviceID.uuidString
    }

    /// The participant's name as a label (≤ 40 characters), or nil.
    public static func formatName(_ components: PersonNameComponents) -> String? {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return Records.sanitizeLabel(formatter.string(from: components))
    }
}
