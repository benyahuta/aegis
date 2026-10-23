// Menu commands (SPEC §11 "Mac: full keyboard navigation"). Every screen is reachable from the
// keyboard: the Go menu (Home ⌘1, Family ⌘2, Back ⌘[ or Escape, Is this a scam? ⌘K, Family Rules,
// Call Ben ⇧⌘B, About & Privacy ⌘,, Check Again ⌘R, which is Refresh on Ben's Family tab) and
// View → text size. Inside a screen, Return presses the screen's main button (Command-Return is
// Next / Done on a fix step that has one), and number keys pick an answer in the call quiz and the
// self-check answers, with macOS defaults; Tab moves between controls when macOS
// Keyboard Navigation is on, and every Family Shield button shows a focus ring.

import AppKit
import SwiftUI
import ShieldCore
import ShieldUI

struct ShieldCommands: Commands {
    let model: AppModel
    let textSize: TextSizeSetting
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // One window only.
        CommandGroup(replacing: .newItem) {}
        // About & Privacy is Family Shield's settings screen.
        CommandGroup(replacing: .appSettings) {
            Button(L.t("about.title")) { go { model.homePath = [.about] } }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(model.onboarding != .done)
        }
        CommandMenu(L.t("command.go")) {
            Button(L.t("command.home")) { go {} }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(model.onboarding != .done)
            if model.isOwner {
                Button(L.t("home.tab.family")) {
                    show()
                    model.selectedTab = .family
                }
                .keyboardShortcut("2", modifiers: .command)
            }
            Button(L.t("command.back")) { MacNavigation.back(model) }
                .keyboardShortcut("[", modifiers: .command)
            Divider()
            Button(L.t("home.isThisAScam")) {
                go {
                    model.clearScam()
                    model.homePath = [.scamEntry]
                }
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(model.onboarding != .done)
            Button(L.t("rules.title")) { go { model.homePath = [.familyRules] } }
                .disabled(model.onboarding != .done)
            // From any screen, with or without macOS Keyboard navigation: menus are always
            // reachable from the keyboard (Control-F2, or this shortcut). With no number picked
            // yet it opens Who to call, like the Call Ben buttons.
            Button(L.t("action.callBen")) {
                if let url = model.callBenURL {
                    NSWorkspace.shared.open(url)
                } else {
                    go { model.homePath = [.whoToCall] }
                }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(model.callBenURL == nil && model.onboarding != .done)
            Divider()
            // ⌘R: Ben's Family tab fetches the latest reports; everywhere else the checks run again.
            Button(model.refreshesDashboard ? L.t("family.refresh") : L.t("command.checkNow")) {
                Task { await model.refreshCurrentTab() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isRefreshingCurrentTab)
        }
        CommandGroup(after: .toolbar) {
            Button(L.t("command.textBigger")) { textSize.bigger() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!textSize.canGrow)
            Button(L.t("command.textSmaller")) { textSize.smaller() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!textSize.canShrink)
            Button(L.t("command.textActual")) { textSize.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(textSize.isDefault)
            Divider()
        }
    }

    private func show() {
        openWindow(id: MainWindow.id)
        NSApplication.shared.activate()
    }

    /// Home tab, then `change`, in the window.
    private func go(_ change: () -> Void) {
        show()
        MacNavigation.home(model)
        change()
    }
}
