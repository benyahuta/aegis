// Buttons (SPEC §10 "Primary buttons at least 60 pt tall, full width"; §11 hit targets ≥ 60 pt
// primary, ≥ 44 pt everything else; buttons grow with Dynamic Type and never truncate).

import SwiftUI

public enum ShieldButtonKind: Sendable {
    /// Filled brand blue, white text. One per screen.
    case primary
    /// Soft blue fill, blue text. Same size as primary.
    case secondary
    /// Text-style action, at least 44 pt tall.
    case quiet
    /// Filled green, white text: the "I did it" button right after it is tapped.
    case success
}

public struct ShieldButtonStyle: ButtonStyle {
    let kind: ShieldButtonKind
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    public init(_ kind: ShieldButtonKind = .primary) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: ShieldMetrics.cornerRadius, style: .continuous)
        return configuration.label
            .shieldFont(kind == .quiet ? .body : .title3, weight: .semibold)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 8 : 20)
            .padding(.vertical, kind == .quiet ? 8 : 14)
            .frame(maxWidth: kind == .quiet ? nil : .infinity,
                   minHeight: kind == .quiet ? ShieldMetrics.minHitTarget : ShieldMetrics.primaryButtonMinHeight)
            .background {
                if kind != .quiet {
                    shape.fill(background)
                }
            }
            .overlay {
                if !isEnabled && kind != .quiet {
                    shape.strokeBorder(ShieldPalette.strongOutline.color, lineWidth: 1.5)
                } else if kind == .secondary && contrast == .increased {
                    shape.strokeBorder(ShieldPalette.brandText.color, lineWidth: 2)
                }
            }
            .contentShape(shape)
            .modifier(MacFocusRing(shape: shape))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .modifier(PressScale(isPressed: configuration.isPressed && kind != .quiet))
    }

    /// A disabled button is grey with readable text (≥ 4.5:1, §11) instead of a faded copy of
    /// the enabled one: "not yet" should still be legible, it just isn't blue.
    private var foreground: Color {
        if !isEnabled { return ShieldPalette.textSecondary.color }
        return switch kind {
        case .primary: ShieldPalette.onBrand.color
        case .secondary, .quiet: ShieldPalette.brandText.color
        case .success: ShieldPalette.onDarkFill.color
        }
    }

    private var background: Color {
        if !isEnabled { return kind == .quiet ? .clear : ShieldPalette.disabledFill.color }
        return switch kind {
        case .primary: ShieldPalette.brand.color
        case .secondary: ShieldPalette.brandSoft.color
        case .quiet: .clear
        case .success: ShieldPalette.greenFill.color
        }
    }
}

/// A small squish while a big button is held down, so a tap feels like a press.
/// Skipped with Reduce Motion (§11); the opacity change above still shows the press.
private struct PressScale: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }
}

/// Mac keyboard navigation (§11): a clear 3 pt ring around the focused button, drawn by us so
/// it follows the rounded shape and has enough contrast. iPhone: nothing changes.
struct MacFocusRing<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .focusEffectDisabled()
            .overlay { FocusRingOverlay(shape: shape) }
        #else
        content
        #endif
    }
}

#if os(macOS)
private struct FocusRingOverlay<S: InsettableShape>: View {
    let shape: S
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        if isFocused {
            shape
                .inset(by: -4)
                .strokeBorder(ShieldPalette.brandText.color, lineWidth: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
#endif

extension View {
    /// On the Mac, a large switch instead of the small checkbox (easier to see on or off).
    public func shieldToggleStyle() -> some View {
        #if os(macOS)
        self.toggleStyle(.switch).controlSize(.large)
        #else
        self
        #endif
    }
}

extension ButtonStyle where Self == ShieldButtonStyle {
    public static var shieldPrimary: ShieldButtonStyle { ShieldButtonStyle(.primary) }
    public static var shieldSecondary: ShieldButtonStyle { ShieldButtonStyle(.secondary) }
    public static var shieldQuiet: ShieldButtonStyle { ShieldButtonStyle(.quiet) }
}

/// A button label with a leading SF Symbol that stacks under the text at accessibility sizes.
public struct ButtonLabel: View {
    let title: String
    let systemImage: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    nonisolated public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        if let systemImage {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 6))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(title)
            }
        } else {
            Text(title)
        }
    }
}
