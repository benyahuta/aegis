// The big "Paste" button on "Paste a message" (SPEC §10 "Primary buttons at least 60 pt tall,
// full width"; §11 buttons grow with the text). The SwiftUI `PasteButton` keeps its own small
// system size whatever frame it gets, so:
// - iPhone: a `UIPasteControl` (the same privacy-preserving system control: no "Allow Paste"
//   alert, nothing read until the person taps it) laid out full width and at least 60 pt tall.
// - Mac: a Shield button that reads the pasteboard only when clicked (the click is the person's
//   own paste, like Edit → Paste). Words go in the box; a copied picture (a screenshot copied
//   with Control-Shift-Command-4, or Copy on an image in Messages or Mail) goes to the screenshot
//   check. Nothing is stored (§12.3).

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ShieldPasteButton: View {
    let onPaste: @MainActor (String) -> Void
    /// Mac: a copied picture instead of words.
    var onPasteImage: (@MainActor (Data) -> Void)?
    #if os(macOS)
    @State private var nothingCopied = false
    #endif
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        #if os(iOS)
        PasteControlRepresentable(onPaste: onPaste, minHeight: minHeight)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            // The identifier is on the UIPasteControl itself (one element, not two).
        #else
        VStack(alignment: .leading, spacing: 10) {
            Button {
                let pasteboard = NSPasteboard.general
                if let text = pasteboard.string(forType: .string),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    nothingCopied = false
                    onPaste(text)
                } else if let onPasteImage, let image = Self.imageData(pasteboard) {
                    nothingCopied = false
                    onPasteImage(image)
                } else {
                    nothingCopied = true
                    // The note appears under the button the person is still on: say it.
                    announceForAccessibility(L.t("scam.paste.nothingCopied"))
                }
            } label: {
                ButtonLabel(L.t("scam.paste.pasteButton"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.shieldSecondary)
            .accessibilityIdentifier("scam.paste.button")
            if nothingCopied {
                NoticeCard(info: L.t("scam.paste.nothingCopied"))
                    .accessibilityIdentifier("scam.paste.nothingCopied")
            }
        }
        #endif
    }

    #if os(macOS)
    /// A picture on the pasteboard (PNG, TIFF, or anything `NSImage` reads, such as JPEG/HEIC),
    /// as image data the screenshot check can read.
    static func imageData(_ pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        if let tiff = pasteboard.data(forType: .tiff) { return tiff }
        guard pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
              let image = NSImage(pasteboard: pasteboard) else { return nil }
        return image.tiffRepresentation
    }
    #endif

    /// 60 pt, growing with the text like the Shield buttons around it.
    private var minHeight: CGFloat {
        ShieldMetrics.primaryButtonMinHeight * max(1, ShieldTypeScale.points(.title3, typeSize) / ShieldTypeScale.points(.title3, .large))
    }
}

#if os(iOS)
private struct PasteControlRepresentable: UIViewRepresentable {
    let onPaste: @MainActor (String) -> Void
    let minHeight: CGFloat

    func makeUIView(context: Context) -> PasteHostView {
        let view = PasteHostView()
        view.onPaste = onPaste
        return view
    }

    func updateUIView(_ view: PasteHostView, context: Context) {
        view.onPaste = onPaste
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PasteHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: minHeight)
    }
}

/// Hosts the system paste control and receives what it pastes.
final class PasteHostView: UIView {
    var onPaste: (@MainActor (String) -> Void)?
    private let control: UIPasteControl

    override init(frame: CGRect) {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = UIColor(ShieldPalette.brandSoft.color)
        configuration.baseForegroundColor = UIColor(ShieldPalette.brandText.color)
        control = UIPasteControl(configuration: configuration)
        super.init(frame: frame)
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: ["public.utf8-plain-text", "public.plain-text", "public.text"])
        control.target = self
        control.translatesAutoresizingMaskIntoConstraints = false
        control.accessibilityIdentifier = "scam.paste.button"
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            guard let text = object as? NSString else { return }
            let string = String(text)
            Task { @MainActor in self?.onPaste?(string) }
        }
    }
}
#endif
