// AppKit hooks for the Mac app:
// - CloudKit share acceptance (SPEC §8.4 "Family device: enroll"): the share link opens Family
//   Shield and AppKit calls `application(_:userDidAcceptCloudKitShareWith:)` → `CKAcceptSharesOperation`
//   (CloudKitSink) → the zone is remembered and this Mac's `Device` record is saved.
//   Needs `CKSharingSupported = YES` in Info.plist.
// - The app stays in the menu bar when the window closes.
// - The check schedule starts at launch.
// - Reminders show while Family Shield is in front (notification-center delegate). Clicking one
//   opens the window on Home with the check's step (the app is menu-bar only, so activating it
//   alone would show nothing).

import AppKit
import CloudKit
import ShieldCore
import ShieldUI

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// `-FSAppearance light|dark` (UI tests): fixes the appearance for this launch only.
    static let appearanceFlag = "-FSAppearance"

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Reminders found while the window is in front are still shown (§5.4); never asks permission.
        ForegroundNotificationPresenter.install()
        ForegroundNotificationPresenter.onOpen = { checkID in
            AppEnvironment.shared.model.openFromNotification(checkID: checkID)
            MacLaunch.requestWindow()
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: Self.appearanceFlag), arguments.index(after: index) < arguments.endIndex {
            switch arguments[arguments.index(after: index)].lowercased() {
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            default: break
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MacLaunch.recordLaunch()
        let environment = AppEnvironment.shared
        MacRefreshSchedule.shared.start(model: environment.model, options: environment.options)
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Log.app.info("share.accept received")
        let model = AppEnvironment.shared.model
        Task { await model.acceptShare(metadata) }
        MacLaunch.requestWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Family Shield again from Finder or Launchpad while it runs shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MacLaunch.requestWindow() }
        return true
    }
}

/// Whether to show the window at launch, and a way for AppKit code to ask SwiftUI to open it.
@MainActor
enum MacLaunch {
    /// Set by `recordLaunch()`: this launch is the login item at sign-in (stay in the menu bar).
    private(set) static var launchedAsLoginItem = false
    /// SwiftUI's `openWindow`, captured by the menu-bar label.
    static var openWindowAction: (() -> Void)?
    private static var pendingWindow = false

    static func recordLaunch() {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// The window opens at launch, except at sign-in once setup is done (§10.2: the menu-bar
    /// shield is enough; the window opens from the menu).
    static func shouldOpenWindowAtLaunch(onboardingDone: Bool) -> Bool {
        !(launchedAsLoginItem && onboardingDone)
    }

    static func requestWindow() {
        if let openWindowAction {
            openWindowAction()
        } else {
            pendingWindow = true
        }
    }

    static func register(openWindow: @escaping () -> Void) {
        openWindowAction = openWindow
        if pendingWindow {
            pendingWindow = false
            openWindow()
        }
    }
}
