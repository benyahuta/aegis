// §10.1 6 Home: one status, one Next step, two big buttons, Family Rules, the trust line, About.

import SwiftUI
import ShieldCore

struct HomeScreen: View {
    @Bindable var model: AppModel
    @State private var showLater = false

    private var home: HomeState { model.snapshot.home }

    var body: some View {
        ScreenScaffold("home") {
            if model.snapshot.showBuildAgeBanner {
                NoticeCard(.toDo, L.t("buildAge.banner"))
                    .accessibilityIdentifier("home.buildBanner")
            }

            HomeStatusHeader(model: model)

            if let next = home.nextStep {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(L.t("home.nextStep"))
                    StatusItemButton(model: model, item: next, actionTitle: L.t("action.showMeHow"))
                        .accessibilityIdentifier("home.nextStep")
                }
                if !home.later.isEmpty, let laterText = home.laterText {
                    LaterSection(model: model, items: home.later, title: laterText, expanded: $showLater)
                }
            }

            if model.showAccountsPrompt {
                Button {
                    model.open(.accountsPicker)
                } label: {
                    NavigationRowContent(systemImage: "person.crop.rectangle.stack", title: L.t("accounts.picker.title"),
                                         detail: L.t("accounts.picker.later"))
                }
                .buttonStyle(.plain)
            }

            if model.snapshot.nextUnlockDay != nil {
                Secondary(L.t("pace.moreSoon"))
            }

            VStack(spacing: 12) {
                Button {
                    model.open(.scamEntry)
                } label: {
                    ButtonLabel(L.t("home.isThisAScam"), systemImage: "questionmark.bubble.fill")
                }
                .buttonStyle(.shieldPrimary)
                .accessibilityIdentifier("home.isThisAScam")
                CallBenButton(model: model)
            }
            .padding(.top, 4)

            Button {
                model.open(.familyRules)
            } label: {
                NavigationRowContent(systemImage: "list.bullet.rectangle.portrait.fill", title: L.t("rules.title"),
                                     detail: L.t("home.familyRules.detail"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.familyRules")

            if !model.snapshot.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(L.t("home.goodToDo"))
                    ForEach(model.snapshot.suggestions) { item in
                        StatusItemButton(model: model, item: item)
                    }
                }
            }

            TrustLine()
                .padding(.top, 4)

            Button {
                model.open(.about)
            } label: {
                ButtonLabel(L.t("home.about"), systemImage: "info.circle")
            }
            .buttonStyle(.shieldQuiet)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("home.about")
        }
        .shieldNavigationTitle(L.t("home.tab.home"))
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .refreshable { await model.refresh() }
    }
}

/// The big status at the top: symbol, headline, "Checked today at 9:14 AM."
struct HomeStatusHeader: View {
    let model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let home = model.snapshot.home
        let appearance = model.homeAppearance
        let checked = ShieldDates.checkedLine(model.lastCheckedAt, now: model.clock.now())
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        Card(padding: 22) {
            layout {
                StatusIcon(appearance, size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    Text(home.headline)
                        .shieldFont(.title2, weight: .bold)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("home.headline")
                    if home == .protected {
                        Secondary(L.t("home.allDone.detail"))
                    }
                    // While checking, the headline already says so ("Checking now.").
                    if !home.isChecking {
                        Text(checked)
                            .shieldFont(.subheadline)
                            .foregroundStyle(ShieldPalette.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spokenLabel(home: home, word: appearance.word, checked: checked))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("home.status")
    }
}

extension HomeStatusHeader {
    /// Everything the card shows, in the order it shows it (the label replaces the children's
    /// text, so a line left out here is never heard).
    static func spokenLabel(home: HomeState, word: String, checked: String) -> String {
        if home.isChecking { return sentence(home.headline) }
        let detail = home == .protected ? " " + sentence(L.t("home.allDone.detail")) : ""
        return "\(sentence(home.headline)) \(word).\(detail) \(checked)"
    }

    /// Ends `text` with a full stop so VoiceOver pauses before the status word
    /// ("1 thing to do. To do. Checked today…", not "1 thing to do To do.").
    static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}

/// A status card that opens its fix or guided screen. One VoiceOver element (§11).
struct StatusItemButton: View {
    let model: AppModel
    let item: StatusItem
    var actionTitle: String?

    var body: some View {
        let appearance = model.appearance(item)
        let title = L.plain(item.titleKey)
        Button {
            model.open(model.route(for: item))
        } label: {
            StatusCardContent(title: title, message: L.a(item.messageKey), appearance: appearance,
                              source: item.source, actionTitle: actionTitle)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(appearance.word). \(L.badge(item.source)).")
        .accessibilityValue(L.plain(item.messageKey))
        .accessibilityHint(L.t(L.platformKey("a11y.hint.showHow", model.platform)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("status.\(item.checkID.rawValue)\(item.service.map { ".\($0.rawValue)" } ?? "")")
    }
}

/// "2 more for later": collapsed until tapped.
struct LaterSection: View {
    let model: AppModel
    let items: [StatusItem]
    let title: String
    @Binding var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if reduceMotion { expanded.toggle() } else { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            } label: {
                HStack {
                    Text(title)
                        .shieldFont(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(ShieldPalette.brandText.color)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: ShieldMetrics.minHitTarget + 8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ShieldPalette.card.color))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? L.t("a11y.expanded") : L.t("a11y.collapsed"))
            .accessibilityIdentifier("home.later")
            if expanded {
                ForEach(items) { item in
                    StatusItemButton(model: model, item: item)
                }
            }
        }
    }
}
