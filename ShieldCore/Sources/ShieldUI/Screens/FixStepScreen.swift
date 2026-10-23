// §10.1 7 Fix step (measured): the fail copy, then one step per screen with
// [Open Settings] / [Next] / [Done]. The app re-checks when it comes back to the foreground (H3:
// the person changes the setting; Family Shield never does).

import SwiftUI
import ShieldCore

struct FixStepScreen: View {
    let model: AppModel
    let checkID: CheckID
    @State private var index = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let item = model.item(checkID) {
            content(item)
        } else {
            ScreenScaffold("fixStep") {
                Secondary(L.t("status.unknown.generic"))
                CallBenButton(model: model, kind: .primary, isDefaultAction: true)
            }
        }
    }

    @ViewBuilder
    private func content(_ item: StatusItem) -> some View {
        let appearance = model.appearance(item)
        let steps = item.stepKeys
        let current = min(index, max(steps.count - 1, 0))
        let isLast = current >= steps.count - 1
        let settingsURL = item.deepLink?.openableURL
        ScreenScaffold("fixStep") {
            FixHeader(title: L.plain(item.titleKey), message: L.a(item.messageKey), appearance: appearance, source: item.source)

            if item.status != .pass, !steps.isEmpty {
                Card(padding: 20) {
                    if steps.count > 1 {
                        CounterText(L.fill("step.counter", ["n": "\(current + 1)", "total": "\(steps.count)"]))
                    }
                    Text(L.a(steps[current]))
                        .shieldFont(.title2, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fix.step")
                        .accessibilityFocusOnChange(of: current)
                    if current == 0 {
                        ForEach(item.noteKeys, id: \.self) { note in
                            Label {
                                Text(L.a(note))
                                    .shieldFont(.body)
                                    .foregroundStyle(ShieldPalette.textSecondary.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "info.circle.fill").foregroundStyle(ShieldPalette.brandText.color)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .accessibilityElement(children: .contain)

                let offersSettings = Self.offersSettings(callBen: item.callBen, red: appearance == .today,
                                                         hasLink: settingsURL != nil)
                let hasPrimary = item.callBen || offersSettings
                if item.callBen {
                    CallBenButton(model: model, kind: .primary, isDefaultAction: true)
                }
                if offersSettings, let settingsURL, let link = item.deepLink {
                    Button {
                        openURL.settings(settingsURL, fallback: link.fallbackURL)
                    } label: {
                        ButtonLabel(L.t(link.buttonTitleKey), systemImage: "gear")
                    }
                    .buttonStyle(item.callBen ? .shieldSecondary : .shieldPrimary)
                    .shieldDefaultAction(!item.callBen)
                    .accessibilityIdentifier("fix.openSettings")
                }

                // Keyboard (§11): Return is the main button; Next / Done answer Return when there
                // is none, and Command-Return otherwise, so every step can be finished from the keyboard.
                if !isLast {
                    Button {
                        index = current + 1
                    } label: {
                        Text(L.t("action.next"))
                    }
                    .buttonStyle(.shieldSecondary)
                    .shieldStepShortcut(secondary: hasPrimary)
                    .accessibilityIdentifier("fix.next")
                } else {
                    Button {
                        Task { await model.refresh() }
                        model.pop()
                    } label: {
                        Text(L.t("action.done"))
                    }
                    .buttonStyle(.shieldSecondary)
                    .shieldStepShortcut(secondary: hasPrimary)
                    .accessibilityIdentifier("fix.done")
                }
                if current > 0 {
                    Button {
                        index = current - 1
                    } label: {
                        ButtonLabel(L.t("action.back"), systemImage: "chevron.left")
                    }
                    .buttonStyle(.shieldQuiet)
                    .frame(maxWidth: .infinity)
                }
                Secondary(L.t("fix.recheck"))
            } else {
                Button {
                    model.pop()
                } label: {
                    Text(L.t("action.done"))
                }
                .buttonStyle(.shieldPrimary)
                .shieldDefaultAction()
            }

            VStack(spacing: 4) {
                OfficialLinkButton(title: L.t("action.whyAmISeeingThis"), url: whyURL(item), systemImage: "questionmark.circle")
                if !item.callBen {
                    CallBenButton(model: model, kind: .quiet)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .shieldNavigationTitle(L.plain(item.titleKey))
    }

    /// The §6.2 Settings button (§10.2 "Fix cards use the §6.2 links"): primary when the person
    /// fixes it themselves; secondary under **Call Ben** when the catalog says call Ben, so a step
    /// that says "Open System Settings → …" has its button. Never next to Call Ben on a red item:
    /// H9, Call Ben is the only action for anything scary.
    static func offersSettings(callBen: Bool, red: Bool, hasLink: Bool) -> Bool {
        hasLink && !(callBen && red)
    }

    /// "Why am I seeing this?": Apple's security releases page for updates, else the catalog page.
    private func whyURL(_ item: StatusItem) -> URL? {
        item.checkID == .osPatched ? (OfficialLinks.appleSecurityReleases ?? item.supportURL) : item.supportURL
    }
}

/// The top of a fix or guided screen: title, status chip and badge, and the message.
struct FixHeader: View {
    let title: String
    let message: AttributedString
    let appearance: StatusAppearance
    let source: Source
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if !typeSize.isAccessibilitySize {
                    StatusIcon(appearance, size: 56)
                }
                Text(title)
                    .shieldFont(.title, weight: .bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .reportsScreenTitle()
                Spacer(minLength: 0)
            }
            FlowRow {
                StatusChip(appearance)
                SourceBadge(source)
            }
            Text(message)
                .shieldFont(.title3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(appearance.word). \(L.badge(source)). \(String(message.characters))")
        .accessibilityIdentifier("fix.header")
    }
}

extension OpenURLAction {
    /// Opens a Settings link; if the system refuses it, opens `fallback` instead (see
    /// `DeepLink.fallbackURL`).
    @MainActor
    func settings(_ url: URL, fallback: URL?) {
        self(url) { accepted in
            if !accepted, let fallback { self(fallback) }
        }
    }
}
