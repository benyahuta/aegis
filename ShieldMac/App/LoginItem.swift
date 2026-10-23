// The login item (SPEC §2 C3, §10.2): the app registers ITSELF with `SMAppService.mainApp`.
// There is no helper executable.
//
// `register()` runs only from the first-launch **[Keep checking in the background]** button (and
// the same button in About). Nothing calls it at launch, in demo states or in tests. If macOS
// answers `.requiresApproval`, the button opens System Settings → Login Items with the copy
// "Turn on Family Shield". Reading `status` never shows UI.

import AppKit
import ServiceManagement
import ShieldCore
import ShieldUI

@MainActor
enum MacLoginItem {
    static var control: LoginItemControl {
        LoginItemControl(status: status, register: register, openSettings: openSettings)
    }

    static func state(_ status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .notRegistered: .off
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static func status() -> LoginItemState {
        state(SMAppService.mainApp.status)
    }

    /// Only from the button. Never retried automatically. When macOS refuses (for example a copy
    /// run from a disk image or outside Applications) and the item is still off, the answer is
    /// `.unavailable` ("Ben will turn on background checks"), never the same button again.
    static func register() -> LoginItemState {
        var failed = false
        do {
            try SMAppService.mainApp.register()
            Log.app.info("loginItem.register ok")
        } catch {
            failed = true
            // The error code only (an enum value, no personal data).
            Log.app.notice("loginItem.register failed code=\((error as NSError).code, privacy: .public)")
        }
        let result = LoginItemState.afterRegister(status: status(), threw: failed)
        Log.app.info("loginItem.state \(result.rawValue, privacy: .public)")
        return result
    }

    static func openSettings() {
        guard let url = DeepLink.macLoginItems.url else { return }
        NSWorkspace.shared.open(url)
    }
}
