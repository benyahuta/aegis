// §10.1 11 / §7 Family Rules: all six rules on one scrolling screen, one card per rule, so
// nobody has to page through them. Rule 6 asks about the family code word: [We have one] / [Not yet].

import SwiftUI
import ShieldCore

struct FamilyRulesScreen: View {
    let model: AppModel

    static let symbols = [
        "phone.arrow.up.right.fill",
        "number.square.fill",
        "giftcard.fill",
        "exclamationmark.bubble.fill",
        "terminal.fill",
        "person.2.wave.2.fill",
    ]

    var body: some View {
        ScreenScaffold("familyRules") {
            ForEach(Self.symbols.indices, id: \.self) { index in
                RuleCard(number: index + 1, symbol: Self.symbols[index])
            }

            if let answer = model.currentAnswer(.check(.familyCodeWord)) {
                NoticeCard(answer == .didIt ? .done : .toDo,
                           L.t(answer == .didIt ? "check.family_code_word.pass" : "check.family_code_word.fail"))
            }
            AnswerButtons(options: [(.didIt, "answer.codeWord.haveOne"), (.notNow, "answer.codeWord.notYet")]) { answer in
                model.answer(answer, for: .check(.familyCodeWord))
            }

            Button {
                model.pop()
            } label: {
                Text(L.t("action.done"))
            }
            .buttonStyle(.shieldSecondary)
            .accessibilityIdentifier("rules.done")
        }
        .shieldNavigationTitle(L.t("rules.title"))
    }
}

/// One rule: an icon beside the rule text; icon above the text at accessibility text sizes.
private struct RuleCard: View {
    let number: Int
    let symbol: String
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 48
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Card(padding: 20) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { icon; text }
            } else {
                HStack(alignment: .top, spacing: 16) { icon; text }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rules.card.\(number)")
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize * 0.5, weight: .semibold))
            .foregroundStyle(ShieldPalette.brandText.color)
            .frame(width: iconSize, height: iconSize)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ShieldPalette.brandSoft.color))
            .accessibilityHidden(true)
    }

    private var text: some View {
        Text(L.a("rules.\(number)"))
            .shieldFont(.title3, weight: .semibold)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
