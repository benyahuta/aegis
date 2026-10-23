// ShieldUI: symbol + word + color for one status, as a single accessibility element (§10, §11).

import SwiftUI

public struct StatusLabel: View {
    private let appearance: StatusAppearance

    public init(_ appearance: StatusAppearance) {
        self.appearance = appearance
    }

    public var body: some View {
        Label {
            Text(appearance.word)
        } icon: {
            Image(systemName: appearance.symbolName)
        }
        .shieldFont(.headline)
        .foregroundStyle(appearance.accent.color)
        .accessibilityElement(children: .combine)
    }
}
