// The app's root (SPEC §10): first-run screens, then Home. Ben's copy adds the Family tab.

import SwiftUI
import ShieldCore

public struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.onboarding != .done {
                OnboardingFlow(model: model)
                    .transition(.opacity)
            } else if model.isOwner {
                #if os(macOS)
                // The Mac's TabView is a small control in the title bar; Ben gets two big tabs.
                VStack(spacing: 0) {
                    MacTabBar(selection: $model.selectedTab)
                    Divider()
                    if model.selectedTab == .home {
                        HomeStack(model: model)
                    } else {
                        FamilyStack(model: model)
                    }
                }
                .transition(.opacity)
                #else
                TabView(selection: $model.selectedTab) {
                    HomeStack(model: model)
                        .tabItem { Label(L.t("home.tab.home"), systemImage: "house.fill") }
                        .tag(MainTab.home)
                    FamilyStack(model: model)
                        .tabItem { Label(L.t("home.tab.family"), systemImage: "person.2.fill") }
                        .tag(MainTab.family)
                }
                .transition(.opacity)
                #endif
            } else {
                HomeStack(model: model)
                    .transition(.opacity)
            }
        }
        // §11 Reduce Motion: nothing beyond a cross-fade (and none at all when it's on).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.onboarding)
        .tint(ShieldPalette.brandText.color)
        .task { await model.start() }
    }
}

// MARK: - Stacks

struct HomeStack: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack(path: $model.homePath) {
            HomeScreen(model: model)
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(model: model, route: route)
                }
        }
    }
}

struct RouteDestination: View {
    let model: AppModel
    let route: Route

    var body: some View {
        switch route {
        case .fix(let id): FixStepScreen(model: model, checkID: id)
        case .guided(let id): GuidedStepScreen(model: model, checkID: id)
        case .optional(let id): OptionalStepScreen(model: model, checkID: id)
        case .service(let key): ServiceStepsScreen(model: model, serviceKey: key)
        case .scamEntry: ScamEntryScreen(model: model)
        case .pasteMessage: PasteMessageScreen(model: model)
        case .callQuiz: CallQuizScreen(model: model)
        case .scamResult: ScamResultScreen(model: model)
        case .familyRules: FamilyRulesScreen(model: model)
        case .about: AboutScreen(model: model)
        case .accountsPicker: AccountsPickerScreen(model: model, onboarding: false)
        case .whoToCall: WhoToCallScreen(model: model, onboarding: false)
        case .reminders: RemindersScreen(model: model, onboarding: false)
        }
    }
}

struct OnboardingFlow: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack(path: $model.onboardingPath) {
            WelcomeScreen(model: model)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .welcome: WelcomeScreen(model: model)
                    case .join: JoinScreen(model: model)
                    case .keepChecking: KeepCheckingScreen(model: model)
                    case .whoToCall: WhoToCallScreen(model: model, onboarding: true)
                    case .reminders: RemindersScreen(model: model, onboarding: true)
                    case .accounts: AccountsPickerScreen(model: model, onboarding: true)
                    case .startFamily: StartFamilyScreen(model: model)
                    case .done: EmptyView()
                    }
                }
        }
    }
}

struct FamilyStack: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack(path: $model.familyPath) {
            FamilyTabScreen(model: model)
                .navigationDestination(for: FamilyRoute.self) { route in
                    switch route {
                    case .device(let zone, let id): DeviceDetailScreen(model: model, zoneName: zone, deviceID: id)
                    case .addPerson: AddPersonScreen(model: model)
                    case .feedHealth: FeedHealthScreen(model: model)
                    }
                }
        }
    }
}

#if os(macOS)
/// Home / Family for Ben's Mac copy (⌘1 / ⌘2 in the Go menu too). A compact two-part control,
/// not two big filled buttons: it is navigation, so it never looks like the page's one main
/// action (§10), and it stays one 44 pt row at every text size (icon beside the word).
struct MacTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 4) {
            tab(.home, title: L.t("home.tab.home"), symbol: "house.fill")
            tab(.family, title: L.t("home.tab.family"), symbol: "person.2.fill")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ShieldPalette.greyWash.color))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(ShieldPalette.page.color)
    }

    private func tab(_ tab: MainTab, title: String, symbol: String) -> some View {
        Button {
            selection = tab
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
                Text(title)
            }
        }
        .buttonStyle(MacTabStyle(selected: selection == tab))
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}

/// One part of `MacTabBar`: the selected tab is a card-colored segment with a brand outline
/// (color is never the only signal: it also has the selected trait and a heavier word).
struct MacTabStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return configuration.label
            .shieldFont(.headline, weight: selected ? .bold : .medium)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(selected ? ShieldPalette.brandText.color : ShieldPalette.textSecondary.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: ShieldMetrics.minHitTarget)
            .background { if selected { shape.fill(ShieldPalette.card.color) } }
            .overlay {
                if selected {
                    shape.strokeBorder(contrast == .increased ? ShieldPalette.brandText.color : ShieldPalette.brand.color,
                                       lineWidth: contrast == .increased ? 2.5 : 1.5)
                }
            }
            .contentShape(shape)
            .modifier(MacFocusRing(shape: shape))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif

// MARK: - Shared actions

/// The big **Call Ben** button (H9). With no number picked yet it opens "Who to call".
/// `isDefaultAction`: Return presses it (the screen's main button). Quiet Call Ben is centred
/// like every other text-style action.
struct CallBenButton: View {
    let model: AppModel
    var kind: ShieldButtonKind = .secondary
    var isDefaultAction = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = model.callBenURL {
                openURL(url)
            } else {
                model.open(.whoToCall)
            }
        } label: {
            ButtonLabel(L.t("action.callBen"), systemImage: "phone.fill")
        }
        .buttonStyle(ShieldButtonStyle(kind))
        .shieldDefaultAction(isDefaultAction)
        .frame(maxWidth: kind == .quiet ? .infinity : nil)
        .accessibilityHint(model.callBenURL == nil ? L.t("callBen.notSet") : L.t("a11y.callBen.hint"))
        .accessibilityIdentifier("action.callBen")
    }
}

/// Opens an https page from the compiled constants, as a quiet link (≥ 44 pt), centred like
/// every other text-style action.
struct OfficialLinkButton: View {
    let title: String
    let url: URL?
    var systemImage = "arrow.up.right.square"
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                ButtonLabel(title, systemImage: systemImage)
            }
            .buttonStyle(.shieldQuiet)
            .frame(maxWidth: .infinity)
        }
    }
}
