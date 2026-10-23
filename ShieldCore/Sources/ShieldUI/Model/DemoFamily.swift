// Sample Family tab data (SPEC §10.3) for `-FSDemoState` screens and copies without iCloud.
// Built through the real DashboardAggregator, so staleness and worst-status rules are the real ones.
// Labels are invented ("Mom", "Dad"); no real person's data is involved.

import Foundation
import ShieldCore

public enum DemoFamily {
    public static let thisDevice = UUID(uuidString: "6F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F1")!
    public static let momZone = "z_0f1e2d3c4b5a6978"
    public static let dadZone = "z_8695a4b3c2d1e0f1"
    public static let grandmaZone = "z_1a2b3c4d5e6f7a8b"
    public static let momPhone = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    public static let momMac = UUID(uuidString: "21111111-2222-4333-8444-555555555555")!
    public static let dadPhone = UUID(uuidString: "31111111-2222-4333-8444-555555555555")!
    public static let benPhone = UUID(uuidString: "41111111-2222-4333-8444-555555555555")!
    public static let benMac = UUID(uuidString: "51111111-2222-4333-8444-555555555555")!
    /// Never shown on screen; only makes the demo "Call Ben" button active.
    public static let benNumber = "5550100"

    public static func dashboard(today: DateDay, catalog: CheckCatalog) -> FamilyDashboard {
        let creator = "_demo_creator"
        func device(_ id: UUID, _ platform: Platform, daysAgo: Int, overrides: [CheckID: Status] = [:]) -> (DeviceSnapshot, [ResultSnapshot]) {
            let reported = today.adding(days: -daysAgo)
            let info = DeviceInfo(deviceID: id, platform: platform, enrolledOn: today.adding(days: -40),
                                  catalogVersion: catalog.version, appBuild: 12, lastReport: reported)
            let authorship = RecordAuthorship(creator: creator, lastModifier: creator)
            let results = syncedChecks(catalog: catalog, platform: platform).map { id, source in
                let status = overrides[id] ?? (id.isAccountRollup ? .unknown : .pass)
                return ResultSnapshot(
                    result: CheckResult(deviceID: info.deviceID, checkID: id, status: status, source: source,
                                        checkedOn: reported, catalogVersion: catalog.version),
                    authorship: authorship)
            }
            return (DeviceSnapshot(info: info, authorship: authorship), results)
        }

        func zone(_ name: String, devices: [(DeviceSnapshot, [ResultSnapshot])], accepted: Bool?) -> ZoneSnapshot {
            var deviceMap: [UUID: DeviceSnapshot] = [:]
            var resultMap: [String: ResultSnapshot] = [:]
            for (snapshot, results) in devices {
                deviceMap[snapshot.info.deviceID] = snapshot
                for result in results { resultMap[result.result.recordName] = result }
            }
            return ZoneSnapshot(zoneName: name, devices: deviceMap, results: resultMap, participantAccepted: accepted)
        }

        let zones = [
            zone(Records.selfZoneName, devices: [
                device(benPhone, .ios, daysAgo: 0, overrides: Dictionary(uniqueKeysWithValues: CheckID.accountRollups.map { ($0, .pass) })),
                device(benMac, .mac, daysAgo: 0, overrides: [.osPatched: .fail, .osUpdateStuck: .fail,
                                                              .betaCatalog: .fail, .firewall: .fail]),
            ], accepted: nil),
            zone(momZone, devices: [
                device(momPhone, .ios, daysAgo: 0, overrides: [.osPatched: .fail, .stolenDeviceProtection: .unknown,
                                                               .accountsEmail: .pass, .accountsMoney: .unknown]),
                device(momMac, .mac, daysAgo: 1),
            ], accepted: true),
            zone(dadZone, devices: [device(dadPhone, .ios, daysAgo: 9)], accepted: true),
            zone(grandmaZone, devices: [], accepted: false),
        ]
        let now = today.date
        let personLabels = [
            momZone: PersonLabel(zoneName: momZone, label: "Mom", createdOn: now),
            dadZone: PersonLabel(zoneName: dadZone, label: "Dad", createdOn: now),
            grandmaZone: PersonLabel(zoneName: grandmaZone, label: "Grandma", createdOn: now),
        ]
        let deviceLabels = [
            momPhone: DeviceLabel(deviceID: momPhone, label: "Mom's iPhone", firstCreatorRecordName: creator),
            momMac: DeviceLabel(deviceID: momMac, label: "Mom's Mac", firstCreatorRecordName: creator),
            dadPhone: DeviceLabel(deviceID: dadPhone, label: "Dad's iPhone", firstCreatorRecordName: creator),
            benPhone: DeviceLabel(deviceID: benPhone, label: "Ben's iPhone", firstCreatorRecordName: creator),
            benMac: DeviceLabel(deviceID: benMac, label: "Ben's Mac", firstCreatorRecordName: creator),
        ]
        return DashboardAggregator.build(zones: zones, personLabels: personLabels, deviceLabels: deviceLabels, today: today)
    }

    /// The P0 checks a device of `platform` syncs, with their source.
    static func syncedChecks(catalog: CheckCatalog, platform: Platform) -> [(CheckID, Source)] {
        catalog.entries(for: platform).compactMap { entry in
            guard entry.priority == .p0, let variant = entry.variant(for: platform), variant.kind != .optional else { return nil }
            return (entry.id, variant.source)
        }
    }
}
