// Text styles for the shared screens (SPEC §11 "Dynamic Type through AX5 with no truncation").
//
// iPhone: `.shieldFont(.body)` is exactly `.font(.body)`, so Dynamic Type works as usual.
// Mac: SwiftUI text styles on macOS are fixed sizes and ignore `dynamicTypeSize`. The Mac app sets
// its own text size (View → Bigger Text, `-FSTextSize`) as a `dynamicTypeSize`, and this modifier
// turns it into point sizes from Apple's iOS Dynamic Type table. The Mac default is the iPhone
// "Large" size (body 17 pt), which is easier to read than the 13 pt Mac default.

import SwiftUI

extension View {
    /// The app's text style. Use this instead of `.font(.body)` in ShieldUI.
    public func shieldFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ShieldFontModifier(style: style, weight: weight))
    }
}

extension View {
    /// For a small glyph beside text (`GlyphRow`): the text style's size, but never more than
    /// `maxPoints`, so at the largest text sizes the glyph stays a bullet and the words keep the
    /// width (no "compa-ny's" on a small iPhone).
    public func shieldGlyphFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, maxPoints: CGFloat = 36) -> some View {
        modifier(ShieldGlyphFontModifier(style: style, weight: weight, maxPoints: maxPoints))
    }
}

struct ShieldGlyphFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    let maxPoints: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.font(.system(size: min(ShieldTypeScale.points(style, typeSize), maxPoints),
                             weight: weight ?? ShieldTypeScale.defaultWeight(style)))
    }
}

struct ShieldFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        #if os(macOS)
        content.font(.system(size: ShieldTypeScale.points(style, typeSize),
                             weight: weight ?? ShieldTypeScale.defaultWeight(style)))
        #else
        content.font(ShieldTypeScale.font(style, weight: weight))
        #endif
    }
}

/// Apple's Dynamic Type point sizes (HIG, iOS), used for the Mac's own text-size setting.
public enum ShieldTypeScale {
    /// The order of the columns in `table`.
    public static let sizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    static func row(_ style: Font.TextStyle) -> [CGFloat] {
        switch style {
        case .largeTitle: [31, 32, 33, 34, 36, 38, 40, 44, 48, 52, 56, 60]
        case .title: [25, 26, 27, 28, 30, 32, 34, 38, 43, 48, 53, 58]
        case .title2: [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56]
        case .title3: [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55]
        case .headline, .body: [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        case .callout: [13, 14, 15, 16, 18, 20, 22, 26, 32, 38, 44, 51]
        case .subheadline: [12, 13, 14, 15, 17, 19, 21, 25, 30, 36, 42, 49]
        case .footnote: [12, 12, 12, 13, 15, 17, 19, 23, 27, 33, 38, 44]
        default: [11, 11, 11, 12, 14, 16, 18, 22, 26, 32, 37, 43]
        }
    }

    /// The point size of `style` at `size`.
    public static func points(_ style: Font.TextStyle, _ size: DynamicTypeSize) -> CGFloat {
        let index = sizes.firstIndex(of: size) ?? 3
        return row(style)[index]
    }

    static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }

    static func font(_ style: Font.TextStyle, weight: Font.Weight?) -> Font {
        let base: Font = switch style {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        default: .body
        }
        return weight.map { base.weight($0) } ?? base
    }
}

// MARK: - The Mac's own text size (View → Bigger Text / Smaller Text / Actual Size)

extension ShieldTypeScale {
    /// The launch argument that fixes the Mac text size for UI tests and screenshots.
    public static let textSizeFlag = "-FSTextSize"

    /// The sizes the Mac offers, smallest first. "Actual Size" is `.large` (body 17 pt).
    public static let macSteps: [DynamicTypeSize] = [
        .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    public static let macDefault: DynamicTypeSize = .large

    /// A stable name for `size` (UserDefaults, launch arguments, screenshot file names).
    public static func name(_ size: DynamicTypeSize) -> String {
        switch size {
        case .xSmall: "xSmall"
        case .small: "small"
        case .medium: "medium"
        case .large: "default"
        case .xLarge: "xLarge"
        case .xxLarge: "xxLarge"
        case .xxxLarge: "xxxLarge"
        case .accessibility1: "ax1"
        case .accessibility2: "ax2"
        case .accessibility3: "ax3"
        case .accessibility4: "ax4"
        case .accessibility5: "ax5"
        @unknown default: "default"
        }
    }

    /// Parses `name(_:)` values plus "large", "largest", "accessibility5" and the iOS
    /// `UICTContentSizeCategoryAccessibilityXXXL` style names. nil for anything else.
    public static func size(named raw: String) -> DynamicTypeSize? {
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "default", "large", "l", "actual", "uictcontentsizecategoryl": return .large
        case "largest", "uictcontentsizecategoryaccessibilityxxxl": return .accessibility5
        case "uictcontentsizecategoryaccessibilityxxl": return .accessibility4
        case "uictcontentsizecategoryaccessibilityxl": return .accessibility3
        case "uictcontentsizecategoryaccessibilityl": return .accessibility2
        case "uictcontentsizecategoryaccessibilitym": return .accessibility1
        case "uictcontentsizecategoryxxxl": return .xxxLarge
        case "uictcontentsizecategoryxxl": return .xxLarge
        case "uictcontentsizecategoryxl": return .xLarge
        default: break
        }
        if key.hasPrefix("accessibility"), let n = Int(key.dropFirst("accessibility".count)) {
            return accessibility(n)
        }
        if key.hasPrefix("ax"), let n = Int(key.dropFirst(2)) {
            return accessibility(n)
        }
        return sizes.first { name($0).lowercased() == key }
    }

    private static func accessibility(_ n: Int) -> DynamicTypeSize? {
        switch n {
        case 1: .accessibility1
        case 2: .accessibility2
        case 3: .accessibility3
        case 4: .accessibility4
        case 5: .accessibility5
        default: nil
        }
    }

    /// The next Mac step up or down (clamped).
    public static func step(_ size: DynamicTypeSize, by delta: Int) -> DynamicTypeSize {
        let index = macSteps.firstIndex(of: size) ?? 0
        return macSteps[min(max(index + delta, 0), macSteps.count - 1)]
    }

    /// The `-FSTextSize <name>` value in `arguments`, if any.
    public static func launchSize(_ arguments: [String]) -> DynamicTypeSize? {
        guard let index = arguments.firstIndex(of: textSizeFlag), arguments.index(after: index) < arguments.endIndex else {
            return nil
        }
        return size(named: arguments[arguments.index(after: index)])
    }
}
