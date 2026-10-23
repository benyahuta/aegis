// Mac UI tests (SPEC §13.2): the main window and the menu-bar panel, light and dark, at the
// default and the largest text size, with an accessibility audit on each screen.
//
// - Every launch passes `-FSNoCloud -FSDemoState <name>`: in-memory model, no network, no
//   CloudKit, no checks, no Keychain, a fixed login-item state (SMAppService is never called).
// - `-FSAppearance light|dark` fixes the appearance; `-FSTextSize default|ax5` the text size
//   (macOS has no Dynamic Type for SwiftUI text, so Family Shield has its own size, §11).
// - Screenshots are attached with `.keepAlways`; export with
//   `xcrun xcresulttool export attachments --path <bundle> --output-path docs/screenshots/mac`.
// - Run these only with Ben at the Mac (docs/BUILDING.md): `xcodebuild test` and macOS UI tests
//   can show Developer Tools / Accessibility prompts. Unattended screenshots come from
//   `tools/mac-screenshots.sh` (the app draws its own windows, no prompts).

import XCTest

final class ShieldMacUITests: XCTestCase {
    /// Demo state → the screen identifier it must show (`screen.<id>` on the ScreenScaffold).
    static let matrix: [(state: String, screen: String)] = [
        ("welcome", "welcome"), ("join", "join"), ("keepChecking", "keepChecking"),
        ("keepCheckingApproval", "keepChecking"), ("whoToCall", "whoToCall"), ("reminders", "reminders"),
        ("accountsPicker", "accountsPicker"), ("homeProtected", "home"), ("homeOneRed", "home"),
        ("fixStep", "fixStep"), ("guidedStep", "guidedStep"), ("scamEntry", "scamEntry"),
        ("pasteMessage", "pasteMessage"), ("resultDanger", "scamResult"), ("resultCareful", "scamResult"),
        ("resultNoSigns", "scamResult"), ("callQuiz", "callQuiz"), ("familyRules", "familyRules"),
        ("about", "about"), ("familyTab", "familyTab"), ("deviceDetail", "deviceDetail"), ("feedHealth", "feedHealth"),
        ("optionalStep", "optionalStep"),
    ]

    /// The menu-bar panel in each of its three words.
    static let menuStates = ["homeProtected", "homeOneToDo", "homeOneRed"]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor func testWindowLightDefault() throws { try runWindowMatrix(dark: false, largest: false) }
    @MainActor func testWindowDarkDefault() throws { try runWindowMatrix(dark: true, largest: false) }
    @MainActor func testWindowLightLargest() throws { try runWindowMatrix(dark: false, largest: true) }
    @MainActor func testWindowDarkLargest() throws { try runWindowMatrix(dark: true, largest: true) }

    @MainActor func testMenuBarLightDefault() throws { try runMenuMatrix(dark: false, largest: false) }
    @MainActor func testMenuBarDarkDefault() throws { try runMenuMatrix(dark: true, largest: false) }
    @MainActor func testMenuBarLightLargest() throws { try runMenuMatrix(dark: false, largest: true) }
    @MainActor func testMenuBarDarkLargest() throws { try runMenuMatrix(dark: true, largest: true) }

    /// The window opens at the spec minimum size and never smaller (§11: 600×500 pt).
    @MainActor
    func testWindowMinimumSize() throws {
        let app = launch("homeProtected", dark: false, largest: false)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(window.frame.width, 600)
        XCTAssertGreaterThanOrEqual(window.frame.height, 500)
    }

    /// Keyboard only: ⌘K opens the scam checker, the call quiz answers, ⌘[ goes back (§11).
    @MainActor
    func testKeyboardNavigation() throws {
        let app = launch("homeProtected", dark: false, largest: false)
        XCTAssertTrue(element(app, "screen.home").waitForExistence(timeout: 10))
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(element(app, "screen.scamEntry").waitForExistence(timeout: 5), "⌘K opens Is this a scam?")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(element(app, "screen.home").waitForExistence(timeout: 5), "⌘[ goes back")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(element(app, "screen.about").waitForExistence(timeout: 5), "⌘, opens About & Privacy")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element(app, "screen.home").waitForExistence(timeout: 5), "Escape goes back")
    }

    /// Keyboard only, with macOS defaults (Keyboard navigation off, so Tab doesn't reach buttons):
    /// Return presses each screen's main button through first-run setup, and the call quiz is
    /// answered with number keys (§11).
    @MainActor
    func testReturnAndNumberKeysWithoutKeyboardNavigation() throws {
        let app = launch("welcome", dark: false, largest: false)
        XCTAssertTrue(element(app, "screen.welcome").waitForExistence(timeout: 10))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element(app, "screen.join").waitForExistence(timeout: 5), "Return = Get started")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(element(app, "screen.keepChecking").waitForExistence(timeout: 5), "Return = Continue")

        let quiz = launch("callQuiz", dark: false, largest: false)
        XCTAssertTrue(element(quiz, "screen.callQuiz").waitForExistence(timeout: 10))
        // Bank (1), Code (1), rushed: No (2), you called them: No (2).
        for key in ["1", "1", "2", "2"] { quiz.typeKey(key, modifierFlags: []) }
        XCTAssertTrue(element(quiz, "scam.result.verdict.danger").waitForExistence(timeout: 5))
    }

    /// The call quiz from Home with real clicks gives Danger for "asked for a code" (§5.3).
    @MainActor
    func testCallQuizFromHome() throws {
        let app = launch("homeProtected", dark: false, largest: false)
        app.buttons["home.isThisAScam"].click()
        XCTAssertTrue(element(app, "screen.scamEntry").waitForExistence(timeout: 5))
        app.buttons["scam.call"].click()
        for answer in ["callQuiz.answer.bank", "callQuiz.answer.code", "callQuiz.answer.no", "callQuiz.answer.no"] {
            let button = app.buttons[answer]
            XCTAssertTrue(button.waitForExistence(timeout: 5), answer)
            button.click()
        }
        XCTAssertTrue(element(app, "scam.result.verdict.danger").waitForExistence(timeout: 5))
    }

    /// The login-item screen's button exists, and the demo state never registers anything.
    @MainActor
    func testKeepCheckingScreen() throws {
        let app = launch("keepChecking", dark: false, largest: false)
        XCTAssertTrue(element(app, "screen.keepChecking").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "loginItem.expected").exists, "§10.2 'That's expected, that's us.'")
        XCTAssertTrue(app.buttons["loginItem.action"].exists)
    }

    // MARK: Helpers

    @MainActor
    private func runWindowMatrix(dark: Bool, largest: Bool) throws {
        let variant = Self.variant(dark: dark, largest: largest)
        for (state, screen) in Self.matrix {
            let app = launch(state, dark: dark, largest: largest)
            XCTAssertTrue(element(app, "screen.\(screen)").waitForExistence(timeout: 10), "\(state) did not open \(screen)")
            let window = app.windows.firstMatch
            let shot = XCTAttachment(screenshot: window.exists ? window.screenshot() : XCUIScreen.main.screenshot())
            shot.name = "mac-\(variant)-\(state)"
            shot.lifetime = .keepAlways
            add(shot)
            audit(app, "\(state) (\(variant))")
            app.terminate()
        }
    }

    @MainActor
    private func runMenuMatrix(dark: Bool, largest: Bool) throws {
        let variant = Self.variant(dark: dark, largest: largest)
        for state in Self.menuStates {
            let app = launch(state, dark: dark, largest: largest)
            let item = app.statusItems.firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 10), "\(state): no menu-bar item")
            XCTAssertFalse(item.label.isEmpty, "the menu-bar item has an accessibility label")
            item.click()
            let panel = element(app, "menubar.panel")
            XCTAssertTrue(panel.waitForExistence(timeout: 5), "\(state): the menu-bar panel did not open")
            let shot = XCTAttachment(screenshot: panel.exists ? panel.screenshot() : XCUIScreen.main.screenshot())
            shot.name = "menubar-\(variant)-\(state)"
            shot.lifetime = .keepAlways
            add(shot)
            audit(app, "menubar \(state) (\(variant))")
            app.terminate()
        }
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ context: String) {
        do {
            try app.performAccessibilityAudit { issue in Self.isDocumentedException(issue) }
        } catch {
            XCTFail("accessibility audit failed on \(context): \(error)")
        }
    }

    @MainActor
    private func launch(_ state: String, dark: Bool, largest: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-FSNoCloud", "-FSDemoState", state,
            "-FSAppearance", dark ? "dark" : "light",
            "-FSTextSize", largest ? "ax5" : "default",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private static func variant(dark: Bool, largest: Bool) -> String {
        "\(dark ? "dark" : "light")-\(largest ? "ax5" : "default")"
    }

    /// System UI Family Shield doesn't draw (§13.2 "zero failures allowed except documented ones"):
    /// 1. The system PasteButton is dimmed while the pasteboard is empty (it is disabled).
    /// 2. The traffic-light window buttons have system hit regions smaller than 44 pt.
    /// (macOS audits have no text-clipped or Dynamic Type checks; the AX5 screenshots cover those.)
    @MainActor
    static func isDocumentedException(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        if issue.auditType == .contrast, element.identifier == "scam.paste.button" { return true }
        if issue.auditType == .hitRegion, element.identifier.hasPrefix("_XCUI:") { return true }
        return false
    }
}
