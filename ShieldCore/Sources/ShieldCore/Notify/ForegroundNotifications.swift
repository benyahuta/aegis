// Shows Family Shield's reminders while the app is open (SPEC §5.4 "1 + 1"), and opens the
// failing check when the person taps or clicks one.
//
// Opening: a notification response goes to this delegate's `didReceive`. Without it the system
// only activates the app, and the Mac app (a menu-bar app whose window is normally closed) then
// shows nothing at all. `onOpen` is set by each app at launch (Mac: open the window; both: Home
// with the check's step).
//
// The first reminder is scheduled with no delay right after a check, and checks almost always run
// with the app in front (foreground, pull to refresh, after a fix). Without a notification-center
// delegate, the system drops a notification delivered to the frontmost app, so the person's first
// alert would silently become the "+3 days" reminder. The delegate asks for a banner, a
// Notification Center entry and the sound. It never asks for permission.

import Foundation
@preconcurrency import UserNotifications

public final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    /// How a reminder is presented while Family Shield is in front.
    public static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

    /// The notification center keeps its delegate weakly; this keeps it alive.
    public static let shared = ForegroundNotificationPresenter()

    /// Sets the delegate. Call once at launch, before the app finishes launching. A no-op outside
    /// a real `.app` bundle (tests, the headless check run).
    public static func install() {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().delegate = shared
    }

    /// The app's "open this reminder" action (the check it is about, when known). Set once at
    /// launch on the main actor.
    @MainActor public static var onOpen: (@MainActor (CheckID?) -> Void)?

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Self.foregroundOptions
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let request = response.notification.request
        let checkID = ReminderPlanner.checkID(userInfo: request.content.userInfo, identifier: request.identifier)
        Log.notify.info("notify.opened check=\(checkID?.rawValue ?? "-", privacy: .public)")
        await Self.open(checkID)
    }

    @MainActor static func open(_ checkID: CheckID?) {
        onOpen?(checkID)
    }
}
