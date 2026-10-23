import XCTest
import ShieldCore
@testable import ShieldUI

/// §11: every UI string lives in the String Catalog. Scans ShieldUI for `L.t("…")`-style keys.
final class UICopyTests: XCTestCase {
    static var shieldUIRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ShieldUI")
    }

    func testEveryLiteralKeyExistsInTheCatalog() throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: Self.shieldUIRoot, includingPropertiesForKeys: nil) else {
            throw XCTSkip("ShieldUI sources not readable")
        }
        let regex = try NSRegularExpression(pattern: #"L\.(?:t|a|plain|fill|plural)\("([A-Za-z0-9_.]+)""#)
        var keys: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { keys.insert(String(text[range])) }
            }
        }
        XCTAssertGreaterThan(keys.count, 100)
        let missing = keys.filter { !ShieldStrings.contains($0) }.sorted()
        XCTAssertTrue(missing.isEmpty, "missing from Localizable.xcstrings: \(missing)")
    }

    /// A value with `**bold**` read through the plain accessors would show literal asterisks.
    func testMarkdownValuesAreNeverShownThroughPlainText() throws {
        let fm = FileManager.default
        let roots = [Self.shieldUIRoot,
                     Self.shieldUIRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("ShieldMac"),
                     Self.shieldUIRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("ShieldiOS")]
        let literal = try NSRegularExpression(pattern: #"L\.(?:t|fill)\("([A-Za-z0-9_.]+)""#)
        let platform = try NSRegularExpression(pattern: #"L\.(?:t|fill)\(L\.platformKey\("([A-Za-z0-9_.]+)""#)
        var keys: Set<String> = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                let range = NSRange(text.startIndex..., in: text)
                for match in literal.matches(in: text, range: range) {
                    if let r = Range(match.range(at: 1), in: text) { keys.insert(String(text[r])) }
                }
                for match in platform.matches(in: text, range: range) {
                    if let r = Range(match.range(at: 1), in: text) {
                        for p in Platform.allCases { keys.insert(L.platformKey(String(text[r]), p)) }
                    }
                }
            }
        }
        XCTAssertGreaterThan(keys.count, 100)
        let offenders = keys.filter { ShieldStrings.contains($0) && ShieldStrings.text($0).contains("**") }.sorted()
        XCTAssertTrue(offenders.isEmpty, "use L.a (or L.plain) for Markdown values: \(offenders)")
    }

    func testDynamicKeysExist() {
        for platform in Platform.allCases {
            XCTAssertTrue(ShieldStrings.contains(L.platformKey("welcome.body", platform)))
        }
        for number in 1...6 { XCTAssertTrue(ShieldStrings.contains("rules.\(number)")) }
        for verdict in Verdict.allCases { XCTAssertTrue(ShieldStrings.contains(verdict.headlineKey)) }
        for caller in CallQuiz.Caller.allCases { XCTAssertTrue(ShieldStrings.contains("scam.call.caller.\(caller.rawValue)")) }
        for want in CallQuiz.Want.allCases { XCTAssertTrue(ShieldStrings.contains("scam.call.want.\(want.rawValue)")) }
        for key in ScamOutcome.limitationKeys(Set(ScamLimitation.allCases)) { XCTAssertTrue(ShieldStrings.contains(key), key) }
        for id in [CheckID.creditFreezeEquifax, .creditFreezeExperian, .creditFreezeTransunion] {
            XCTAssertTrue(ShieldStrings.contains(GuidedStepScreen.openKey(id) ?? "missing"))
        }
    }

    /// Integration item: scam reasons now come from the catalog, with the same text as the rules.
    func testScamReasonsMatchTheCompiledText() {
        for rule in RuleID.allCases {
            XCTAssertTrue(ShieldStrings.contains(rule.reasonKey), rule.rawValue)
            XCTAssertEqual(L.reason(rule), rule.reasonText, rule.rawValue)
        }
        for reason in CallQuiz.Reason.allCases {
            XCTAssertTrue(ShieldStrings.contains(reason.reasonKey), reason.rawValue)
            XCTAssertEqual(L.reason(reason), reason.text, reason.rawValue)
        }
        for caller in CallQuiz.Caller.allCases { XCTAssertEqual(L.label(caller), caller.label) }
        for want in CallQuiz.Want.allCases { XCTAssertEqual(L.label(want), want.label) }
    }

    func testFillAndCheckedLine() {
        XCTAssertEqual(L.fill("step.counter", ["n": "2", "total": "3"]), "Step 2 of 3")
        let now = Date(timeIntervalSince1970: 1_792_660_440)
        XCTAssertTrue(ShieldDates.checkedLine(now, now: now).hasPrefix("Checked today at "))
        XCTAssertEqual(ShieldDates.checkedLine(nil, now: now), "Checking now.")
        XCTAssertTrue(ShieldDates.checkedLine(now.addingTimeInterval(-5 * 86_400), now: now).hasPrefix("Checked "))
    }

    func testVerdictAppearanceIsNeverGreen() {
        XCTAssertEqual(Verdict.danger.appearance, .today)
        XCTAssertEqual(Verdict.beCareful.appearance, .toDo)
        XCTAssertEqual(Verdict.noCommonSignsFound.appearance, .cantCheck, "no signs is grey, never green (§1)")
    }

    /// §11: text ≥ 4.5:1, icons and edges ≥ 3:1, light and dark.
    func testThemeContrast() {
        for (name, fg, bg) in ShieldPalette.textPairs {
            XCTAssertGreaterThanOrEqual(fg.light.contrastRatio(with: bg.light), 4.5, "\(name) light")
            XCTAssertGreaterThanOrEqual(fg.dark.contrastRatio(with: bg.dark), 4.5, "\(name) dark")
        }
        for (name, fg, bg) in ShieldPalette.shapePairs {
            XCTAssertGreaterThanOrEqual(fg.light.contrastRatio(with: bg.light), 3, "\(name) light")
            XCTAssertGreaterThanOrEqual(fg.dark.contrastRatio(with: bg.dark), 3, "\(name) dark")
        }
        for appearance in StatusAppearance.allCases {
            XCTAssertGreaterThanOrEqual(appearance.accent.light.contrastRatio(with: appearance.wash.light), 4.5, "\(appearance)")
            XCTAssertGreaterThanOrEqual(appearance.accent.dark.contrastRatio(with: appearance.wash.dark), 4.5, "\(appearance)")
        }
    }

    func testHollowSymbolsDifferFromFilled() {
        for appearance in StatusAppearance.allCases where appearance != .cantCheck {
            XCTAssertNotEqual(appearance.symbolName, appearance.hollowSymbolName)
            XCTAssertFalse(appearance.hollowSymbolName.hasSuffix(".fill"))
        }
    }
}
