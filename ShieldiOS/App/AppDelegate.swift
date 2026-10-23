// CloudKit share acceptance on iPhone (SPEC §8.4 "Family device: enroll"):
// `windowScene(_:userDidAcceptCloudKitShareWith:)` → `CKAcceptSharesOperation` (CloudKitSink) →
// the accepted zone is remembered and this device's `Device` record is saved.
// A cold launch from the share link delivers the metadata in the connection options instead.
// It also installs the notification-center delegate so reminders show while the app is open.

import CloudKit
import ShieldCore
import ShieldUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Reminders found while the app is open are still shown (§5.4); never asks permission.
        // Tapping one opens Home with that check's step.
        ForegroundNotificationPresenter.install()
        ForegroundNotificationPresenter.onOpen = { checkID in
            AppEnvironment.shared.model.openFromNotification(checkID: checkID)
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        accept(metadata)
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            await AppEnvironment.shared.model.acceptShare(metadata)
        }
    }
}
