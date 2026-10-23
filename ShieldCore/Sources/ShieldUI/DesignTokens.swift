// SHARED CONTRACT (scaffold). Every UI builder depends on this file.
// Design tokens for SPEC §10 global rules and §11 accessibility:
//   - Every status shows color + SF Symbol + word (never color alone):
//       green `checkmark.shield.fill` "Done"
//       amber `exclamationmark.triangle.fill` "To do" (dark text on amber)
//       red   `exclamationmark.octagon.fill` "Today"
//       grey  `questionmark.circle` "Can't check"
//   - Contrast >= 4.5:1 for text and >= 3:1 for icons, in light AND dark (ShieldUITests checks it).
//   - Primary buttons >= 60 pt tall, full width; other hit targets >= 44 pt.
//   - No countdowns, threat counts, flashing, "CRITICAL" or percentages.

import SwiftUI
import ShieldCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Color primitives

/// An sRGB color with WCAG 2.x luminance and contrast math, so tokens are testable without rendering.
public struct RGBColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `RGBColor(hex: 0x1E7B34)`.
    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio (1...21).
    public func contrastRatio(with other: RGBColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

/// A color with a light and a dark variant that follows the system appearance.
public struct DynamicColor: Hashable, Sendable {
    public let light: RGBColor
    public let dark: RGBColor

    public init(light: RGBColor, dark: RGBColor) {
        self.light = light
        self.dark = dark
    }

    public init(light: UInt32, dark: UInt32) {
        self.init(light: RGBColor(hex: light), dark: RGBColor(hex: dark))
    }

    /// A SwiftUI color that switches with light/dark mode.
    public var color: Color {
        let light = self.light, dark = self.dark
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #else
        return light.color
        #endif
    }
}

// MARK: - Status appearance

/// The four ways a status is shown to a person (§10). Combines `Status` with the local `Tier`.
public enum StatusAppearance: String, CaseIterable, Sendable, Hashable {
    /// Green "Done".
    case done
    /// Amber "To do".
    case toDo
    /// Red "Today".
    case today
    /// Grey "Can't check".
    case cantCheck

    /// pass → done; unknown → can't check; fail → today when the tier is red, otherwise to do.
    /// (Red is reserved for the §5.1 cases; the tier comes from the catalog/engine.)
    public init(status: Status, tier: Tier) {
        switch status {
        case .pass: self = .done
        case .unknown: self = .cantCheck
        case .fail: self = tier == .red ? .today : .toDo
        }
    }

    /// The SF Symbol name (exact, §10).
    public var symbolName: String {
        switch self {
        case .done: "checkmark.shield.fill"
        case .toDo: "exclamationmark.triangle.fill"
        case .today: "exclamationmark.octagon.fill"
        case .cantCheck: "questionmark.circle"
        }
    }

    /// The status word (exact copy, §10).
    public var word: String {
        switch self {
        case .done: "Done"
        case .toDo: "To do"
        case .today: "Today"
        case .cantCheck: "Can't check"
        }
    }

    /// Text and icon color on the normal page background.
    public var accent: DynamicColor {
        switch self {
        case .done: ShieldPalette.greenAccent
        case .toDo: ShieldPalette.amberAccent
        case .today: ShieldPalette.redAccent
        case .cantCheck: ShieldPalette.greyAccent
        }
    }

    /// Card/chip fill.
    public var fill: DynamicColor {
        switch self {
        case .done: ShieldPalette.greenFill
        case .toDo: ShieldPalette.amberFill
        case .today: ShieldPalette.redFill
        case .cantCheck: ShieldPalette.greyFill
        }
    }

    /// Text and icon color on `fill`. Amber uses dark text in both modes (§11).
    public var onFill: DynamicColor {
        switch self {
        case .toDo: ShieldPalette.onAmber
        default: ShieldPalette.onDarkFill
        }
    }
}

// MARK: - Palette

/// Raw palette values. Checked by ShieldUITests against `pageBackgrounds`.
public enum ShieldPalette {
    public static let greenAccent = DynamicColor(light: 0x1E7B34, dark: 0x5BD27A)
    public static let amberAccent = DynamicColor(light: 0x8A5800, dark: 0xFFC24D)
    public static let redAccent = DynamicColor(light: 0xB42318, dark: 0xFF8A80)
    public static let greyAccent = DynamicColor(light: 0x5E6670, dark: 0xAEB6BF)

    public static let greenFill = DynamicColor(light: 0x1E7B34, dark: 0x1E7B34)
    public static let amberFill = DynamicColor(light: 0xFFC24D, dark: 0xFFC24D)
    public static let redFill = DynamicColor(light: 0xB42318, dark: 0xB42318)
    public static let greyFill = DynamicColor(light: 0x5E6670, dark: 0x4A5058)

    public static let onDarkFill = DynamicColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    public static let onAmber = DynamicColor(light: 0x1C1A17, dark: 0x1C1A17)

    /// The system page/card backgrounds accents must stay readable on.
    /// Light: white, systemGroupedBackground. Dark: black, secondarySystemBackground, tertiary.
    public static let pageBackgrounds = (
        light: [RGBColor(hex: 0xFFFFFF), RGBColor(hex: 0xF2F2F7)],
        dark: [RGBColor(hex: 0x000000), RGBColor(hex: 0x1C1C1E), RGBColor(hex: 0x2C2C2E)]
    )
}

// MARK: - Metrics

public enum ShieldMetrics {
    /// Primary buttons: at least 60 pt tall, full width (§10, §11).
    public static let primaryButtonMinHeight: CGFloat = 60
    /// Every other hit target: at least 44 pt (§11).
    public static let minHitTarget: CGFloat = 44
    public static let cornerRadius: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let stackSpacing: CGFloat = 16
    /// Mac window minimum (§11).
    public static let macWindowMinWidth: CGFloat = 600
    public static let macWindowMinHeight: CGFloat = 500
}

extension Status {
    /// Convenience for UI: the appearance for this status at `tier`.
    public func appearance(tier: Tier) -> StatusAppearance {
        StatusAppearance(status: self, tier: tier)
    }
}
