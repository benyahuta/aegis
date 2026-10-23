// Family Shield for iPhone (SPEC §2 C2).
// - One WindowGroup with the shared ShieldUI RootView over the AppModel.
// - Re-checks on every foreground (§8.4 "When: on app foreground"), and on the opportunistic
//   BGAppRefreshTask `<FS_ID_PREFIX>.ios.refresh`.
// - CloudKit share acceptance comes in through the scene delegate (AppDelegate.swift).

import BackgroundTasks
import SwiftUI
import ShieldCore
import ShieldUI

@main
struct ShieldiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView(model: environment.model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await environment.model.refresh() }
            case .background:
                BackgroundRefresh.schedule(options: environment.options)
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

/// The opportunistic background report (§8.4). Never runs for `-FSNoCloud` / `-FSDemoState`.
enum BackgroundRefresh {
    static let identifier = AppIdentity.prefix + ".ios.refresh"
    /// Ask for no more than one run every 6 hours (the feed fetch is throttled to that anyway).
    static let interval: TimeInterval = 6 * 60 * 60

    @MainActor
    static func schedule(options: LaunchOptions) {
        guard !options.noCloud else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.app.notice("bg.schedule.failed")
        }
    }

    @MainActor
    static func run() async {
        let environment = AppEnvironment.shared
        guard !environment.options.noCloud else { return }
        await environment.model.refresh()
        schedule(options: environment.options)
    }
}
