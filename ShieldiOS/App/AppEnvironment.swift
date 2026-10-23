// App-wide dependencies for the iPhone app. Built once at launch.

import Foundation
import ShieldCore
import ShieldUI

@MainActor
final class AppEnvironment {
    /// The one environment for this process (the scene delegate reaches it for share acceptance).
    static let shared = AppEnvironment(options: .current)

    let options: LaunchOptions
    let clock: Clock
    let sink: any ResultSink
    /// CloudKit sink, Ben's OwnerStore and the device ID. In-memory for `-FSNoCloud` /
    /// `-FSDemoState` and for builds without the iCloud entitlement.
    let sync: SyncServices
    /// The iOS SOFA feed (cache + bundled snapshot, raise-only, §5.2).
    let feed: FeedStore
    let checks: IOSChecks
    let model: AppModel

    init(options: LaunchOptions, clock: Clock = .system) {
        self.options = options
        self.clock = clock
        let sync = SyncServices.make(options: options, clock: clock)
        self.sync = sync
        self.sink = sync.sink
        let feed = FeedStore(platform: .ios, clock: clock)
        self.feed = feed
        let checks = IOSChecks(feed: feed, clock: clock, build: .current)
        self.checks = checks
        let services = PlatformServices(
            measure: { await checks.measure() },
            feedInfo: { await checks.feedInfo() },
            canPickContact: true,
            pickContactNumber: { await ContactPhonePicker.pick() },
            presentInvite: { invite in
                guard let owner = sync.owner else { return false }
                return CloudSharingPresenter.present(invite, container: owner.cloudContainer)
            },
            didRefresh: { BackgroundRefresh.schedule(options: options) }
        )
        self.model = AppModel.make(platform: .ios, options: options, sync: sync, services: services, clock: clock)
        Log.app.info("launch noCloud=\(options.noCloud, privacy: .public) demo=\(options.demoState != nil, privacy: .public)")
    }
}
