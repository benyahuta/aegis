// Focus and keyboard helpers (SPEC §11):
// - Multi-step screens change their content in place (call quiz, fix steps, Family Rules, account
//   steps, guided answers). VoiceOver focus would stay on a button that moved or was removed, so
//   the new question / step / response takes VoiceOver focus and is read out.
// - Outcomes that appear in place (a denied permission, "Nothing is copied", an invite result)
//   either take VoiceOver focus (when the button the person was on went away) or are announced.
// - Mac keyboard: the one main button on a screen answers Return (`.defaultAction`), so a screen
//   can be finished from the keyboard even with macOS "Keyboard navigation" off (the default);
//   Next / Done on step screens answer Command-Return when Return is taken.

import SwiftUI

/// Says `text` with VoiceOver (and the Mac's VoiceOver), for an outcome that appears beside the
/// button the person is still on ("Nothing is copied", "Invite ready"): their focus stays put and
/// they still hear what happened. A short delay lets the new text reach the screen first.
@MainActor
public func announceForAccessibility(_ text: String) {
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(200))
        AccessibilityNotification.Announcement(text).post()
    }
}

/// Moves VoiceOver focus to the modified view each time `value` changes.
struct AccessibilityFocusOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            .onChange(of: value) { _, _ in
                focused = false
                Task { @MainActor in
                    // Let the new content reach the accessibility tree first.
                    try? await Task.sleep(for: .milliseconds(150))
                    focused = true
                }
            }
    }
}

/// Moves VoiceOver focus to the modified view when it appears (if `enabled`).
struct AccessibilityFocusOnAppear: ViewModifier {
    let enabled: Bool
    @AccessibilityFocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($focused)
            .onAppear {
                guard enabled else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    focused = true
                }
            }
    }
}

extension View {
    /// VoiceOver focus moves here whenever `value` changes (a new step or question).
    public func accessibilityFocusOnChange<Value: Equatable>(of value: Value) -> some View {
        modifier(AccessibilityFocusOnChange(value: value))
    }

    /// VoiceOver focus moves here when this view appears (a response replacing the buttons).
    /// `enabled: false` for a notice that can also be there when the screen opens, so opening the
    /// screen doesn't jump past its heading: pass true only once the person has acted.
    public func accessibilityFocusOnAppear(_ enabled: Bool = true) -> some View {
        modifier(AccessibilityFocusOnAppear(enabled: enabled))
    }

    /// Next / Done on a step screen: Return when the screen has no other main button, otherwise
    /// Command-Return (Return belongs to the main button, `shieldDefaultAction`).
    public func shieldStepShortcut(secondary: Bool) -> some View {
        keyboardShortcut(.return, modifiers: secondary ? .command : [])
    }

    /// The screen's main button: Return presses it (Mac, and iPhone with a keyboard).
    /// Use on at most one visible button per screen.
    public func shieldDefaultAction(_ enabled: Bool = true) -> some View {
        keyboardShortcut(enabled ? .defaultAction : nil)
    }

    /// The n-th answer in a list of choices: the number key presses it (1–9), so the quiz and
    /// the self-check answers work from the keyboard too.
    @ViewBuilder
    public func shieldNumberShortcut(_ number: Int) -> some View {
        if (1...9).contains(number), let character = "\(number)".first {
            keyboardShortcut(KeyEquivalent(character), modifiers: [])
        } else {
            self
        }
    }
}
