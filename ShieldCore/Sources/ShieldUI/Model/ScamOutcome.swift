// The result of one scam check (SPEC §5.3, §10.1 screen 10). In memory only, for the life of the
// scam screens: never stored, logged or synced (§5.3 "Storage: none", §12.2).

import Foundation
import ShieldCore

public struct ScamOutcome: Sendable, Hashable {
    public enum Origin: String, Sendable, Hashable {
        case message
        case screenshot
        case call
    }

    public var origin: Origin
    public var verdict: Verdict
    /// Up to 3 compiled reasons, most important first.
    public var reasons: [String]
    /// The Family Rule (1–6) to show.
    public var familyRuleNumber: Int
    /// Why the checker couldn't see everything (compiled strings).
    public var limitations: [String]
    /// The message looked like it holds a one-time code.
    public var containsCode: Bool
    /// Text for "Send to Ben" (the person shares it themselves through the share sheet). Never
    /// holds a one-time code: codes in the pasted text are masked, or the text is left out.
    public var shareText: String
    /// A code was found in the pasted text and kept out of `shareText`.
    public var codeLeftOut: Bool = false
    /// A code was read in the screenshot, so the picture is not attached to "Send to Ben" (H2).
    public var screenshotLeftOut: Bool = false
    /// The screenshot, for "Send to Ben". nil when it holds a one-time code.
    public var screenshot: Data?

    public var headline: String { L.t(verdict.headlineKey) }

    public init(origin: Origin, verdict: Verdict, reasons: [String], familyRuleNumber: Int,
                limitations: [String], containsCode: Bool, shareText: String, screenshot: Data? = nil) {
        self.origin = origin
        self.verdict = verdict
        self.reasons = reasons
        self.familyRuleNumber = familyRuleNumber
        self.limitations = limitations
        self.containsCode = containsCode
        self.shareText = shareText
        self.screenshot = screenshot
    }

    /// From the rules engine (pasted text or a screenshot).
    public init(assessment: ScamAssessment, origin: Origin, originalText: String?, screenshot: Data? = nil) {
        let verdictText = L.t(assessment.verdict.headlineKey)
        // §0 H2: a picture can't be masked, so a screenshot with a code in it is never attached;
        // the share says the picture was left out and asks Ben to call.
        let screenshotLeftOut = origin == .screenshot && assessment.containsCode
        let shareKey = screenshotLeftOut ? "scam.share.screenshotLeftOut"
            : origin == .screenshot ? "scam.share.screenshot" : "scam.share.message"
        var share = L.fill(shareKey, ["verdict": verdictText])
        var codeLeftOut = false
        if let originalText, !originalText.isEmpty {
            if assessment.containsCode {
                // §0 H2: the share draft never carries a one-time code. Mask its digits; if a
                // code would still be readable, send the verdict line alone.
                codeLeftOut = true
                if let masked = CodeDetector.redactingCodes(in: originalText) {
                    share += "\n\n" + masked
                }
            } else {
                share += "\n\n" + originalText
            }
        }
        self.init(
            origin: origin,
            verdict: assessment.verdict,
            reasons: assessment.reasons.map(L.reason),
            familyRuleNumber: assessment.familyRuleNumber,
            limitations: ScamOutcome.limitationKeys(assessment.limitations).map(L.t),
            containsCode: assessment.containsCode,
            shareText: share,
            screenshot: screenshotLeftOut ? nil : screenshot
        )
        self.codeLeftOut = codeLeftOut
        self.screenshotLeftOut = screenshotLeftOut
    }

    /// From the call quiz (never grey, §5.3).
    public init(call result: CallQuiz.Result) {
        let verdictText = L.t(result.verdict.headlineKey)
        self.init(
            origin: .call,
            verdict: result.verdict,
            reasons: result.reasons.prefix(3).map(L.reason),
            familyRuleNumber: result.familyRuleNumber,
            limitations: [],
            containsCode: false,
            shareText: L.fill("scam.share.call", ["verdict": verdictText])
        )
    }

    static func limitationKeys(_ limits: Set<ScamLimitation>) -> [String] {
        ScamLimitation.allCases.filter(limits.contains).map { limit in
            switch limit {
            case .emptyInput: "scam.result.limit.empty"
            case .truncated: "scam.result.limit.truncated"
            case .unreadableScript: "scam.result.limit.unreadableScript"
            case .unreadableImage: "scam.result.limit.unreadableImage"
            }
        }
    }
}
