// §10.1 9–10: "Is this a scam?" (paste, screenshot, call quiz) and the Result screen.
// Everything here lives in memory only and is forgotten when the person leaves (§5.3, §12.3).

import PhotosUI
import SwiftUI
import ShieldCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: 9. Entry

struct ScamEntryScreen: View {
    let model: AppModel
    @State private var photo: PhotosPickerItem?
    @State private var loadFailed = false
    @State private var dropTargeted = false

    var body: some View {
        ScreenScaffold("scamEntry") {
            ScreenHeader(systemImage: "questionmark.bubble.fill", title: L.t("scam.entry.title"),
                         detail: AttributedString(L.t("scam.entry.question")))
            VStack(spacing: 14) {
                Button {
                    model.open(.pasteMessage)
                } label: {
                    ButtonLabel(L.t("scam.entry.paste"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.shieldPrimary)
                .accessibilityIdentifier("scam.paste")

                #if os(macOS)
                // §10.2: the Mac takes a picture file (file picker or drag and drop).
                MacScreenshotIntake(model: model, loadFailed: $loadFailed, dropTargeted: $dropTargeted)
                #else
                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    ButtonLabel(L.t("scam.entry.screenshot"), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.shieldPrimary)
                .accessibilityIdentifier("scam.screenshot")
                #endif

                Button {
                    model.open(.callQuiz)
                } label: {
                    ButtonLabel(L.t("scam.entry.call"), systemImage: "phone.arrow.down.left")
                }
                .buttonStyle(.shieldPrimary)
                .accessibilityIdentifier("scam.call")
            }
            if model.isCheckingScam {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L.t("scam.screenshot.reading")).shieldFont(.body)
                }
                .accessibilityElement(children: .combine)
            }
            if loadFailed {
                NoticeCard(.toDo, L.t("scam.screenshot.failed"))
            }
            PrivacyLine()
            CallBenButton(model: model)
        }
        .shieldNavigationTitle(L.t("scam.entry.title"))
        #if os(macOS)
        .dropDestination(for: DroppedImage.self) { images, _ in
            guard let image = images.first else {
                loadFailed = true
                return false
            }
            loadFailed = false
            Task { await model.checkScreenshot(image.data) }
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        #endif
        .onChange(of: photo) { _, item in
            guard let item else { return }
            loadFailed = false
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.checkScreenshot(data)
                } else {
                    loadFailed = true
                }
                photo = nil
            }
        }
    }
}

/// "Nothing you check here is saved or sent."
struct PrivacyLine: View {
    var body: some View {
        Label {
            Text(L.t("scam.privacy"))
                .shieldFont(.callout)
                .foregroundStyle(ShieldPalette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill").foregroundStyle(ShieldPalette.brandText.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scam.privacy")
    }
}

// MARK: Paste a message

struct PasteMessageScreen: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScreenScaffold("pasteMessage") {
            ScreenHeader(title: L.t("scam.paste.title"), detail: L.a(L.platformKey("scam.paste.hint", model.platform)))
            ShieldPasteButton(onPaste: { text in
                model.scamDraft = text
            }, onPasteImage: { image in
                Task { await model.checkScreenshot(image) }
            })
            if model.isCheckingScam {
                NoticeCard(info: L.t("scam.paste.picture"))
                    .accessibilityIdentifier("scam.paste.picture")
            }

            TextEditor(text: $model.scamDraft)
                .shieldFont(.body)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 180)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ShieldPalette.card.color))
                // The box's only edge, so it is at least 3:1 (WCAG 1.4.11) by default: the Mac
                // copy says "click in the box below", and an empty box has nothing else to see.
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ShieldPalette.strongOutline.color, lineWidth: contrast == .increased ? 2 : 1))
                .accessibilityLabel(L.t("scam.paste.fieldLabel"))
                .accessibilityIdentifier("scam.paste.field")
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

            Button {
                focused = false
                Task { await model.checkMessage() }
            } label: {
                ButtonLabel(L.t("scam.paste.check"), systemImage: "magnifyingglass")
            }
            .buttonStyle(.shieldPrimary)
            // Return types a new line in the box above, so the shortcut is Command-Return.
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.scamDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isCheckingMessage)
            .accessibilityIdentifier("scam.paste.check")

            if !model.scamDraft.isEmpty {
                Button {
                    model.scamDraft = ""
                } label: {
                    Text(L.t("scam.paste.clear"))
                }
                .buttonStyle(.shieldQuiet)
                .frame(maxWidth: .infinity)
            }
            PrivacyLine()
        }
        .shieldNavigationTitle(L.t("scam.paste.title"))
    }
}

// MARK: Call quiz

struct CallQuizScreen: View {
    let model: AppModel
    @State private var question = 0
    @State private var caller: CallQuiz.Caller?
    @State private var want: CallQuiz.Want?
    @State private var rushed: Bool?

    private let total = 4

    var body: some View {
        ScreenScaffold("callQuiz") {
            CounterText(L.fill("scam.call.counter", ["n": "\(question + 1)", "total": "\(total)"]))
            Text(L.a(questionKey))
                .shieldFont(.title, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("callQuiz.question")
                .accessibilityFocusOnChange(of: question)
            VStack(spacing: 12) {
                switch question {
                case 0:
                    ForEach(Array(CallQuiz.Caller.allCases.enumerated()), id: \.element) { offset, option in
                        answerButton(L.label(option), selected: caller == option, id: option.rawValue, number: offset + 1) {
                            caller = option
                            question = 1
                        }
                    }
                case 1:
                    ForEach(Array(CallQuiz.Want.allCases.enumerated()), id: \.element) { offset, option in
                        answerButton(L.label(option), selected: want == option, id: option.rawValue, number: offset + 1) {
                            want = option
                            question = 2
                        }
                    }
                case 2:
                    yesNo(selected: rushed) { value in
                        rushed = value
                        question = 3
                    }
                default:
                    yesNo(selected: nil) { value in
                        guard let caller, let want, let rushed else { return }
                        model.finishCallQuiz(CallQuiz.Answers(caller: caller, want: want, secretOrRushed: rushed, youCalledThem: value))
                    }
                }
            }
            if question > 0 {
                Button {
                    question -= 1
                } label: {
                    ButtonLabel(L.t("action.back"), systemImage: "chevron.left")
                }
                .buttonStyle(.shieldQuiet)
                .frame(maxWidth: .infinity)
            }
            PrivacyLine()
        }
        .shieldNavigationTitle(L.t("scam.call.title"))
    }

    private var questionKey: String {
        ["scam.call.q1", "scam.call.q2", "scam.call.q3", "scam.call.q4"][min(question, 3)]
    }

    private func answerButton(_ title: String, selected: Bool, id: String, number: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(ShieldButtonStyle(selected ? .primary : .secondary))
        .shieldNumberShortcut(number)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("callQuiz.answer.\(id)")
    }

    @ViewBuilder
    private func yesNo(selected: Bool?, action: @escaping (Bool) -> Void) -> some View {
        answerButton(L.t("answer.yes"), selected: selected == true, id: "yes", number: 1) { action(true) }
        answerButton(L.t("answer.no"), selected: selected == false, id: "no", number: 2) { action(false) }
    }
}

// MARK: 10. Result

struct ScamResultScreen: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let outcome = model.scamOutcome {
            content(outcome)
        } else {
            ScreenScaffold("scamResult") {
                Button {
                    model.checkAnother()
                } label: {
                    Text(L.t("scam.result.checkAnother"))
                }
                .buttonStyle(.shieldPrimary)
            }
        }
    }

    private func content(_ outcome: ScamOutcome) -> some View {
        let appearance = outcome.verdict.appearance
        return ScreenScaffold("scamResult") {
            VerdictHeader(outcome: outcome)

            if !outcome.reasons.isEmpty {
                Card {
                    SectionHeading(L.t("scam.result.reasons"))
                    ForEach(Array(outcome.reasons.enumerated()), id: \.offset) { _, reason in
                        GlyphRow {
                            Image(systemName: appearance == .cantCheck ? "circle.fill" : appearance.symbolName)
                                .shieldGlyphFont(.body)
                                .foregroundStyle(appearance.accent.color)
                                .accessibilityHidden(true)
                        } content: {
                            Text(reason)
                                .shieldFont(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("scam.result.reasons")
            }
            ForEach(outcome.limitations, id: \.self) { text in
                NoticeCard(info: text)
            }

            // `.contain`, not `.combine`: merging would make the rule itself a heading.
            Card {
                SectionHeading(L.t("scam.result.rule"))
                Text(L.a("rules.\(outcome.familyRuleNumber)"))
                    .shieldFont(.title3, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scam.result.rule")

            CallBenButton(model: model, kind: .primary, isDefaultAction: true)
            SendToBenButton(outcome: outcome)
            Label {
                // Say what the app did with a code it found: masked in pasted text, or the picture
                // left out. Otherwise the person is asked to leave any code out themselves.
                Text(L.t(outcome.screenshotLeftOut ? "scam.result.screenshotLeftOut"
                         : outcome.codeLeftOut ? "scam.result.codeLeftOut" : "scam.result.codeWarning"))
                    .shieldFont(.callout)
                    .foregroundStyle(ShieldPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "number.circle.fill").foregroundStyle(ShieldPalette.brandText.color)
            }
            .accessibilityElement(children: .combine)

            OfficialLinkButton(title: L.t("scam.result.report"), url: OfficialLinks.reportFraudFTC)
            PrivacyLine()
            Button {
                model.checkAnother()
            } label: {
                Text(L.t("scam.result.checkAnother"))
            }
            .buttonStyle(.shieldQuiet)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("scam.result.checkAnother")
        }
        .shieldNavigationTitle(L.t("scam.result.title"))
    }
}

struct VerdictHeader: View {
    let outcome: ScamOutcome
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let appearance = outcome.verdict.appearance
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        Card(padding: 22) {
            layout {
                StatusIcon(appearance, size: 80)
                VStack(alignment: .leading, spacing: 8) {
                    Text(outcome.headline)
                        .shieldFont(.title2, weight: .bold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outcome.headline)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("scam.result.verdict.\(outcome.verdict.rawValue)")
    }
}

/// "Send to Ben": the system share sheet. The person picks Ben and sends it themselves.
struct SendToBenButton: View {
    let outcome: ScamOutcome

    var body: some View {
        Group {
            if let data = outcome.screenshot, let image = PlatformImage.image(from: data) {
                ShareLink(item: image, message: Text(outcome.shareText),
                          preview: SharePreview(L.t("scam.result.sendToBen"), image: image)) {
                    ButtonLabel(L.t("scam.result.sendToBen"), systemImage: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: outcome.shareText) {
                    ButtonLabel(L.t("scam.result.sendToBen"), systemImage: "square.and.arrow.up")
                }
            }
        }
        .buttonStyle(.shieldSecondary)
        .accessibilityIdentifier("scam.result.sendToBen")
    }
}

enum PlatformImage {
    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        nil
        #endif
    }
}
