// §10.1 1–5: Welcome, Join Ben's family, Who to call, Reminders. (Accounts picker has its own file.)
// One main action per screen. Nothing auto-advances (§11).

import SwiftUI
import ShieldCore

// MARK: 1. Welcome

struct WelcomeScreen: View {
    let model: AppModel

    var body: some View {
        // fillsHeight: the page is at least as tall as the window, so the two Spacers share the
        // free space and Get started sits in the lower part of the screen (it still scrolls at
        // the largest text sizes).
        ScreenScaffold("welcome", fillsHeight: true) {
            Spacer(minLength: 12)
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(ShieldPalette.brandText.color)
                .frame(width: 112, height: 112)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ShieldPalette.brandSoft.color))
                .accessibilityHidden(true)
            Text(L.t("welcome.headline"))
                .shieldFont(.largeTitle, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome.headline")
            Text(L.t(L.platformKey("welcome.body", model.platform)))
                .shieldFont(.title3)
                .foregroundStyle(ShieldPalette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button {
                model.next(after: .welcome)
            } label: {
                Text(L.t("welcome.getStarted"))
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction()
            .accessibilityIdentifier("welcome.getStarted")
            Button {
                model.beginStartFamily()
            } label: {
                Text(L.t("welcome.setUpFamily"))
            }
            .buttonStyle(.shieldQuiet)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("welcome.setUpFamily")
        }
        .shieldNavigationTitle("")
    }
}

// MARK: 2. Join Ben's family

struct JoinScreen: View {
    let model: AppModel

    var body: some View {
        let connected = model.connection == .connected
        ScreenScaffold("join") {
            ScreenHeader(systemImage: connected ? "person.2.fill" : "link",
                         tint: connected ? StatusAppearance.done.accent.color : ShieldPalette.brandText.color,
                         wash: connected ? StatusAppearance.done.wash.color : ShieldPalette.brandSoft.color,
                         title: L.t("join.title"))
            Card {
                if connected {
                    Label {
                        Text(L.t("join.connected"))
                            .shieldFont(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: StatusAppearance.done.symbolName)
                            .foregroundStyle(StatusAppearance.done.accent.color)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("join.connected")
                } else {
                    Text(L.t(L.platformKey("join.waiting", model.platform)))
                        .shieldFont(.title3, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("join.waiting")
                    Secondary(L.t(L.platformKey("join.waiting.detail", model.platform)))
                }
            }
            if !connected, let notice = model.notice {
                // Tapping Ben's link didn't connect (§8.4 enroll): say why instead of nothing.
                NoticeCard(.toDo, notice)
                    .accessibilityIdentifier("join.notice")
            }
            Button {
                model.next(after: .join)
            } label: {
                Text(L.t("action.continue"))
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction()
            .accessibilityIdentifier("join.continue")
        }
        .shieldNavigationTitle(L.t("join.title"))
    }
}

// MARK: 3. Who to call

struct WhoToCallScreen: View {
    let model: AppModel
    let onboarding: Bool
    @State private var picking = false
    @State private var notSaved = false

    var body: some View {
        ScreenScaffold("whoToCall") {
            ScreenHeader(systemImage: "phone.circle.fill", title: L.t("whoToCall.title"),
                         detail: AttributedString(L.t("whoToCall.question")))
            if notSaved {
                NoticeCard(.toDo, L.t("whoToCall.notSaved"))
                    .accessibilityIdentifier("whoToCall.notSaved")
            } else if model.benNumber != nil {
                NoticeCard(.done, L.t("whoToCall.saved"))
                    .accessibilityIdentifier("whoToCall.saved")
            }
            Card {
                Label {
                    Secondary(L.t("whoToCall.privacy"))
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(ShieldPalette.brandText.color)
                }
                .accessibilityElement(children: .combine)
            }
            if model.canPickContact {
                Button {
                    picking = true
                    Task {
                        switch await model.chooseBen() {
                        case .saved:
                            notSaved = false
                            announceForAccessibility(NoticeCard(.done, L.t("whoToCall.saved")).spokenLabel)
                        case .notSaved:
                            notSaved = true
                            announceForAccessibility(NoticeCard(.toDo, L.t("whoToCall.notSaved")).spokenLabel)
                        case .cancelled: break
                        }
                        picking = false
                    }
                } label: {
                    ButtonLabel(L.t(model.benNumber == nil ? "whoToCall.choose" : "whoToCall.chooseAgain"),
                                systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(model.benNumber == nil ? .shieldPrimary : .shieldSecondary)
                .shieldDefaultAction(model.benNumber == nil)
                .disabled(picking)
                .accessibilityIdentifier("whoToCall.choose")
            } else {
                Secondary(L.t("whoToCall.unavailable"))
            }
            if onboarding {
                Button {
                    model.next(after: .whoToCall)
                } label: {
                    Text(L.t(model.benNumber == nil ? "whoToCall.notNow" : "action.continue"))
                }
                .buttonStyle(model.benNumber == nil ? .shieldQuiet : .shieldPrimary)
                .shieldDefaultAction(model.benNumber != nil)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("whoToCall.next")
            } else if model.benNumber != nil {
                Button {
                    model.pop()
                } label: {
                    Text(L.t("action.done"))
                }
                .buttonStyle(.shieldPrimary)
                .shieldDefaultAction()
            }
        }
        .shieldNavigationTitle(L.t("whoToCall.title"))
    }
}

// MARK: 4. Reminders

/// §10.1 4, and the same screen again from About (the only places the system prompt is asked).
/// If iOS says no (now or from an earlier "Don't Allow"), the screen says so and how to turn
/// reminders on in Settings, instead of moving on as if nothing happened.
struct RemindersScreen: View {
    let model: AppModel
    let onboarding: Bool
    @State private var asking = false
    @State private var answered = false
    /// The person tapped Yes on this screen: the answer that replaces the button takes VoiceOver
    /// focus (the button they were on is gone).
    @State private var asked = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScreenScaffold("reminders") {
            ScreenHeader(systemImage: "bell.badge.fill", title: L.t("reminders.title"),
                         detail: AttributedString(L.t("reminders.question")))
            if model.remindersOptIn {
                NoticeCard(.done, L.t("reminders.on"))
                    .accessibilityFocusOnAppear(asked)
                    .accessibilityIdentifier("reminders.on")
            } else if model.remindersBlocked, answered || !onboarding {
                NoticeCard(.toDo, L.plain(L.platformKey("reminders.denied", model.platform)))
                    .accessibilityFocusOnAppear(asked)
                    .accessibilityIdentifier("reminders.denied")
                if let url = DeepLink.iosAppSettings.openableURL {
                    Button {
                        openURL(url)
                    } label: {
                        ButtonLabel(L.t(DeepLink.iosAppSettings.buttonTitleKey), systemImage: "gear")
                    }
                    .buttonStyle(.shieldSecondary)
                    .accessibilityIdentifier("reminders.openSettings")
                }
            } else if !onboarding, !model.remindersWanted {
                // (Wanted, but the system's answer isn't read yet this launch: say nothing.)
                NoticeCard(info: L.t("reminders.off"))
                    .accessibilityIdentifier("reminders.off")
            }

            if onboarding && (answered || model.remindersOptIn) {
                Button {
                    model.next(after: .reminders)
                } label: {
                    Text(L.t("action.continue"))
                }
                .buttonStyle(.shieldPrimary)
                .shieldDefaultAction()
                .accessibilityIdentifier("reminders.continue")
            } else if onboarding || !model.remindersWanted {
                Button {
                    asking = true
                    asked = true
                    Task {
                        let on = await model.answerReminders(true)
                        asking = false
                        if onboarding {
                            if on { model.next(after: .reminders) } else { answered = true }
                        }
                    }
                } label: {
                    Text(L.t("reminders.yes"))
                }
                .buttonStyle(.shieldPrimary)
                .shieldDefaultAction()
                .disabled(asking)
                .accessibilityIdentifier("reminders.yes")
                if onboarding {
                    Button {
                        Task {
                            await model.answerReminders(false)
                            model.next(after: .reminders)
                        }
                    } label: {
                        Text(L.t("reminders.noThanks"))
                    }
                    .buttonStyle(.shieldSecondary)
                    .disabled(asking)
                    .accessibilityIdentifier("reminders.noThanks")
                }
            }
            if !onboarding, model.remindersWanted {
                Button {
                    Task { await model.answerReminders(false) }
                } label: {
                    Text(L.t("reminders.turnOff"))
                }
                .buttonStyle(.shieldQuiet)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("reminders.turnOff")
            }
        }
        .shieldNavigationTitle(L.t("reminders.title"))
    }
}
