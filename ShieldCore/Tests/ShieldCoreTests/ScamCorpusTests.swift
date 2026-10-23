import XCTest
@testable import ShieldCore

/// SPEC §13.1 `ScamCorpusTests`:
///   - ≥ 80 scam cases (this corpus has more) → `danger` or `beCareful`, with ≥ 90% `danger` on
///     the clear ones;
///   - ≥ 40 benign cases → not `danger` in ≥ 95%.
/// The rules are tuned on general patterns, never on corpus strings.
final class ScamCorpusTests: XCTestCase {
    struct ScamCase: Decodable {
        let id: String
        let category: String
        let clear: Bool
        let text: String
    }

    struct BenignCase: Decodable {
        let id: String
        let category: String
        let text: String
    }

    static func load<T: Decodable>(_ name: String, as: T.Type) throws -> [T] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"),
            "missing fixture \(name).jsonl"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            try decoder.decode(T.self, from: Data($0.utf8))
        }
    }

    var scams: [ScamCase] = []
    var benign: [BenignCase] = []

    override func setUpWithError() throws {
        scams = try Self.load("scam_corpus", as: ScamCase.self)
        benign = try Self.load("benign_corpus", as: BenignCase.self)
    }

    // MARK: - Corpus shape

    func testCorpusSizes() {
        XCTAssertGreaterThanOrEqual(scams.count, 90)
        XCTAssertGreaterThanOrEqual(benign.count, 50)
        XCTAssertGreaterThanOrEqual(scams.filter { $0.category == "ai_injection" }.count, 10)
        XCTAssertEqual(Set(scams.map(\.id)).count, scams.count, "duplicate scam ids")
        XCTAssertEqual(Set(benign.map(\.id)).count, benign.count, "duplicate benign ids")
    }

    func testCorpusCoversRequiredLures() {
        let categories = Set(scams.map(\.category))
        let required = [
            "toll", "delivery", "irs", "medi_cal", "ahold_refund", "apple_support", "hi_mom", "romance",
            "investment", "tech_support", "clickfix", "gift_card", "zelle_safe_account", "punycode",
            "brand_link_mismatch", "zero_width", "bidi", "ai_injection",
        ]
        for category in required {
            XCTAssertTrue(categories.contains(category), "corpus is missing \(category)")
        }
        let benignCategories = Set(benign.map(\.category))
        for category in ["bank_2fa", "apple_genuine", "google_genuine", "appointment", "family_chat", "delivery_genuine"] {
            XCTAssertTrue(benignCategories.contains(category), "benign corpus is missing \(category)")
        }
    }

    // MARK: - §13.1 thresholds

    func testEveryScamIsAtLeastBeCareful() {
        var misses: [String] = []
        for item in scams {
            let result = ScamRules.assess(item.text)
            if result.verdict == .noCommonSignsFound { misses.append(Self.describe(item.id, result)) }
        }
        XCTAssertTrue(misses.isEmpty, "scams graded grey:\n" + misses.joined(separator: "\n"))
    }

    func testClearScamsAreDangerAtLeast90Percent() {
        let clear = scams.filter(\.clear)
        var notDanger: [String] = []
        for item in clear {
            let result = ScamRules.assess(item.text)
            if result.verdict != .danger { notDanger.append(Self.describe(item.id, result)) }
        }
        let rate = Double(clear.count - notDanger.count) / Double(clear.count)
        print("ScamCorpus: clear-scam danger rate \(String(format: "%.1f", rate * 100))% (\(clear.count - notDanger.count)/\(clear.count))")
        if !notDanger.isEmpty { print("ScamCorpus: clear scams not graded danger:\n" + notDanger.joined(separator: "\n")) }
        XCTAssertGreaterThanOrEqual(rate, 0.90, notDanger.joined(separator: "\n"))
    }

    func testBenignNotDangerAtLeast95Percent() {
        var danger: [String] = []
        var careful: [String] = []
        for item in benign {
            let result = ScamRules.assess(item.text)
            switch result.verdict {
            case .danger: danger.append(Self.describe(item.id, result))
            case .beCareful: careful.append(Self.describe(item.id, result))
            case .noCommonSignsFound: break
            }
        }
        let rate = Double(benign.count - danger.count) / Double(benign.count)
        print("ScamCorpus: benign not-danger rate \(String(format: "%.1f", rate * 100))% (\(benign.count - danger.count)/\(benign.count))")
        if !danger.isEmpty { print("ScamCorpus: benign graded danger:\n" + danger.joined(separator: "\n")) }
        if !careful.isEmpty { print("ScamCorpus: benign graded be careful:\n" + careful.joined(separator: "\n")) }
        XCTAssertGreaterThanOrEqual(rate, 0.95, danger.joined(separator: "\n"))
    }

    /// Injection attempts are themselves a scam signal (tool-threat-model C6): every one must fire
    /// `ai_injection` and so be `danger`. The rules can never be talked down.
    func testEveryInjectionAttemptFiresAIInjection() {
        for item in scams where ["ai_injection", "zero_width", "bidi"].contains(item.category) {
            let result = ScamRules.assess(item.text)
            XCTAssertTrue(result.firedRules.contains(.aiInjection), Self.describe(item.id, result))
            XCTAssertEqual(result.verdict, .danger, Self.describe(item.id, result))
        }
    }

    func testEveryResultShowsAtMostThreeCompiledReasons() {
        for item in scams {
            let result = ScamRules.assess(item.text)
            XCTAssertLessThanOrEqual(result.reasons.count, 3)
            XCTAssertEqual(result.reasons, Array(result.firedRules.prefix(3)))
            for reason in result.reasons { XCTAssertFalse(reason.reasonText.isEmpty) }
        }
    }

    static func describe(_ id: String, _ result: ScamAssessment) -> String {
        "  \(id): \(result.verdict.rawValue) score=\(result.score) rules=\(result.firedRules.map(\.rawValue))"
    }
}
