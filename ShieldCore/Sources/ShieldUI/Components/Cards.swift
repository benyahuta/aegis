// Cards, chips and the screen scaffold (SPEC §10, §11).
// - Status is always color + SF Symbol + word.
// - Every status card is ONE VoiceOver element ("Update your iPhone. Today. Measured.").
// - Layouts reflow vertically at accessibility text sizes; no text is ever truncated.

import SwiftUI
import ShieldCore

// MARK: - Accessibility-size layout

/// Side by side normally; stacked at accessibility text sizes (§11 "Cards reflow vertically").
/// Only for rows with real width pressure (a chip or value next to a title). A small glyph,
/// bullet or step number beside a paragraph stays beside it: use `GlyphRow`.
public func rowLayout(_ typeSize: DynamicTypeSize, spacing: CGFloat = 12, alignment: VerticalAlignment = .top) -> AnyLayout {
    typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
}

/// A row that stacks at accessibility sizes (see `rowLayout`).
public struct AXRow<Content: View>: View {
    let spacing: CGFloat
    let alignment: VerticalAlignment
    let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(spacing: CGFloat = 12, alignment: VerticalAlignment = .top, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.alignment = alignment
        self.content = content()
    }

    public var body: some View {
        let layout = rowLayout(typeSize, spacing: spacing, alignment: alignment)
        layout { content }
    }
}

/// A small leading glyph (bullet, step number, status symbol) beside its text at every text
/// size, on the first line, like `Label`. At accessibility sizes a glyph on a line of its own
/// reads as a broken list and loses its tie to the text. Draw the glyph with `shieldGlyphFont`
/// (at most 36 pt), so the words keep most of the width and nothing is squeezed.
public struct GlyphRow<Glyph: View, Content: View>: View {
    let spacing: CGFloat
    let glyph: Glyph
    let content: Content

    public init(spacing: CGFloat = 12, @ViewBuilder glyph: () -> Glyph, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.glyph = glyph()
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            glyph
            content
            Spacer(minLength: 0)
        }
    }
}

/// A fixed-width column for a leading SF Symbol drawn at `style`, so symbols of different widths
/// (`iphone`, `laptopcomputer`) never move the text column. Grows with the text size.
public func symbolColumnWidth(_ style: Font.TextStyle, _ typeSize: DynamicTypeSize, base: CGFloat = 36) -> CGFloat {
    base * max(1, ShieldTypeScale.points(style, typeSize) / ShieldTypeScale.points(style, .large))
}

// MARK: - Screen scaffold

/// The bottom of the screen's big heading, in the scaffold's content coordinates (iPhone: the
/// inline bar title appears only once that heading has scrolled under the bar).
struct ScreenTitleBottomKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = min(value ?? next, next) }
    }
}

enum ScreenScaffoldSpace {
    static let name = "shield.screen.content"
}

extension EnvironmentValues {
    /// The title passed to `shieldNavigationTitle`, read by `ScreenScaffold` (iPhone).
    @Entry var shieldScreenTitle: String? = nil
}

extension View {
    /// Marks this view as the screen's big heading (`ScreenHeader`, `FixHeader`).
    func reportsScreenTitle() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: ScreenTitleBottomKey.self,
                                   value: proxy.frame(in: .named(ScreenScaffoldSpace.name)).maxY)
        })
    }
}

/// A scrolling page with the grouped background, generous margins and a readable max width.
/// `fillsHeight`: the content is at least as tall as the window, so `Spacer`s in it spread out
/// (Welcome puts its buttons in the lower part of the screen); it still scrolls when taller.
public struct ScreenScaffold<Content: View>: View {
    let identifier: String
    let fillsHeight: Bool
    let content: Content
    @State private var viewportHeight: CGFloat = 0

    public init(_ identifier: String, fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    #if os(macOS)
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss
    #else
    @Environment(\.shieldScreenTitle) private var screenTitle
    @State private var scrollOffset: CGFloat = 0
    @State private var titleBottom: CGFloat?
    #endif

    private static var topPadding: CGFloat { 12 }
    private static var bottomPadding: CGFloat { 32 }

    public var body: some View {
        scroll
            .background(ShieldPalette.page.color.ignoresSafeArea())
            .foregroundStyle(ShieldPalette.textPrimary.color)
            .accessibilityIdentifier("screen.\(identifier)")
            #if os(iOS)
            // The screen's own big heading says the title; the inline bar title appears only once
            // that heading has scrolled under the bar (as in Settings), so it is never shown twice.
            .navigationTitle(barTitle)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    #if os(iOS)
    private var barTitle: String {
        guard let screenTitle else { return "" }
        guard let titleBottom else { return screenTitle }
        return scrollOffset > titleBottom ? screenTitle : ""
    }
    #endif

    private var scroll: some View {
        ScrollView {
            column
                .frame(minHeight: fillsHeight ? max(0, viewportHeight - Self.topPadding - Self.bottomPadding) : nil,
                       alignment: .top)
                .shieldFont(.body)
                .padding(.horizontal, 20)
                .padding(.top, Self.topPadding)
                .padding(.bottom, Self.bottomPadding)
                .coordinateSpace(.named(ScreenScaffoldSpace.name))
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
                #if os(iOS)
                .onPreferenceChange(ScreenTitleBottomKey.self) { value in
                    MainActor.assumeIsolated { titleBottom = value }
                }
                #endif
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            if fillsHeight { viewportHeight = height }
        }
        #if os(iOS)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, offset in
            scrollOffset = offset
        }
        #endif
    }

    private var column: some View {
            VStack(alignment: .leading, spacing: 20) {
                #if os(macOS)
                // The title-bar back chevron is small (< 44 pt, §11) and easy to miss; the Mac
                // shows a real Back button at the top of every pushed screen instead (also ⌘[ / Esc).
                if isPresented {
                    Button {
                        dismiss()
                    } label: {
                        // Always chevron + word side by side (the macOS Back idiom), even at the
                        // largest text sizes where ButtonLabel stacks; it has no width pressure.
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "chevron.left")
                                .accessibilityHidden(true)
                            Text(L.t("action.back"))
                        }
                    }
                    .buttonStyle(.shieldQuiet)
                    .accessibilityIdentifier("nav.back")
                    // The quiet style's 8 pt inset, undone so the chevron sits on the content column.
                    .padding(.leading, -8)
                    .padding(.bottom, -8)
                }
                #endif
                content
            }
            // (`.shieldFont(.body)` in `scroll`: the default text style for everything inside, so
            // SF Symbols in labels scale with the text on the Mac too; on iPhone it is .body.)
    }
}

// MARK: - Card

public struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    public init(padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(ShieldPalette.card.color))
            .overlay(shape.strokeBorder(contrast == .increased ? ShieldPalette.strongOutline.color : ShieldPalette.hairline.color,
                                        lineWidth: contrast == .increased ? 1.5 : 0.5))
    }
}

/// A section heading above cards.
public struct SectionHeading: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .shieldFont(.headline)
            .foregroundStyle(ShieldPalette.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 4)
    }
}

/// Supporting text in the high-contrast secondary color.
public struct Secondary: View {
    let text: Text

    public init(_ string: String) { text = Text(string) }
    public init(_ attributed: AttributedString) { text = Text(attributed) }

    public var body: some View {
        text
            .shieldFont(.body)
            .foregroundStyle(ShieldPalette.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Status

/// The filled chip: symbol + word on the status color (amber uses dark text, §11).
public struct StatusChip: View {
    let appearance: StatusAppearance
    let hollow: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ appearance: StatusAppearance, hollow: Bool = false) {
        self.appearance = appearance
        self.hollow = hollow
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hollow ? appearance.hollowSymbolName : appearance.symbolName)
                .accessibilityHidden(true)
            Text(appearance.word)
        }
        .shieldFont(.subheadline, weight: .bold)
        .foregroundStyle(appearance.onFill.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(appearance.fill.color))
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }
}

/// "Measured" / "Confirmed by you".
public struct SourceBadge: View {
    let source: Source

    public init(_ source: Source) { self.source = source }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: source == .measured ? "ruler" : "person.fill.checkmark")
                .accessibilityHidden(true)
            Text(L.badge(source))
        }
        .shieldFont(.subheadline)
        .foregroundStyle(ShieldPalette.textSecondary.color)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A round wash with the status symbol.
public struct StatusIcon: View {
    let appearance: StatusAppearance
    let size: CGFloat
    var symbolOverride: String?

    public init(_ appearance: StatusAppearance, size: CGFloat = 44, symbol: String? = nil) {
        self.appearance = appearance
        self.size = size
        self.symbolOverride = symbol
    }

    public var body: some View {
        Image(systemName: symbolOverride ?? appearance.symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(appearance.accent.color)
            .frame(width: size, height: size)
            .background(Circle().fill(appearance.wash.color))
            .accessibilityHidden(true)
    }
}

/// Lays children out side by side and wraps them onto the next line when they don't fit
/// (`FlowLayout`: one view per child at every text size, never truncated).
public struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    public init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        FlowLayout(spacing: spacing, lineSpacing: spacing * 0.6) { content }
    }
}

/// One status card: title, chip, badge and message. Optionally shows a "Show me how" bar.
/// The caller wraps it in a Button / NavigationLink; this view is a single VoiceOver element.
public struct StatusCardContent: View {
    let title: String
    let message: AttributedString?
    let appearance: StatusAppearance
    let source: Source
    let actionTitle: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(title: String, message: AttributedString?, appearance: StatusAppearance, source: Source, actionTitle: String? = nil) {
        self.title = title
        self.message = message
        self.appearance = appearance
        self.source = source
        self.actionTitle = actionTitle
    }

    public var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                if !typeSize.isAccessibilitySize {
                    StatusIcon(appearance)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .shieldFont(.title3, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowRow {
                        StatusChip(appearance)
                        SourceBadge(source)
                    }
                    if let message {
                        Text(message)
                            .shieldFont(.body)
                            .foregroundStyle(ShieldPalette.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let actionTitle {
                Text(actionTitle)
                    .shieldFont(.title3, weight: .semibold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(ShieldPalette.onBrand.color)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: ShieldMetrics.primaryButtonMinHeight)
                    .background(RoundedRectangle(cornerRadius: ShieldMetrics.cornerRadius, style: .continuous)
                        .fill(ShieldPalette.brand.color))
                    .padding(.top, 4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A compact tappable row: icon, title, optional detail and a chevron. At least 60 pt tall.
public struct NavigationRowContent: View {
    let systemImage: String
    let title: String
    let detail: String?
    let tint: Color
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(systemImage: String, title: String, detail: String? = nil, tint: Color = ShieldPalette.brandText.color) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.tint = tint
    }

    public var body: some View {
        Card(padding: 16) {
            // The icon stays beside the title at every size (on the first line at accessibility
            // sizes, where the chevron is left out), in a fixed column so titles line up.
            HStack(alignment: typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing: 14) {
                Image(systemName: systemImage)
                    .shieldFont(.title2)
                    .foregroundStyle(tint)
                    .frame(width: symbolColumnWidth(.title2, typeSize))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .shieldFont(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .shieldFont(.subheadline)
                            .foregroundStyle(ShieldPalette.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .shieldFont(.body, weight: .semibold)
                        .foregroundStyle(ShieldPalette.textSecondary.color)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The trust line (§7) shown on Home and About.
public struct TrustLine: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    public init() {}

    public var body: some View {
        // A Label like PrivacyLine: the hand stays beside the first line at every text size.
        Label {
            Text(L.t("trust.line"))
                .shieldFont(.callout)
                .foregroundStyle(ShieldPalette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(ShieldPalette.brandText.color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trust.line")
    }
}

/// A big symbol with a headline and body, used at the top of most screens.
public struct ScreenHeader: View {
    let systemImage: String?
    let tint: Color
    let wash: Color
    let title: String
    let detail: AttributedString?

    public init(systemImage: String? = nil, tint: Color = ShieldPalette.brandText.color,
                wash: Color = ShieldPalette.brandSoft.color, title: String, detail: AttributedString? = nil) {
        self.systemImage = systemImage
        self.tint = tint
        self.wash = wash
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 68, height: 68)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(wash))
                    .accessibilityHidden(true)
            }
            Text(title)
                .shieldFont(.title, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .reportsScreenTitle()
            if let detail {
                Text(detail)
                    .shieldFont(.title3)
                    .foregroundStyle(ShieldPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Step 2 of 3".
public struct CounterText: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .shieldFont(.subheadline, weight: .semibold)
            .foregroundStyle(ShieldPalette.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A label/value pair that stacks at accessibility sizes.
public struct InfoRow: View {
    let label: String
    let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        LabelValueLayout {
            Text(label).shieldFont(.body).fixedSize(horizontal: false, vertical: true)
            Text(value).shieldFont(.body, weight: .semibold).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A gentle notice strip (build-age banner, sync messages).
/// - `NoticeCard(.done, …)` etc. is a real status notice: VoiceOver says the status word first
///   ("Done. Reminders are on.").
/// - `NoticeCard(info: …)` is plain information (an "i" symbol, no status word): §10 reserves
///   "Can't check" and the other words for statuses, so they are never spoken for guidance.
public struct NoticeCard: View {
    let appearance: StatusAppearance?
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ appearance: StatusAppearance, _ text: String) {
        self.appearance = appearance
        self.text = text
    }

    public init(info text: String) {
        self.appearance = nil
        self.text = text
    }

    /// What VoiceOver reads.
    public var spokenLabel: String {
        appearance.map { "\($0.word). \(text)" } ?? text
    }

    public var body: some View {
        GlyphRow {
            Image(systemName: appearance?.symbolName ?? "info.circle.fill")
                .shieldGlyphFont(.title3)
                .foregroundStyle(appearance?.accent.color ?? ShieldPalette.brandText.color)
                .accessibilityHidden(true)
        } content: {
            Text(text)
                .shieldFont(.body, weight: .medium)
                .foregroundStyle(ShieldPalette.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(appearance?.wash.color ?? ShieldPalette.brandSoft.color))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }
}

extension View {
    /// The screen's title. iPhone: `ScreenScaffold` shows it as an inline bar title only once the
    /// screen's own big heading has scrolled under the bar (never the same words twice). Mac: the
    /// window title (the Back button is drawn by `ScreenScaffold`).
    @ViewBuilder
    public func shieldNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        self.environment(\.shieldScreenTitle, title)
        #else
        self.navigationTitle(title).navigationBarBackButtonHidden(true)
        #endif
    }
}
