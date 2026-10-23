// The menu-bar shield (SPEC §10.2): a word, "Protected", "1 to do" or "Today". No counts out of
// totals. The window it opens holds everything else. Both views come from ShieldUI
// (`MenuBarLabelContent`, `MenuBarPanel`), so screenshots and tests render the same thing.

import AppKit
import SwiftUI
import ShieldCore
import ShieldUI

struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabelContent(model: model)
            .task {
                // The label exists from launch, so it hands SwiftUI's openWindow to AppKit code
                // and opens the window unless this is the login item at sign-in.
                MacLaunch.register { openMainWindow(openWindow) }
                if MacLaunch.shouldOpenWindowAtLaunch(onboardingDone: model.onboarding == .done) {
                    openMainWindow(openWindow)
                }
            }
    }
}

struct MenuBarContent: View {
    let model: AppModel
    let textSize: TextSizeSetting
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarPanel(model: model, openWindow: { openMainWindow(openWindow) }, quit: {
            NSApplication.shared.terminate(nil)
        })
        .dynamicTypeSize(textSize.size)
    }
}

@MainActor
func openMainWindow(_ openWindow: OpenWindowAction) {
    openWindow(id: MainWindow.id)
    NSApplication.shared.activate()
}
