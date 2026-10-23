// §6.4 one online account: its mini-checklist, one step per screen, each answered
// [I did it] / [Not sure] / [Not now]. Service names and answers never leave the device; only the
// category rollup syncs (H5).

import SwiftUI
import ShieldCore

struct ServiceStepsScreen: View {
    let model: AppModel
    let serviceKey: ServiceKey
    @State private var index = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let progress = model.serviceProgress(serviceKey) {
            content(progress)
        } else {
            ScreenScaffold("serviceSteps") {
                Secondary(L.t("status.unknown.generic"))
            }
        }
    }

    @ViewBuilder
    private func content(_ progress: ServiceProgress) -> some View {
        let service = progress.service
        let item = model.snapshot.familyItems.first { $0.id == .service(serviceKey) }
        let appearance = item.map(model.appearance) ?? StatusAppearance(status: progress.status, tier: .amber)
        let steps = progress.steps
        let finished = index >= steps.count
        ScreenScaffold("serviceSteps") {
            FixHeader(title: L.t(service.nameKey), message: L.a(item?.messageKey ?? "accounts.service.fail"),
                      appearance: appearance, source: .selfReported)

            if let whereKey = service.whereKey {
                Card {
                    Label {
                        Text(L.a(whereKey))
                            .shieldFont(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "app.badge.fill").foregroundStyle(ShieldPalette.brandText.color)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let url = service.officialURL {
                Button {
                    openURL(url)
                } label: {
                    ButtonLabel(L.t("service.officialPage"), systemImage: "safari")
                }
                .buttonStyle(.shieldSecondary)
                .accessibilityIdentifier("service.officialPage")
            }

            ForEach(service.linkedChecks, id: \.self) { id in
                if let linked = model.item(id) {
                    StatusItemButton(model: model, item: linked)
                }
            }

            if !steps.isEmpty {
                if finished {
                    NoticeCard(progress.status == .pass ? .done : .toDo,
                               L.t(progress.status == .pass ? "accounts.service.pass" : "accounts.service.someLeft"))
                        .accessibilityFocusOnAppear()
                    Button {
                        model.pop()
                    } label: {
                        Text(L.t("action.done"))
                    }
                    .buttonStyle(.shieldPrimary)
                    .shieldDefaultAction()
                    .accessibilityIdentifier("service.done")
                } else {
                    let step = steps[index]
                    Card(padding: 20) {
                        CounterText(L.fill("step.counter", ["n": "\(index + 1)", "total": "\(steps.count)"]))
                        // Instruction, then "Why: …" in smaller secondary text. VoiceOver reads
                        // both as one element, instruction first.
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L.a(step.copyKey))
                                .shieldFont(.title2, weight: .semibold)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(Self.whyText(step.whyKey))
                                .shieldFont(.subheadline)
                                .foregroundStyle(ShieldPalette.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("service.step")
                        .accessibilityFocusOnChange(of: index)
                        if let answer = step.answer {
                            // "Last time: I did it", so it never reads as a fourth answer button.
                            Label(Self.previousAnswerText(answer), systemImage: "person.fill.checkmark")
                                .shieldFont(.subheadline)
                                .foregroundStyle(ShieldPalette.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("service.previousAnswer")
                        }
                    }
                    AnswerButtons(options: [(.didIt, "answer.didIt"), (.notSure, "answer.notSure"), (.notNow, "answer.notNow")]) { answer in
                        model.answer(answer, for: .accountStep(serviceKey, step.step))
                        index += 1
                    }
                    if index > 0 {
                        Button {
                            index -= 1
                        } label: {
                            ButtonLabel(L.t("action.back"), systemImage: "chevron.left")
                        }
                        .buttonStyle(.shieldQuiet)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            SelfCheckFooter()
        }
        .shieldNavigationTitle(L.t(service.nameKey))
    }

    static func previousAnswerText(_ answer: SelfAnswer) -> String {
        L.fill("accounts.step.previousAnswer", ["answer": L.t(answerKey(answer))])
    }

    /// "Why: …" under a step. The reasons are plain text (no Markdown).
    static func whyText(_ whyKey: String) -> String {
        L.fill("accounts.step.whyLine", ["why": L.t(whyKey)])
    }

    static func answerKey(_ answer: SelfAnswer) -> String {
        switch answer {
        case .didIt: "answer.didIt"
        case .notSure: "answer.notSure"
        case .notNow: "answer.notNow"
        }
    }
}
