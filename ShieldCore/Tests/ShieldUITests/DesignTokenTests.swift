import XCTest
import ShieldCore
@testable import ShieldUI

final class DesignTokenTests: XCTestCase {
    func testSymbolsAndWordsMatchSpec() {
        XCTAssertEqual(StatusAppearance.done.symbolName, "checkmark.shield.fill")
        XCTAssertEqual(StatusAppearance.toDo.symbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(StatusAppearance.today.symbolName, "exclamationmark.octagon.fill")
        XCTAssertEqual(StatusAppearance.cantCheck.symbolName, "questionmark.circle")
        XCTAssertEqual(StatusAppearance.allCases.map(\.word), ["Done", "To do", "Today", "Can't check"])
    }

    func testStatusMapping() {
        XCTAssertEqual(StatusAppearance(status: .pass, tier: .red), .done)
        XCTAssertEqual(StatusAppearance(status: .unknown, tier: .red), .cantCheck)
        XCTAssertEqual(StatusAppearance(status: .fail, tier: .red), .today)
        XCTAssertEqual(StatusAppearance(status: .fail, tier: .amber), .toDo)
        XCTAssertEqual(StatusAppearance(status: .fail, tier: .yellow), .toDo, "firewall is never red")
        XCTAssertEqual(Status.fail.appearance(tier: .info), .toDo)
    }

    /// §11: text >= 4.5:1 (which also covers icons >= 3:1) in light and dark.
    func testAccentContrastOnPageBackgrounds() {
        for appearance in StatusAppearance.allCases {
            for background in ShieldPalette.pageBackgrounds.light {
                XCTAssertGreaterThanOrEqual(appearance.accent.light.contrastRatio(with: background), 4.5,
                                            "\(appearance) light")
            }
            for background in ShieldPalette.pageBackgrounds.dark {
                XCTAssertGreaterThanOrEqual(appearance.accent.dark.contrastRatio(with: background), 4.5,
                                            "\(appearance) dark")
            }
        }
    }

    func testOnFillContrast() {
        for appearance in StatusAppearance.allCases {
            XCTAssertGreaterThanOrEqual(appearance.onFill.light.contrastRatio(with: appearance.fill.light), 4.5,
                                        "\(appearance) light")
            XCTAssertGreaterThanOrEqual(appearance.onFill.dark.contrastRatio(with: appearance.fill.dark), 4.5,
                                        "\(appearance) dark")
        }
    }

    func testAmberUsesDarkText() {
        let onAmber = StatusAppearance.toDo.onFill
        XCTAssertLessThan(onAmber.light.relativeLuminance, 0.05)
        XCTAssertLessThan(onAmber.dark.relativeLuminance, 0.05)
    }

    func testContrastMath() {
        let white = RGBColor(hex: 0xFFFFFF), black = RGBColor(hex: 0x000000)
        XCTAssertEqual(white.contrastRatio(with: black), 21, accuracy: 0.01)
        XCTAssertEqual(white.contrastRatio(with: white), 1, accuracy: 0.0001)
    }

    func testMetrics() {
        XCTAssertGreaterThanOrEqual(ShieldMetrics.primaryButtonMinHeight, 60)
        XCTAssertGreaterThanOrEqual(ShieldMetrics.minHitTarget, 44)
        XCTAssertEqual(ShieldMetrics.macWindowMinWidth, 600)
        XCTAssertEqual(ShieldMetrics.macWindowMinHeight, 500)
    }
}

/// ShieldCore's `Clock` must resolve (over the stdlib `Clock` protocol) in importing modules.
final class CrossModuleSharedTypeTests: XCTestCase {
    func testClockResolvesAcrossModules() {
        let clock: Clock = .fixed(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(clock.today(), DateDay(daysSinceEpoch: 0))
    }
}
