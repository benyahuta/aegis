// Family Shield for Mac (SPEC §2 C3): an LSUIElement MenuBarExtra app with one window.
// - Menu bar: a shield and a word, "Protected", "1 to do" or "Today" (§10.2).
// - Window: the shared ShieldUI screens, at least 600×500 pt, full keyboard navigation (Go menu,
//   View → text size, ⌘[ back, Tab through every control) (§11).
// - Checks run at launch, every 24 h, on wake and when the app comes back to the front (§8.4).
// - The login item (SMAppService.mainApp) is registered ONLY from the first-launch
//   "Keep checking in the background" button (§10.2). Nothing here registers it.
//
// The MenuBarExtra is the first scene, so SwiftUI does not open the window by itself; the menu-bar
// label opens it at launch unless this launch is the login item at sign-in (`MacLaunch`).

import AppKit
import SwiftUI
import ShieldCore
import ShieldUI

struct ShieldMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: environment.model, textSize: environment.textSize)
        } label: {
            MenuBarLabel(model: environment.model)
        }
        .menuBarExtraStyle(.window)

        Window("Family Shield", id: MainWindow.id) {
            MainWindowContent(model: environment.model, textSize: environment.textSize)
        }
        .defaultSize(width: MainWindow.defaultWidth, height: MainWindow.defaultHeight)
        .windowResizability(.contentMinSize)
        .commands {
            ShieldCommands(model: environment.model, textSize: environment.textSize)
        }
    }
}

enum MainWindow {
    static let id = "main"
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 760
}

/// The window's root: the shared screens at the Mac's text size.
struct MainWindowContent: View {
    let model: AppModel
    let textSize: TextSizeSetting

    var body: some View {
        RootView(model: model)
            .dynamicTypeSize(textSize.size)
            .frame(minWidth: ShieldMetrics.macWindowMinWidth, minHeight: ShieldMetrics.macWindowMinHeight)
            .onExitCommand { MacNavigation.back(model) }
            .onAppear { Log.app.info("window.shown") }
    }
}

/// Back / Home for the Go menu and Escape.
@MainActor
enum MacNavigation {
    static func back(_ model: AppModel) {
        if model.onboarding != .done {
            if !model.onboardingPath.isEmpty { model.onboardingPath.removeLast() }
        } else if model.isOwner && model.selectedTab == .family {
            if !model.familyPath.isEmpty { model.familyPath.removeLast() }
        } else {
            model.pop()
        }
    }

    static func home(_ model: AppModel) {
        model.selectedTab = .home
        model.popToHome()
    }

}

/// Every 24 h, on wake and on coming back to the front (§8.4). Not for demo states, which never
/// measure. The decisions are `RefreshPolicy` (ShieldCore, unit-tested).
@MainActor
final class MacRefreshSchedule {
    static let shared = MacRefreshSchedule()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private weak var model: AppModel?

    func start(model: AppModel, options: LaunchOptions) {
        guard timer == nil else { return }
        self.model = model
        Task { await model.start() }
        guard options.demoState == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: RefreshPolicy.tick, repeats: true) { _ in
            Task { @MainActor in MacRefreshSchedule.shared.trigger(.timer) }
        }
        timer?.tolerance = 5 * 60
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in MacRefreshSchedule.shared.trigger(.wake) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in MacRefreshSchedule.shared.trigger(.activated) }
        })
    }

    func trigger(_ trigger: RefreshTrigger) {
        guard let model else { return }
        if trigger == .activated { model.refreshLoginItemState() }
        guard RefreshPolicy.shouldRefresh(trigger, lastChecked: model.lastCheckedAt, now: model.clock.now()) else { return }
        Log.app.info("refresh trigger=\(trigger.rawValue, privacy: .public)")
        Task { await model.refresh() }
    }
}
