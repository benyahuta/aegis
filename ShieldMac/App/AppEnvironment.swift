// App-wide dependencies for the Mac app. Built once at launch.

import AppKit
import Foundation
import ShieldCore
import ShieldUI

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment(options: .current)

    let options: LaunchOptions
    let clock: Clock
    let sink: any ResultSink
    /// CloudKit sink, Ben's OwnerStore and the device ID. In-memory for `-FSNoCloud` /
    /// `-FSDemoState` and for builds without the iCloud entitlement.
    let sync: SyncServices
    /// The macOS SOFA feed (cache + bundled snapshot, raise-only, §5.2). Shared by the checks
    /// and the local `feed_fresh` item. Not fetched with `-FSNoCloud`.
    let feed: FeedStore
    /// The §6.2 measured checks, version checks backed by `feed` + VersionEvaluator.
    let checks: MacCheckService
    /// The window and menu-bar text size (View → Bigger Text).
    let textSize: TextSizeSetting
    /// The shared screens' model (ShieldUI).
    let model: AppModel

    init(options: LaunchOptions, clock: Clock = .system) {
        self.options = options
        self.clock = clock
        let sync = SyncServices.make(options: options, clock: clock)
        self.sync = sync
        self.sink = sync.sink
        let feed = FeedStore(platform: .mac, clock: clock)
        self.feed = feed
        let checks = MacCheckService(options: options, clock: clock, feedStore: feed)
        self.checks = checks
        self.textSize = TextSizeSetting(arguments: ProcessInfo.processInfo.arguments, persist: options.demoState == nil)
        let services = PlatformServices(
            measure: {
                let today = clock.today()
                return await checks.run().map { $0.measuredResult(today: today) }
            },
            feedInfo: { FeedInfo(state: await feed.currentFeed(), now: clock.now()) },
            canPickContact: true,
            pickContactNumber: { await MacContactPicker.pick() },
            presentInvite: { invite in
                guard let owner = sync.owner else { return false }
                return MacSharePresenter.present(invite, container: owner.cloudContainer)
            },
            loginItem: MacLoginItem.control,
            mdmExpected: OwnerMacSetting(
                get: { MacCheckService.mdmExpectedDefault() },
                set: { UserDefaults.standard.set($0, forKey: MacCheckService.mdmExpectedDefaultsKey) }
            )
        )
        self.model = AppModel.make(platform: .mac, options: options, sync: sync, services: services, clock: clock)
        Log.app.info("launch noCloud=\(options.noCloud, privacy: .public) demo=\(options.demoState != nil, privacy: .public)")
    }
}
