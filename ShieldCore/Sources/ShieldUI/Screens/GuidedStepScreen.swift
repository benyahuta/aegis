// §10.1 8 Guided step (self-check): one "why" sentence → steps → [I did it] / [Not sure] /
// [Not now]. Badge "Confirmed by you". Fixed footer: "Family Shield will never ask you to type a
// password, code or PIN." (§6.3). Answers are enum values only (H2); nothing typed is stored.

import SwiftUI
import ShieldCore

struct GuidedStepScreen: View {
    let model: AppModel
    let checkID: CheckID
    @State private var answered: SelfAnswer?
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let item = model.item(checkID), let variant = model.catalog.variant(checkID, platform: model.platform) {
            content(item, variant)
        } else {
            ScreenScaffold("guidedStep") {
                Secondary(L.t("status.unknown.generic"))
                SelfCheckFooter()
            }
        }
    }

    @ViewBuilder
    private func content(_ item: StatusItem, _ variant: CheckVariant) -> some View {
        let appearance = model.appearance(item)
        ScreenScaffold("guidedStep") {
            FixHeader(title: L.plain(item.titleKey), message: L.a(item.messageKey), appearance: appearance, source: .selfReported)

            // `.contain`, not `.combine`: merging would make the whole paragraph a heading.
            Card {
                SectionHeading(L.t("guided.whyHeading"))
                Text(L.a(item.whyKey))
                    .shieldFont(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)

            ForEach(item.noteKeys.filter { $0.hasSuffix(".maybeOn") }, id: \.self) { note in
                NoticeCard(info: L.plain(note))
            }

            if checkID == .carrierLock {
                CarrierPicker(model: model)
            }

            StepList(stepKeys: item.stepKeys + (checkID == .carrierLock ? (model.carrier?.stepKeys ?? []) : []))

            ForEach(item.noteKeys.filter { !$0.hasSuffix(".maybeOn") }, id: \.self) { note in
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

            if let link = item.deepLink, let url = link.openableURL {
                Button {
                    openURL.settings(url, fallback: link.fallbackURL)
                } label: {
                    ButtonLabel(L.t(link.buttonTitleKey), systemImage: "gear")
                }
                .buttonStyle(.shieldSecondary)
                .accessibilityIdentifier("guided.openSettings")
            } else if let url = item.supportURL, let key = Self.openKey(checkID) {
                Button {
                    openURL(url)
                } label: {
                    ButtonLabel(L.t(key), systemImage: "safari")
                }
                .buttonStyle(.shieldSecondary)
                .accessibilityIdentifier("guided.openPage")
            }

            if let answered {
                AnswerResponse(answer: answered, connection: model.connection, platform: model.platform) { model.pop() }
            } else {
                Secondary(L.t("guided.answerPrompt"))
                AnswerButtons(options: variant.answerOptions) { answer in
                    model.answer(answer, for: .check(checkID))
                    answered = answer
                }
            }

            if item.checkID != .familyCodeWord {
                CallBenButton(model: model, kind: .quiet)
            }
            SelfCheckFooter()
        }
        .shieldNavigationTitle(L.plain(item.titleKey))
    }

    /// "Open Equifax" etc. for the credit freezes (their supportURL is the bureau's own page).
    static func openKey(_ id: CheckID) -> String? {
        switch id {
        case .creditFreezeEquifax: "freeze.open.equifax"
        case .creditFreezeExperian: "freeze.open.experian"
        case .creditFreezeTransunion: "freeze.open.transunion"
        default: nil
        }
    }
}

/// Numbered steps, each in its own row.
struct StepList: View {
    let stepKeys: [String]

    var body: some View {
        if !stepKeys.isEmpty {
            Card {
                ForEach(Array(stepKeys.enumerated()), id: \.offset) { offset, key in
                    GlyphRow(spacing: 14) {
                        // The SF Symbol "1.circle.fill" etc.: a glyph, not text, so it can stay
                        // bullet-sized beside the step at the largest sizes (VoiceOver reads
                        // "Step 1 of 3" from the row's label).
                        Image(systemName: "\(min(offset + 1, 50)).circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(ShieldPalette.brandText.color, ShieldPalette.brandSoft.color)
                            .shieldGlyphFont(.title)
                            .accessibilityHidden(true)
                    } content: {
                        Text(L.a(key))
                            .shieldFont(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L.fill("step.counter", ["n": "\(offset + 1)", "total": "\(stepKeys.count)"])
                                        + ". " + L.plain(key))
                    if offset < stepKeys.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

/// [I did it] (primary), then [Not sure] and [Not now].
struct AnswerButtons: View {
    let options: [(answer: SelfAnswer, labelKey: String)]
    let onAnswer: (SelfAnswer) -> Void
    @State private var chosen: SelfAnswer?
    @State private var bounce = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                let isChosen = chosen == option.answer
                Button {
                    choose(option.answer)
                } label: {
                    if isChosen {
                        HStack(spacing: 10) {
                            Image(systemName: option.answer == .didIt ? "checkmark.circle.fill" : "checkmark")
                                .symbolEffect(.bounce, value: bounce)
                                .accessibilityHidden(true)
                            Text(L.t(option.labelKey))
                        }
                    } else {
                        Text(L.t(option.labelKey))
                    }
                }
                .buttonStyle(ShieldButtonStyle(isChosen && option.answer == .didIt ? .success : (offset == 0 ? .primary : .secondary)))
                .scaleEffect(isChosen && !reduceMotion ? 1.03 : 1)
                .opacity(chosen != nil && !isChosen ? 0.4 : 1)
                .allowsHitTesting(chosen == nil)
                .shieldNumberShortcut(offset + 1)
                .accessibilityIdentifier("answer.\(option.answer.rawValue)")
            }
        }
        .sensoryFeedback(trigger: chosen) { _, new in
            guard let new else { return nil }
            return new == .didIt ? .success : .selection
        }
    }

    /// Shows the tap (green check, little bounce, haptic), holds it a moment, then answers.
    /// Nothing auto-advances past the response: the person still taps [Done] there.
    private func choose(_ answer: SelfAnswer) {
        guard chosen == nil else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.55)) {
            chosen = answer
        }
        bounce += 1
        let hold: Duration = reduceMotion ? .milliseconds(300) : .milliseconds(700)
        Task { @MainActor in
            try? await Task.sleep(for: hold)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                onAnswer(answer)
            }
            // Stay green while the buttons fade out; screens that keep the buttons on screen
            // (Family Rules) get them back afterwards.
            try? await Task.sleep(for: .milliseconds(450))
            chosen = nil
        }
    }
}

/// What the person sees after answering, with a [Done] they tap themselves (nothing auto-advances).
/// VoiceOver moves to the response when it appears (the answer buttons it was on are gone).
struct AnswerResponse: View {
    let answer: SelfAnswer
    let connection: SyncConnectionState
    let platform: Platform
    let done: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Group {
                switch answer {
                case .didIt: NoticeCard(.done, L.t(Self.didItKey(connection: connection, platform: platform)))
                case .notSure: NoticeCard(.toDo, L.t("selfcheck.notSure.response"))
                case .notNow: NoticeCard(info: L.t("selfcheck.notNow.response"))
                }
            }
            .accessibilityFocusOnAppear()
            .accessibilityIdentifier("guided.response")
            .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity).animation(.easeOut(duration: 0.3).delay(0.15)), removal: .opacity))
            Button(action: done) {
                Text(L.t("action.done"))
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction()
            .accessibilityIdentifier("guided.done")
        }
    }

    /// "Ben will see a ✓" only while this device is connected to Ben; otherwise the answer stays
    /// on this device (not joined yet, sharing stopped, or a copy without iCloud), so say that.
    static func didItKey(connection: SyncConnectionState, platform: Platform) -> String {
        connection == .connected ? "guided.saved.didIt" : L.platformKey("guided.saved.didIt.local", platform)
    }
}

/// "Family Shield will never ask you to type a password, code or PIN."
struct SelfCheckFooter: View {
    var body: some View {
        GlyphRow(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .shieldGlyphFont(.callout)
                .foregroundStyle(ShieldPalette.brandText.color)
                .accessibilityHidden(true)
        } content: {
            Text(L.t("selfcheck.footer"))
                .shieldFont(.callout, weight: .medium)
                .foregroundStyle(ShieldPalette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("selfcheck.footer")
    }
}

/// The phone company list for `carrier_lock` (kept on this device only, §12.2).
struct CarrierPicker: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(L.t("guided.carrier.title"))
            ForEach(Carrier.allCases, id: \.self) { carrier in
                let selected = model.carrier == carrier
                Button {
                    model.setCarrier(carrier)
                } label: {
                    HStack {
                        Text(L.t(carrier.nameKey))
                            .shieldFont(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .shieldFont(.title3)
                            .foregroundStyle(selected ? ShieldPalette.brandText.color : ShieldPalette.strongOutline.color)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: ShieldMetrics.minHitTarget + 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ShieldPalette.card.color))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selected ? ShieldPalette.brand.color : ShieldPalette.hairline.color, lineWidth: selected ? 2 : 0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("carrier.\(carrier.rawValue)")
            }
            Secondary(L.t("guided.carrier.privacy"))
        }
    }
}

/// §6.2 / §6.3 optional extras (About → Optional extras): why it exists, where it is, and the
/// "talk to Ben first" warning (Advanced Data Protection can lock someone out for good) before
/// any Settings button. Nothing to answer; it never counts against the person and never syncs.
struct OptionalStepScreen: View {
    let model: AppModel
    let checkID: CheckID
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let item = model.item(checkID), item.kind == .optional {
            content(item)
        } else {
            ScreenScaffold("optionalStep") {
                Secondary(L.t("status.unknown.generic"))
            }
        }
    }

    @ViewBuilder
    private func content(_ item: StatusItem) -> some View {
        ScreenScaffold("optionalStep") {
            // The heading's "why" already says it is optional and never counts against them; the
            // one "talk to Ben first" is the warning card below the steps.
            ScreenHeader(systemImage: "sparkles", title: L.plain(item.titleKey), detail: L.a(item.whyKey))

            StepList(stepKeys: item.stepKeys)

            ForEach(item.noteKeys, id: \.self) { note in
                Card {
                    Label {
                        Text(L.a(note))
                            .shieldFont(.title3, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(StatusAppearance.toDo.accent.color)
                    }
                    .accessibilityElement(children: .combine)
                }
                .accessibilityIdentifier("optional.note")
            }

            CallBenButton(model: model, kind: .primary, isDefaultAction: true)

            if let link = item.deepLink, let url = link.openableURL {
                Button {
                    openURL.settings(url, fallback: link.fallbackURL)
                } label: {
                    ButtonLabel(L.t(link.buttonTitleKey), systemImage: "gear")
                }
                .buttonStyle(.shieldSecondary)
                .accessibilityIdentifier("optional.openSettings")
            }
            OfficialLinkButton(title: L.t("service.officialPage"), url: item.supportURL, systemImage: "safari")

            Button {
                model.pop()
            } label: {
                Text(L.t("action.done"))
            }
            .buttonStyle(.shieldQuiet)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("optional.done")
        }
        .shieldNavigationTitle(L.plain(item.titleKey))
    }
}
