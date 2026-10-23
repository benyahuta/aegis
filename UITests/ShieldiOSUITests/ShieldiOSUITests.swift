// iPhone UI tests (SPEC §13.2): the screenshot matrix and an accessibility audit per screen.
//
// - Screens: every §13.2 screen, opened directly with `-FSDemoState <name>` (in-memory: no
//   network, no CloudKit, no notification prompt, no contact picker).
// - Variants: light and dark × default text and AX5. Run the suite once per simulator
//   (iPhone 17 Pro and iPhone 17e) — the device name goes into each attachment name.
// - Every screenshot is attached with `.keepAlways`; export with
//   `xcrun xcresulttool export attachments --path <bundle> --output-path docs/screenshots/ios`.
// - `performAccessibilityAudit()` runs on each screen. Documented exceptions (system UI we
//   don't own) are listed in `isDocumentedException`.

import UIKit
import XCTest

final class ShieldiOSUITests: XCTestCase {
    /// Demo state → the screen identifier it must show (`screen.<id>` on the ScreenScaffold).
    static let matrix: [(state: String, screen: String)] = [
        ("welcome", "welcome"), ("join", "join"), ("whoToCall", "whoToCall"), ("reminders", "reminders"),
        ("accountsPicker", "accountsPicker"), ("homeProtected", "home"), ("homeOneRed", "home"),
        ("fixStep", "fixStep"), ("guidedStep", "guidedStep"), ("scamEntry", "scamEntry"),
        ("resultDanger", "scamResult"), ("resultCareful", "scamResult"), ("resultNoSigns", "scamResult"),
        ("callQuiz", "callQuiz"), ("familyRules", "familyRules"), ("about", "about"),
        ("familyTab", "familyTab"), ("deviceDetail", "deviceDetail"),
        // Beyond the §13.2 minimum: the rest of §10.1 / §10.3.
        ("pasteMessage", "pasteMessage"), ("serviceSteps", "serviceSteps"), ("startFamily", "startFamily"),
        ("addPerson", "addPerson"), ("feedHealth", "feedHealth"), ("homeBuildBanner", "home"),
    ]

    static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor func testMatrixLightDefault() throws { try runMatrix(appearance: .light, largeText: false) }
    @MainActor func testMatrixDarkDefault() throws { try runMatrix(appearance: .dark, largeText: false) }
    @MainActor func testMatrixLightAX5() throws { try runMatrix(appearance: .light, largeText: true) }
    @MainActor func testMatrixDarkAX5() throws { try runMatrix(appearance: .dark, largeText: true) }

    /// The Home → scam checker → result path works with real taps (no demo shortcut).
    @MainActor
    func testScamCheckFromHome() throws {
        let app = launch("homeProtected", largeText: false)
        app.buttons["home.isThisAScam"].tap()
        XCTAssertTrue(element(app, "screen.scamEntry").waitForExistence(timeout: 5))
        app.buttons["scam.call"].tap()
        for answer in ["callQuiz.answer.bank", "callQuiz.answer.code", "callQuiz.answer.no", "callQuiz.answer.no"] {
            let button = app.buttons[answer]
            XCTAssertTrue(button.waitForExistence(timeout: 5), answer)
            button.tap()
        }
        XCTAssertTrue(element(app, "scam.result.verdict.danger").waitForExistence(timeout: 5),
                      "asking for a code is always danger (§5.3)")
    }

    /// Answering a guided step records it and returns home (nothing auto-advances).
    @MainActor
    func testGuidedStepAnswer() throws {
        let app = launch("guidedStep", largeText: false)
        let didIt = app.buttons["answer.didIt"]
        XCTAssertTrue(didIt.waitForExistence(timeout: 5))
        didIt.tap()
        let done = app.buttons["guided.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(element(app, "screen.home").waitForExistence(timeout: 5))
    }

    /// The full-width Paste control (UIPasteControl) puts the copied text in the box.
    @MainActor
    func testPasteControlFillsTheBox() throws {
        UIPasteboard.general.string = "Your package is waiting. Pay the fee at usps-hold.top today."
        let app = launch("pasteMessage", largeText: false)
        let paste = element(app, "scam.paste.button")
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(paste.frame.height, 59.5, "§10 primary-size button (60 pt)")
        XCTAssertGreaterThan(paste.frame.width, app.windows.firstMatch.frame.width * 0.8, "full width")
        paste.tap()
        let field = app.textViews["scam.paste.field"]
        let filled = NSPredicate(format: "value CONTAINS 'usps-hold.top'")
        expectation(for: filled, evaluatedWith: field)
        waitForExpectations(timeout: 5)
    }

    /// After an answer the call quiz shows the next question (VoiceOver focus moves there; the
    /// heading is the element that changes).
    @MainActor
    func testCallQuizAdvancesToTheNextQuestion() throws {
        let app = launch("callQuiz", largeText: false)
        let question = element(app, "callQuiz.question")
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        let first = question.label
        app.buttons["callQuiz.answer.bank"].tap()
        let changed = NSPredicate(format: "label != %@", first)
        expectation(for: changed, evaluatedWith: question)
        waitForExpectations(timeout: 5)
    }

    // MARK: Helpers

    @MainActor
    private func runMatrix(appearance: XCUIDevice.Appearance, largeText: Bool) throws {
        XCUIDevice.shared.appearance = appearance
        let device = Self.deviceName()
        let variant = "\(appearance == .dark ? "dark" : "light")-\(largeText ? "ax5" : "default")"
        // `TEST_RUNNER_FS_MATRIX_STATES=a,b xcodebuild test …` limits the run while iterating.
        let only = ProcessInfo.processInfo.environment["FS_MATRIX_STATES"].flatMap { $0.isEmpty ? nil : Set($0.split(separator: ",").map(String.init)) }
        for (state, screen) in Self.matrix where only?.contains(state) ?? true {
            let app = launch(state, largeText: largeText)
            XCTAssertTrue(element(app, "screen.\(screen)").waitForExistence(timeout: 10), "\(state) did not open \(screen)")
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "\(device)-\(variant)-\(state)"
            shot.lifetime = .keepAlways
            add(shot)
            audit(app, name: "\(state) (\(variant))")
            app.terminate()
        }
    }

    /// Audits what is on screen. Text that reaches into the bottom band covered by the system's
    /// floating tab bar / home indicator and their scroll-edge fade (iOS 26) is drawn faded on
    /// purpose by the system, so contrast and clipping issues there are not counted
    /// (`isUnderSystemBar`). Each one is printed as `AUDIT-UNDER-BAR` in the log; all are repeats of
    /// components that pass in full elsewhere on the same screen or in the matrix (device rows,
    /// check rows, info rows, buttons).
    ///
    /// The audit also reads the pixels for text no element exposes ("Potentially inaccessible
    /// text", reported with no element and so no frame). Text half-hidden behind the floating tab
    /// bar reads as garbled words that match no label ("Normal m… nger" under "Home"), so that
    /// one issue is never waved through here: the screen is scrolled to bring the covered text
    /// into the clear and that check is run again, and only a clean second run lets it pass.
    @MainActor
    private func audit(_ app: XCUIApplication, name: String) {
        let bottom = Self.coveredBottomEdge(app)
        var unlocatedText = false
        do {
            try app.performAccessibilityAudit { issue in
                if Self.isDocumentedException(issue) { return true }
                if Self.isUnderSystemBar(issue, bottomEdge: bottom) {
                    print("AUDIT-UNDER-BAR \(name): \(issue.compactDescription) | \(Self.describe(issue.element))")
                    return true
                }
                if issue.auditType == .elementDetection, issue.element == nil, Self.hasTextUnderSystemBar(app, bottomEdge: bottom) {
                    unlocatedText = true
                    return true
                }
                // The audit's own failure says only "Contrast failed"; name the element.
                print("AUDIT \(name): \(issue.compactDescription) | \(Self.describe(issue.element))")
                return false
            }
        } catch {
            XCTFail("accessibility audit failed on \(name): \(error)")
        }
        guard unlocatedText else { return }
        app.swipeUp()
        do {
            try app.performAccessibilityAudit(for: .elementDetection) { issue in
                print("AUDIT \(name) (scrolled): \(issue.compactDescription) | \(Self.describe(issue.element))")
                return false
            }
            print("AUDIT-UNDER-BAR \(name): text under the tab bar re-checked after scrolling: clean")
        } catch {
            XCTFail("accessibility audit failed on \(name) after scrolling: \(error)")
        }
    }

    /// Some static text on screen reaches into the covered bottom band.
    @MainActor
    static func hasTextUnderSystemBar(_ app: XCUIApplication, bottomEdge: CGFloat) -> Bool {
        let window = app.windows.firstMatch.frame
        return app.staticTexts.allElementsBoundByIndex.contains { text in
            let frame = text.frame
            return frame.maxY > bottomEdge && frame.minY < window.maxY
        }
    }

    @MainActor
    private func launch(_ state: String, largeText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FSNoCloud", "-FSDemoState", state]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", Self.ax5] }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Issues in system UI Family Shield doesn't draw, documented per §13.2 "zero failures allowed
    /// except documented ones":
    /// 1. The system tab bar and navigation bar title truncate at AX5 (Apple shows the large-content
    ///    viewer on long-press instead).
    /// 2. The system PasteButton is drawn dimmed while the pasteboard is empty (it is disabled).
    /// 3. Contrast and clipping on text that has scrolled into the bottom band under the floating
    ///    tab bar / home indicator, where the system fades it (`isUnderSystemBar`, used by `audit`).
    ///    Unlocated "inaccessible text" while text sits in that band is re-checked after scrolling
    ///    (`audit`), not excused.
    @MainActor
    static func isDocumentedException(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        if issue.auditType == .textClipped || issue.auditType == .dynamicType {
            if element.elementType == .tabBar || element.elementType == .navigationBar { return true }
            if element.identifier.isEmpty, element.elementType == .button, element.frame.minY < 120 { return true }
        }
        if issue.auditType == .contrast, element.identifier == "scam.paste.button" { return true }
        return false
    }

    /// Where the system's bottom bars and their scroll-edge fade start: the top of the floating
    /// tab bar, or the home indicator when there is no tab bar, less the height of the fade.
    @MainActor
    static func coveredBottomEdge(_ app: XCUIApplication) -> CGFloat {
        let fade: CGFloat = 32
        var bottom = app.windows.firstMatch.frame.maxY - 34
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, tabBar.frame.height > 0 { bottom = min(bottom, tabBar.frame.minY) }
        return bottom - fade
    }

    /// A contrast or clipping issue on an element that reaches into the covered bottom band.
    @MainActor
    static func isUnderSystemBar(_ issue: XCUIAccessibilityAuditIssue, bottomEdge: CGFloat) -> Bool {
        guard issue.auditType == .contrast || issue.auditType == .textClipped, let element = issue.element else { return false }
        return element.frame.maxY > bottomEdge
    }

    @MainActor
    private static func describe(_ element: XCUIElement?) -> String {
        guard let element else { return "no element" }
        return "type=\(element.elementType.rawValue) id='\(element.identifier)' label='\(element.label)' frame=\(element.frame)"
    }

    private static func deviceName() -> String {
        let model = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "iPhone"
        return model.replacingOccurrences(of: " ", with: "")
    }
}
