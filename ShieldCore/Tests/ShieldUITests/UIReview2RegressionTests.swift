import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
import ShieldCore
@testable import ShieldUI

/// Regressions from the second UI review: layout at the largest text sizes, VoiceOver parity,
/// tap/click wording and copy that contradicts the person's own answers.
@MainActor
final class UIReview2RegressionTests: XCTestCase {
    // MARK: Menu-bar panel fits a laptop screen at the largest text size

    #if os(macOS)
    func testMenuBarPanelFitsALaptopScreenAtTheLargestTextSize() {
        for screen in [DemoScreen.homeOneRed, .homeProtected, .homeOneToDo] {
            let model = AppModel.demo(screen, platform: .mac)
            let screenHeight = MenuBarPanel.smallLaptopScreenHeight
            let panel = MenuBarPanel(model: model, screenHeight: screenHeight, openWindow: {}, quit: {})
                .environment(\.dynamicTypeSize, .accessibility5)
            let host = NSHostingView(rootView: panel)
            let size = host.fittingSize
            XCTAssertLessThanOrEqual(size.height, screenHeight - 40, "\(screen): the panel must fit under the menu bar of a 13-inch MacBook")
            XCTAssertGreaterThan(size.height, 200, "\(screen): the panel still shows its status and buttons")
        }
    }
    #endif

    func testMenuBarBodyHeightLeavesRoomForTheFooter() {
        for ax in [false, true] {
            XCTAssertLessThanOrEqual(MenuBarPanel.maxBodyHeight(screenHeight: 875, accessibilitySize: ax) + 110, 875 - 40)
            XCTAssertLessThanOrEqual(MenuBarPanel.maxBodyHeight(screenHeight: nil, accessibilitySize: ax) + 110,
                                     MenuBarPanel.smallLaptopScreenHeight - 40)
            XCTAssertGreaterThanOrEqual(MenuBarPanel.maxBodyHeight(screenHeight: 300, accessibilitySize: ax), 240, "never collapses to nothing")
        }
    }

    // MARK: Account tiles: the badge grows with its glyph

    func testServiceTileBadgeGrowsWithTheText() {
        XCTAssertEqual(ServiceTile.badgeSize(.large), 44)
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            XCTAssertGreaterThanOrEqual(ServiceTile.badgeSize(size), ShieldTypeScale.points(.title2, size) * 1.5,
                                        "\(size): the glyph fits inside its circle")
        }
    }

    // MARK: Fix cards keep their Settings button (§10.2) except next to Call Ben on red (H9)

    func testFixCardSettingsButton() {
        XCTAssertTrue(FixStepScreen.offersSettings(callBen: false, red: false, hasLink: true))
        XCTAssertTrue(FixStepScreen.offersSettings(callBen: false, red: true, hasLink: true))
        XCTAssertTrue(FixStepScreen.offersSettings(callBen: true, red: false, hasLink: true),
                      "Remote access says 'Open System Settings → General → Sharing': it has its button")
        XCTAssertFalse(FixStepScreen.offersSettings(callBen: true, red: true, hasLink: true), "H9")
        XCTAssertFalse(FixStepScreen.offersSettings(callBen: false, red: false, hasLink: false))
    }

    // MARK: VoiceOver hears what is on screen

    func testDeviceRowSaysTheCreatorWarning() {
        var device = DashboardDevice(deviceID: UUID(), label: "Mom's iPhone", platform: .ios, enrolledOn: nil,
                                     lastReport: nil, appBuild: nil, catalogVersion: nil, daysSinceReport: 0,
                                     staleness: .fresh, worstStatus: .pass, checks: [], creatorMismatch: false)
        XCTAssertFalse(DeviceRow.spokenLabel(device).contains(L.t("deviceDetail.creatorMismatch")))
        device.creatorMismatch = true
        XCTAssertTrue(DeviceRow.spokenLabel(device).contains(L.t("deviceDetail.creatorMismatch")),
                      "the red warning is never visual-only")
    }

    func testHomeHeaderSaysTheAllDoneDetail() {
        let label = HomeStatusHeader.spokenLabel(home: .protected, word: "Done", checked: "Checked today at 9:14 AM.")
        XCTAssertTrue(label.contains(L.t("home.allDone.detail").trimmingCharacters(in: CharacterSet(charactersIn: "."))), label)
        XCTAssertTrue(label.hasSuffix("Checked today at 9:14 AM."), label)
    }

    func testPreviousAnswerHasContext() {
        let text = ServiceStepsScreen.previousAnswerText(.didIt)
        XCTAssertTrue(text.contains(L.t("answer.didIt")))
        XCTAssertNotEqual(text, L.t("answer.didIt"), "never a bare 'I did it' next to the I did it button")
    }

    func testServiceStepShowsItsWhyLine() {
        let reason = L.t("service.bank.why.alerts")
        XCTAssertEqual(ServiceStepsScreen.whyText("service.bank.why.alerts"), "Why: " + reason)
        XCTAssertFalse(ServiceStepsScreen.whyText("accounts.why.2fa").contains("{why}"))
    }

    func testMacHintsDontSayDoubleTap() {
        for base in ["a11y.hint.showHow", "a11y.hint.deviceDetail"] {
            XCTAssertTrue(L.t(L.platformKey(base, .ios)).hasPrefix("Double-tap"), base)
            XCTAssertFalse(L.t(L.platformKey(base, .mac)).lowercased().contains("tap"), base)
        }
    }

    // MARK: Tap on the iPhone, click on the Mac

    /// Copy read with a fixed key in the shared screens is shown on both platforms, so it never
    /// says "tap" or "click" (one of them would be wrong); such copy is split with
    /// `L.platformKey` instead. Allowed: keys read only in a Mac-only or iPhone-only branch, and
    /// sentences that name both ("tap or click").
    func testSharedCopyNeverSaysTapOrClick() throws {
        let platformOnly: Set<String> = [
            "scam.paste.nothingCopied",   // ShieldPasteButton, Mac branch
        ]
        let literal = try NSRegularExpression(pattern: #"L\.(?:t|a|plain|fill)\("([A-Za-z0-9_.]+)""#)
        let gesture = try NSRegularExpression(pattern: #"\b(tap|taps|tapped|tapping|double-tap|click|clicks|clicked|clicking)\b"#,
                                              options: .caseInsensitive)
        var keys: Set<String> = []
        guard let enumerator = FileManager.default.enumerator(at: Self.shieldUIRoot, includingPropertiesForKeys: nil) else {
            throw XCTSkip("ShieldUI sources not readable from this test host")
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in literal.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(match.range(at: 1), in: text) { keys.insert(String(text[r])) }
            }
        }
        XCTAssertGreaterThan(keys.count, 100)
        let offenders = keys.subtracting(platformOnly).filter { key in
            guard ShieldStrings.contains(key) else { return false }
            let value = ShieldStrings.text(key)
            let lower = value.lowercased()
            if lower.contains("tap") && lower.contains("click") { return false }
            return gesture.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        }.sorted()
        XCTAssertTrue(offenders.isEmpty, "split with L.platformKey (.ios says tap, .mac says click): \(offenders)")

        for base in ["share.failed.alreadyConnected", "share.failed.offline", "family.empty", "deviceDetail.text.update"] {
            XCTAssertTrue(L.t(L.platformKey(base, .mac)).lowercased().contains("click"), base)
            XCTAssertFalse(L.t(L.platformKey(base, .mac)).lowercased().contains("tap"), base)
            XCTAssertFalse(L.t(L.platformKey(base, .ios)).lowercased().contains("click"), base)
        }
    }

    static var shieldUIRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShieldUI")
    }
}
