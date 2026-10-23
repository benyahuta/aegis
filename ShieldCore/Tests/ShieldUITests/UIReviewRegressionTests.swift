import XCTest
#if os(macOS)
import AppKit
#endif
import ShieldCore
@testable import ShieldUI

/// Regressions from the UI review (copy that contradicts what the app does, VoiceOver wording,
/// unreachable warnings).
@MainActor
final class UIReviewRegressionTests: XCTestCase {
    // MARK: Send to Ben never carries a one-time code (§0 H2)

    private func outcome(_ text: String) -> ScamOutcome {
        ScamOutcome(assessment: ScamChecker.assess(text: text), origin: .message, originalText: text)
    }

    func testShareTextMasksTheCode() {
        let text = "Your Chase code is 482913. Reply with it to confirm."
        let result = outcome(text)
        XCTAssertTrue(result.containsCode)
        XCTAssertTrue(result.codeLeftOut)
        XCTAssertFalse(result.shareText.contains("482913"), result.shareText)
        XCTAssertTrue(result.shareText.contains("Your Chase code is ••••••."), "the rest of the message is still there for Ben")
    }

    func testShareTextMasksEveryCodeShape() {
        for text in [
            "482913 is your verification code. Don't share it.",
            "Use PIN 4821 to finish signing in",
            "G-583920 is your Google verification code.",
            "Your passcode: ４８２９１３",              // full-width digits
            "Enter OTP 77125 now",
        ] {
            let result = outcome(text)
            XCTAssertTrue(result.codeLeftOut, text)
            let shared = result.shareText
            for run in text.split(whereSeparator: { !$0.isNumber }) where run.count >= 4 {
                XCTAssertFalse(shared.contains(run), "\(text) -> \(shared)")
            }
        }
    }

    /// A code hidden from the plain-text mask (an invisible character between its digits) is
    /// still found in the normalized reading, so the text is left out entirely.
    func testShareTextDropsTheMessageWhenTheCodeCanStillBeRead() {
        let text = "Your code is 48\u{200B}2913. Tell the agent."
        let result = outcome(text)
        XCTAssertTrue(result.containsCode)
        XCTAssertTrue(result.codeLeftOut)
        XCTAssertFalse(result.shareText.contains("2913"), result.shareText)
        XCTAssertFalse(result.shareText.contains("Tell the agent"), "no masked copy could be made, so no text at all")
    }

    func testShareTextKeepsMessagesWithoutACode() {
        let result = outcome(DemoScreen.dangerSample)
        XCTAssertFalse(result.codeLeftOut)
        XCTAssertTrue(result.shareText.hasSuffix(DemoScreen.dangerSample))
    }

    func testScreenshotWithACodeIsNeverAttached() {
        // A picture can't be masked: when the checker read a code in it, Send to Ben shares the
        // verdict line only, and says so (the "don't send the code" label can't be acted on).
        let text = "Your Chase code is 482913. Reply with it to confirm."
        let picture = Data([0x89, 0x50, 0x4E, 0x47])
        let result = ScamOutcome(assessment: ScamChecker.assess(text: text), origin: .screenshot,
                                 originalText: nil, screenshot: picture)
        XCTAssertTrue(result.containsCode)
        XCTAssertTrue(result.screenshotLeftOut)
        XCTAssertNil(result.screenshot, "the image is not handed to the share sheet")
        XCTAssertFalse(result.shareText.contains("482913"))
        XCTAssertTrue(result.shareText.contains("didn't send the picture"), result.shareText)
        XCTAssertTrue(ShieldStrings.contains("scam.result.screenshotLeftOut"))

        let clean = ScamOutcome(assessment: ScamChecker.assess(text: DemoScreen.dangerSample), origin: .screenshot,
                                originalText: nil, screenshot: picture)
        XCTAssertFalse(clean.screenshotLeftOut)
        XCTAssertEqual(clean.screenshot, picture, "a picture without a code is still sent")
    }

    #if os(macOS)
    func testMacPasteReadsACopiedPicture() throws {
        // ⌃⇧⌘4 or Copy on an image puts only image data on the pasteboard: that is not "nothing copied".
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("fs.test.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertNil(ShieldPasteButton.imageData(pasteboard))
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        pasteboard.setData(tiff, forType: .tiff)
        XCTAssertEqual(ShieldPasteButton.imageData(pasteboard), tiff)
    }
    #endif

    func testRedactionLeavesPhoneNumbersAndPricesAlone() {
        XCTAssertEqual(CodeDetector.redactingCodes(in: "Call 1-800-555-1234 about your $1999 order"),
                       "Call 1-800-555-1234 about your $1999 order")
    }

    // MARK: Notices: the status word is spoken only for real statuses (§10, §11)

    func testInfoNoticesHaveNoStatusWord() {
        XCTAssertEqual(NoticeCard(info: "You're no longer sharing with Ben.").spokenLabel, "You're no longer sharing with Ben.")
        XCTAssertEqual(NoticeCard(.done, "Reminders are on.").spokenLabel, "Done. Reminders are on.")
    }

    /// No screen uses the grey "Can't check" status for plain guidance: only Ben's stale-device
    /// notices (where every check really is "Can't check") may.
    func testCantCheckNoticesAreOnlyForUnknownStatus() throws {
        let screens = UICopyTests.shieldUIRoot.appendingPathComponent("Screens")
        var uses: [String] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: screens.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: screens.appendingPathComponent(name), encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("NoticeCard(.cantCheck") {
                uses.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        XCTAssertEqual(Set(uses), ["NoticeCard(.cantCheck, L.t(\"deviceDetail.stale\"))",
                                   "NoticeCard(.cantCheck, L.t(\"family.notReporting\"))"])
    }

    func testHomeHeaderLabelPausesBeforeTheStatusWord() {
        XCTAssertEqual(HomeStatusHeader.sentence("1 thing to do"), "1 thing to do.")
        XCTAssertEqual(HomeStatusHeader.sentence("1 thing to do today."), "1 thing to do today.")
    }

    // MARK: Answer responses

    func testDidItPromisesBenOnlyWhenConnected() {
        XCTAssertEqual(AnswerResponse.didItKey(connection: .connected, platform: .ios), "guided.saved.didIt")
        for connection in [SyncConnectionState.notJoined, .notConnected, .notDelivering] {
            for platform in Platform.allCases {
                let key = AnswerResponse.didItKey(connection: connection, platform: platform)
                XCTAssertFalse(L.t(key).contains("Ben"), "\(connection) \(platform): \(L.t(key))")
                XCTAssertTrue(ShieldStrings.contains(key), key)
            }
        }
    }

    func testNotNowGetsItsOwnResponse() throws {
        let source = try String(contentsOf: UICopyTests.shieldUIRoot.appendingPathComponent("Screens/GuidedStepScreen.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("pace.moreSoon"), "Not now is answered with its own sentence, not the Home pacing line")
        let service = try String(contentsOf: UICopyTests.shieldUIRoot.appendingPathComponent("Screens/ServiceStepsScreen.swift"), encoding: .utf8)
        XCTAssertFalse(service.contains("pace.moreSoon"))
        XCTAssertFalse(L.t("selfcheck.notNow.response").isEmpty)
        XCTAssertFalse(L.t("accounts.service.someLeft").isEmpty)
    }

    // MARK: Optional extras show their warning before Settings (§6.2, §6.3)

    func testOptionalExtrasOpenTheirOwnScreenWithTheWarning() {
        let model = DemoScreen.optionalStep.makeModel(platform: .mac)
        XCTAssertEqual(model.homePath, [.about, .optional(.adp)])
        let adp = model.snapshot.optionalLinks.first { $0.checkID == .adp }
        XCTAssertNotNil(adp)
        guard let adp else { return }
        XCTAssertEqual(model.item(.adp)?.kind, .optional)
        XCTAssertTrue(adp.noteKeys.contains("check.advanced_data_protection.note.recovery"))
        XCTAssertFalse(model.snapshot.optionalLinks.isEmpty)
        // Every optional extra (ADP, Lockdown Mode) opens its own screen, and each one tells the
        // person to talk to Ben before turning it on.
        for item in model.snapshot.optionalLinks {
            XCTAssertEqual(model.route(for: item), .optional(item.checkID))
            XCTAssertTrue((item.stepKeys + item.noteKeys).contains { L.t($0).contains("Talk to Ben") }, item.checkID.rawValue)
        }
    }

    // MARK: Copy that points at the layout

    func testCarrierPickStepPointsUp() {
        // The picker is drawn above the steps (GuidedStepScreen).
        XCTAssertFalse(L.t("check.carrier_lock.ios.step.pick").contains("below"))
        XCTAssertTrue(L.t("check.carrier_lock.ios.step.pick").contains("above"))
    }

    func testDeviceRowHintDescribesTheDetailScreen() {
        for platform in Platform.allCases {
            XCTAssertFalse(L.t(L.platformKey("a11y.hint.deviceDetail", platform)).contains("how"))
        }
    }
}
