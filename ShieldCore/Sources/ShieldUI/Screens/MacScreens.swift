// Mac-only pieces of the shared screens (SPEC §10.2, §10.3, §6.2):
// - First launch "Keep checking in the background" (the login item). `SMAppService.mainApp.register()`
//   runs ONLY from that button; if macOS wants approval, System Settings → Login Items opens with
//   the copy "Turn on Family Shield".
// - About: the background-check state, with the same button.
// - Ben's own Mac: Ben-only items and the local "MDM is expected" switch (never synced).
// - Scam checker: pick a screenshot file, or drag a picture onto the window. In memory only.

import SwiftUI
import ShieldCore
import UniformTypeIdentifiers
import CoreTransferable
#if canImport(AppKit)
import AppKit
#endif

// MARK: First launch: login item

struct KeepCheckingScreen: View {
    let model: AppModel

    var body: some View {
        ScreenScaffold("keepChecking") {
            ScreenHeader(systemImage: "clock.arrow.circlepath", title: L.t("loginItem.title"),
                         detail: AttributedString(L.t("loginItem.body")))
            Card {
                Label {
                    Text(L.a("loginItem.expected"))
                        .shieldFont(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(ShieldPalette.brandText.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("loginItem.expected")
            }
            LoginItemStatusContent(model: model, onboarding: true)
        }
        .shieldNavigationTitle(L.t("loginItem.title"))
    }
}

/// The state, plus the one button that registers the login item.
struct LoginItemStatusContent: View {
    let model: AppModel
    let onboarding: Bool
    /// Set when the person clicks the button: the outcome that replaces it takes VoiceOver focus
    /// (not when the screen opens on an earlier answer).
    @State private var asked = false

    var body: some View {
        switch model.loginItemState {
        case .on?:
            NoticeCard(.done, L.t("loginItem.on"))
                .accessibilityFocusOnAppear(asked)
                .accessibilityIdentifier("loginItem.on")
            if onboarding { continueButton(primary: true) }
        case .needsApproval?:
            Card {
                Text(L.t("loginItem.approval.title"))
                    .shieldFont(.title3, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L.a("loginItem.approval.steps"))
                    .shieldFont(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocusOnAppear(asked)
            .accessibilityIdentifier("loginItem.needsApproval")
            Button {
                model.openLoginItemsSettings()
            } label: {
                ButtonLabel(L.t("deeplink.open.mac"), systemImage: "gear")
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction()
            .accessibilityIdentifier("loginItem.openSettings")
            Button {
                asked = true
                model.refreshLoginItemState()
            } label: {
                Text(L.t("loginItem.checkAgain"))
            }
            .buttonStyle(.shieldSecondary)
            .accessibilityIdentifier("loginItem.checkAgain")
            if onboarding { continueButton(primary: false) }
        case .unavailable?:
            NoticeCard(info: L.t("loginItem.unavailable"))
                .accessibilityFocusOnAppear(asked)
                .accessibilityIdentifier("loginItem.unavailable")
            if onboarding { continueButton(primary: true) }
        case .off?, nil:
            Button {
                asked = true
                model.keepCheckingInBackground()
            } label: {
                ButtonLabel(L.t("loginItem.action"), systemImage: "checkmark.shield.fill")
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction()
            .accessibilityIdentifier("loginItem.action")
            if onboarding { continueButton(primary: false) }
        }
    }

    @ViewBuilder
    private func continueButton(primary: Bool) -> some View {
        Button {
            model.next(after: .keepChecking)
        } label: {
            Text(L.t(primary ? "action.continue" : "loginItem.notNow"))
        }
        .buttonStyle(primary ? .shieldPrimary : .shieldQuiet)
        .shieldDefaultAction(primary)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("loginItem.next")
    }
}

/// About → "Background checks" (Mac only).
struct BackgroundChecksSection: View {
    let model: AppModel

    var body: some View {
        if model.hasLoginItem {
            SectionHeading(L.t("loginItem.about.title"))
            Secondary(L.t("loginItem.body"))
            LoginItemStatusContent(model: model, onboarding: false)
        }
    }
}

// MARK: Ben's own Mac (Ben only)

/// "This Mac (only you see this)": Ben-only checks for the Mac he is using, and the local
/// "MDM is expected" switch. Nothing here is shown to a relative or synced.
struct OwnerMacSection: View {
    let model: AppModel

    var body: some View {
        if model.showsOwnerMacSection {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(L.t("ownerMac.title"))
                Secondary(L.t("ownerMac.detail"))
                ForEach(model.snapshot.benOnly) { item in
                    let appearance = model.appearance(item)
                    let title = L.plain(item.titleKey)
                    StatusCardContent(title: title, message: L.a(item.messageKey), appearance: appearance, source: item.source)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(title). \(appearance.word). \(L.badge(item.source)).")
                        .accessibilityValue(L.plain(item.messageKey))
                        .accessibilityIdentifier("ownerMac.\(item.checkID.rawValue)")
                }
                if model.canMarkMDMExpected {
                    Card {
                        Toggle(isOn: Binding(get: { model.mdmExpected }, set: { model.setMDMExpected($0) })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L.t("ownerMac.mdmExpected"))
                                    .shieldFont(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Secondary(L.t("ownerMac.mdmExpected.detail"))
                            }
                        }
                        .shieldToggleStyle()
                        .frame(minHeight: ShieldMetrics.minHitTarget)
                        .accessibilityIdentifier("ownerMac.mdmExpected")
                    }
                }
            }
            .accessibilityIdentifier("ownerMac")
        }
    }
}

// MARK: Scam checker: picture files (Mac)

/// A picture dragged onto the window or picked with the file picker. Bytes stay in memory.
struct DroppedImage: Transferable {
    /// Larger files are not plausible screenshots; they are refused, not read.
    static let maxBytes = 25 * 1024 * 1024

    let data: Data

    init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maxBytes else { throw CocoaError(.fileReadTooLarge) }
        self.data = data
    }

    init(fileURL url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard let type = values.contentType, type.conforms(to: .image) else { throw CocoaError(.fileReadCorruptFile) }
        guard let size = values.fileSize, size <= Self.maxBytes else { throw CocoaError(.fileReadTooLarge) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try self.init(data: Data(contentsOf: url))
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try DroppedImage(fileURL: received.file)
        }
        DataRepresentation(importedContentType: .image) { data in
            try DroppedImage(data: data)
        }
        ProxyRepresentation(importing: { (url: URL) in try DroppedImage(fileURL: url) })
    }
}

#if os(macOS)
/// "Choose a screenshot file" plus the "drag a picture here" area (§10.2).
struct MacScreenshotIntake: View {
    let model: AppModel
    @Binding var loadFailed: Bool
    @Binding var dropTargeted: Bool
    @State private var showImporter = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button {
            showImporter = true
        } label: {
            ButtonLabel(L.t("scam.entry.screenshot.mac"), systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.shieldPrimary)
        .accessibilityIdentifier("scam.screenshot")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure = result { loadFailed = true }
                return
            }
            check { try DroppedImage(fileURL: url) }
        }

        Label {
            Text(L.t("scam.entry.drop"))
                .shieldFont(.body, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "square.and.arrow.down.on.square")
                .foregroundStyle(ShieldPalette.brandText.color)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(RoundedRectangle(cornerRadius: ShieldMetrics.cornerRadius, style: .continuous)
            .fill(dropTargeted ? ShieldPalette.brandSoft.color : ShieldPalette.card.color))
        .overlay(RoundedRectangle(cornerRadius: ShieldMetrics.cornerRadius, style: .continuous)
            .strokeBorder(dropTargeted || contrast == .increased ? ShieldPalette.brandText.color : ShieldPalette.hairline.color,
                          style: StrokeStyle(lineWidth: 2, dash: dropTargeted ? [] : [8, 6])))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scam.drop")
    }

    private func check(_ load: () throws -> DroppedImage) {
        loadFailed = false
        do {
            let image = try load()
            Task { await model.checkScreenshot(image.data) }
        } catch {
            loadFailed = true
        }
    }
}
#endif

// MARK: Menu bar (§10.2)

/// The panel is 560 pt wide at accessibility sizes, room for the icon beside the words: a
/// stacked icon would make each button a third taller in a window that must fit the screen.
private struct PanelButtonLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
    }
}

/// The menu-bar item: a shield and one word, "Protected", "Checking", "1 to do" or "Today". No counts out of
/// totals. The word carries the meaning (the menu bar is monochrome), so color is never needed.
public struct MenuBarLabelContent: View {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public static func symbol(_ home: HomeState) -> String {
        if home.isChecking { return "shield" }
        guard home.nextStep != nil else { return "checkmark.shield" }
        return home.isToday ? "exclamationmark.shield.fill" : "exclamationmark.shield"
    }

    public var body: some View {
        let home = model.snapshot.home
        Label {
            Text(home.menuBarWord)
        } icon: {
            Image(systemName: Self.symbol(home))
        }
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.fill("menubar.a11y", ["word": home.menuBarWord]))
        .accessibilityIdentifier("menubar.label")
    }
}

/// The menu-bar window: the status, the next step, and the main actions.
public struct MenuBarPanel: View {
    let model: AppModel
    let openWindow: () -> Void
    let quit: () -> Void
    /// The usable screen height (below the menu bar); nil reads the main screen.
    let screenHeight: CGFloat?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// A 13-inch MacBook Air at its default resolution: 900 pt less the menu bar.
    public static let smallLaptopScreenHeight: CGFloat = 875

    public init(model: AppModel, screenHeight: CGFloat? = nil, openWindow: @escaping () -> Void, quit: @escaping () -> Void) {
        self.model = model
        self.screenHeight = screenHeight
        self.openWindow = openWindow
        self.quit = quit
    }

    /// The tallest the scrolling body may be. A menu-bar window that does not fit the screen is
    /// cut off under the status item, so the body scrolls and Check again / Quit stay in a fixed
    /// footer (one row normally, two at accessibility sizes).
    static func maxBodyHeight(screenHeight: CGFloat?, accessibilitySize: Bool) -> CGFloat {
        let footerAndPadding: CGFloat = accessibilitySize ? 220 : 110
        let limit = (screenHeight ?? smallLaptopScreenHeight) - 40
        return max(240, limit - footerAndPadding)
    }

    private var usableScreenHeight: CGFloat? {
        #if os(macOS)
        screenHeight ?? NSScreen.main?.visibleFrame.height
        #else
        screenHeight
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                panelBody
                    .padding([.horizontal, .top], 16)
                    .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Self.maxBodyHeight(screenHeight: usableScreenHeight, accessibilitySize: typeSize.isAccessibilitySize))
            .fixedSize(horizontal: false, vertical: true)

            footer
                .padding([.horizontal, .bottom], 16)
        }
        .frame(width: typeSize.isAccessibilitySize ? 560 : 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .shieldFont(.body)
        .background(ShieldPalette.page.color)
        .foregroundStyle(ShieldPalette.textPrimary.color)
        .tint(ShieldPalette.brandText.color)
        .accessibilityIdentifier("menubar.panel")
    }

    @ViewBuilder
    private var panelBody: some View {
        let home = model.snapshot.home
        let appearance = model.homeAppearance
        VStack(alignment: .leading, spacing: 12) {
            // Beside the headline at every size (a stacked icon would push the buttons down).
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
                // Grows with the text (the Mac's own text size), so the status mark is never
                // smaller than the headline next to it.
                StatusIcon(appearance, size: 44 * max(1, ShieldTypeScale.points(.headline, typeSize) / ShieldTypeScale.points(.headline, .large)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(home.headline)
                        .shieldFont(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !home.isChecking {
                        Text(ShieldDates.checkedLine(model.lastCheckedAt, now: model.clock.now()))
                            .shieldFont(.subheadline)
                            .foregroundStyle(ShieldPalette.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("menubar.status")

            if let next = home.nextStep {
                Button {
                    model.openFromMenuBar(model.route(for: next))
                    openWindow()
                } label: {
                    AXRow(alignment: .center) {
                        StatusChip(model.appearance(next))
                        Text(L.plain(next.titleKey))
                            .shieldFont(.body, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        // At accessibility sizes the row stacks; a chevron on its own line reads
                        // as a stray glyph, so it is left out (as on NavigationRowContent).
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(ShieldPalette.textSecondary.color)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .frame(minHeight: ShieldMetrics.minHitTarget)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ShieldPalette.card.color))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(L.plain(next.titleKey)). \(model.appearance(next).word).")
                .accessibilityHint(L.t(L.platformKey("a11y.hint.showHow", model.platform)))
                .accessibilityIdentifier("menubar.nextStep")
            }

            Button {
                model.openFromMenuBar(.scamEntry)
                openWindow()
            } label: {
                PanelButtonLabel(L.t("home.isThisAScam"), systemImage: "questionmark.bubble.fill")
            }
            .buttonStyle(.shieldPrimary)
            .accessibilityIdentifier("menubar.scam")

            Button {
                openWindow()
            } label: {
                PanelButtonLabel(L.t("menubar.open"), systemImage: "macwindow")
            }
            .buttonStyle(.shieldSecondary)
            .accessibilityIdentifier("menubar.open")
        }
    }

    /// Always visible under the scrolling body. Side by side normally; at accessibility sizes
    /// two full-width rows, each with its icon beside the words (never a glyph on its own line).
    @ViewBuilder
    private var footer: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                checkButton.frame(maxWidth: .infinity, alignment: .leading)
                quitButton.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack {
                checkButton
                Spacer(minLength: 0)
                quitButton
            }
        }
    }

    private var checkButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .accessibilityHidden(true)
                Text(L.t("menubar.checkNow"))
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.shieldQuiet)
        .disabled(model.isRefreshing)
        .accessibilityIdentifier("menubar.checkNow")
    }

    private var quitButton: some View {
        Button {
            quit()
        } label: {
            Text(L.t("menubar.quit"))
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.shieldQuiet)
        .accessibilityIdentifier("menubar.quit")
    }
}
