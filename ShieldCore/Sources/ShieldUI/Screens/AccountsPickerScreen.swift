// §10.1 5 / §6.4: "Which accounts do you use?" Big toggle tiles drawn with SF Symbols and text
// only (no third-party brand art, guideline 5.2). The selection is stored on this device only.

import SwiftUI
import ShieldCore

struct AccountsPickerScreen: View {
    let model: AppModel
    let onboarding: Bool
    @State private var selection: Set<ServiceKey> = []
    @State private var loaded = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 150 pt at the default size, growing with the tile names (headline): two tiles side by side
    /// on an iPhone at default sizes, one per row once the names need the width. Computed from the
    /// type scale rather than `@ScaledMetric`, which doesn't follow the Mac's own text size.
    private var minTileWidth: CGFloat {
        150 * ShieldTypeScale.points(.headline, typeSize) / ShieldTypeScale.points(.headline, .large)
    }

    var body: some View {
        ScreenScaffold("accountsPicker") {
            ScreenHeader(systemImage: "person.crop.rectangle.stack.fill", title: L.t("accounts.picker.title"),
                         detail: AttributedString(L.t("accounts.picker.later")))
            Secondary(L.t("accounts.picker.intro"))
            ForEach(AccountCategory.allCases, id: \.self) { category in
                let services = Services.services(in: category)
                if !services.isEmpty {
                    SectionHeading(L.t(category.nameKey))
                    ColumnsLayout(minColumnWidth: minTileWidth, spacing: 12) {
                        ForEach(services) { service in
                            ServiceTile(service: service, selected: selection.contains(service.key)) {
                                if selection.contains(service.key) {
                                    selection.remove(service.key)
                                } else {
                                    selection.insert(service.key)
                                }
                            }
                        }
                    }
                }
            }
            Button {
                model.setSelectedServices(selection)
                finish()
            } label: {
                Text(L.t("action.done"))
            }
            .buttonStyle(.shieldPrimary)
            .shieldDefaultAction()
            .accessibilityIdentifier("accounts.done")
            if onboarding || model.selectedServices.isEmpty {
                Button {
                    model.skipAccountsPicker()
                    finish()
                } label: {
                    Text(L.t("accounts.picker.skip"))
                }
                .buttonStyle(.shieldQuiet)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("accounts.skip")
            }
        }
        .shieldNavigationTitle(L.t("accounts.picker.title"))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            selection = model.selectedServices
        }
    }

    private func finish() {
        if onboarding {
            model.next(after: .accounts)
        } else {
            model.pop()
        }
    }
}

struct ServiceTile: View {
    let service: OnlineService
    let selected: Bool
    let toggle: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The round badge grows with its glyph (title2), so the glyph always sits inside its circle.
    static func badgeSize(_ typeSize: DynamicTypeSize) -> CGFloat {
        44 * max(1, ShieldTypeScale.points(.title2, typeSize) / ShieldTypeScale.points(.title2, .large))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let badge = Self.badgeSize(typeSize)
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: service.symbolName)
                        .shieldFont(.title2)
                        .foregroundStyle(selected ? ShieldPalette.onBrand.color : ShieldPalette.brandText.color)
                        .frame(width: badge, height: badge)
                        .background(Circle().fill(selected ? ShieldPalette.brand.color : ShieldPalette.brandSoft.color))
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .shieldFont(.title2)
                        .foregroundStyle(selected ? ShieldPalette.brandText.color : ShieldPalette.strongOutline.color)
                }
                Text(L.t(service.nameKey))
                    .shieldFont(.headline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(ShieldPalette.card.color))
            .overlay(shape.strokeBorder(selected ? ShieldPalette.brand.color
                                        : (contrast == .increased ? ShieldPalette.strongOutline.color : ShieldPalette.hairline.color),
                                        lineWidth: selected ? 2.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t(service.nameKey))
        .accessibilityValue(selected ? L.t("accounts.picker.selected") : L.t("accounts.picker.notSelected"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("service.\(service.key.rawValue)")
    }
}
