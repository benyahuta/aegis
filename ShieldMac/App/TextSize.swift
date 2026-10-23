// The Mac's text size (SPEC §11 "Dynamic Type through AX5"; §13.2 "largest text").
// macOS has no Dynamic Type for SwiftUI text styles, so Family Shield has its own:
// View → Bigger Text (⌘+), Smaller Text (⌘−), Actual Size (⌘0). The choice is a local
// per-Mac preference. `-FSTextSize <name>` (UI tests, screenshots) fixes it for one launch.

import Foundation
import Observation
import SwiftUI
import ShieldUI

@MainActor
@Observable
final class TextSizeSetting {
    static let defaultsKey = "fs.mac.textSize"

    private(set) var size: DynamicTypeSize
    @ObservationIgnored private let persist: Bool

    init(arguments: [String], persist: Bool, defaults: UserDefaults = .standard) {
        if let fixed = ShieldTypeScale.launchSize(arguments) {
            size = fixed
            self.persist = false
        } else {
            size = defaults.string(forKey: Self.defaultsKey).flatMap(ShieldTypeScale.size(named:)) ?? ShieldTypeScale.macDefault
            self.persist = persist
        }
    }

    var canGrow: Bool { size != ShieldTypeScale.macSteps.last }
    var canShrink: Bool { size != ShieldTypeScale.macSteps.first }
    var isDefault: Bool { size == ShieldTypeScale.macDefault }

    func bigger() { set(ShieldTypeScale.step(size, by: 1)) }
    func smaller() { set(ShieldTypeScale.step(size, by: -1)) }
    func actualSize() { set(ShieldTypeScale.macDefault) }

    private func set(_ new: DynamicTypeSize) {
        size = new
        if persist { UserDefaults.standard.set(ShieldTypeScale.name(new), forKey: Self.defaultsKey) }
    }
}
