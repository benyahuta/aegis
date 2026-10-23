// Page, card, text and button colors (SPEC §10, §11). Additive to DesignTokens.swift.
// Every pair here is contrast-checked by ShieldUITests (text ≥ 4.5:1, icons/borders ≥ 3:1) in
// light and dark. Calm blues and neutrals; red/amber/green are reserved for status.

import SwiftUI
import ShieldCore

extension ShieldPalette {
    /// Page background (grouped style).
    public static let page = DynamicColor(light: 0xF2F2F7, dark: 0x000000)
    /// Card background.
    public static let card = DynamicColor(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// A raised element on a card (step number bubble, tiles).
    public static let raised = DynamicColor(light: 0xF2F2F7, dark: 0x2C2C2E)
    /// Main text.
    public static let textPrimary = DynamicColor(light: 0x111114, dark: 0xF5F5F7)
    /// Supporting text. Darker than the system secondary label so it stays ≥ 4.5:1 (§11).
    public static let textSecondary = DynamicColor(light: 0x4A4A55, dark: 0xC2C2CA)
    /// Card outline (≥ 3:1 is only required with Increase Contrast; the default is subtle).
    public static let hairline = DynamicColor(light: 0xD8D8DE, dark: 0x38383C)
    public static let strongOutline = DynamicColor(light: 0x6B6B75, dark: 0x9A9AA3)

    /// Primary button fill and white label.
    public static let brand = DynamicColor(light: 0x0A5FBF, dark: 0x1A6FD6)
    public static let onBrand = DynamicColor(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Secondary button fill and its label/link color.
    public static let brandSoft = DynamicColor(light: 0xE1ECFA, dark: 0x1D2B3D)
    public static let brandText = DynamicColor(light: 0x0A5FBF, dark: 0x8CC4FF)

    /// Disabled button fill (label `textSecondary`, edge `strongOutline`).
    public static let disabledFill = DynamicColor(light: 0xE9EAEC, dark: 0x2C2E31)

    /// Soft washes behind a status icon (text never sits on these alone).
    public static let greenWash = DynamicColor(light: 0xE3F3E7, dark: 0x13301C)
    public static let amberWash = DynamicColor(light: 0xFFF1D6, dark: 0x3A2C0B)
    public static let redWash = DynamicColor(light: 0xFCE4E2, dark: 0x3D1512)
    public static let greyWash = DynamicColor(light: 0xE9EAEC, dark: 0x2C2E31)

    /// Text pairs to verify: (name, foreground, background), each needs ≥ 4.5:1.
    public static let textPairs: [(String, DynamicColor, DynamicColor)] = [
        ("primary/page", textPrimary, page), ("primary/card", textPrimary, card),
        ("secondary/page", textSecondary, page), ("secondary/card", textSecondary, card),
        ("secondary/raised", textSecondary, raised), ("secondary/disabledFill", textSecondary, disabledFill),
        ("onBrand/brand", onBrand, brand), ("brandText/brandSoft", brandText, brandSoft),
        ("primary/brandSoft", textPrimary, brandSoft),
        ("brandText/card", brandText, card), ("brandText/page", brandText, page),
        ("green/greenWash", greenAccent, greenWash), ("amber/amberWash", amberAccent, amberWash),
        ("red/redWash", redAccent, redWash), ("grey/greyWash", greyAccent, greyWash),
        ("green/card", greenAccent, card), ("amber/card", amberAccent, card),
        ("red/card", redAccent, card), ("grey/card", greyAccent, card),
    ]

    /// Non-text pairs (icons, button edges), each needs ≥ 3:1.
    public static let shapePairs: [(String, DynamicColor, DynamicColor)] = [
        ("brand/page", brand, page), ("brand/card", brand, card),
        ("strongOutline/card", strongOutline, card), ("strongOutline/page", strongOutline, page),
    ]
}

extension StatusAppearance {
    /// Soft wash behind the status icon.
    public var wash: DynamicColor {
        switch self {
        case .done: ShieldPalette.greenWash
        case .toDo: ShieldPalette.amberWash
        case .today: ShieldPalette.redWash
        case .cantCheck: ShieldPalette.greyWash
        }
    }

    /// Hollow symbol for self-reported items on Ben's dashboard (§10.3 "Hollow icon").
    public var hollowSymbolName: String {
        switch self {
        case .done: "checkmark.shield"
        case .toDo: "exclamationmark.triangle"
        case .today: "exclamationmark.octagon"
        case .cantCheck: "questionmark.circle"
        }
    }
}

extension Verdict {
    /// Danger is red "Today" styling, Be careful is amber, No signs is grey (never green, §1).
    public var appearance: StatusAppearance {
        switch self {
        case .danger: .today
        case .beCareful: .toDo
        case .noCommonSignsFound: .cantCheck
        }
    }

    public var headlineKey: String {
        switch self {
        case .danger: "scam.result.danger"
        case .beCareful: "scam.result.beCareful"
        case .noCommonSignsFound: "scam.result.noSigns"
        }
    }
}
