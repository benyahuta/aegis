// "Is this a scam?" rules engine (SPEC §5.3, P0).
//
// Pipeline: Normalizer → Extractor (NSDataDetector + host scan) → weighted rules → verdict.
//
// Verdict: any rule with weight 5, or a total ≥ 6 → `.danger`. Total 3–5 → `.beCareful`.
// Otherwise → `.noCommonSignsFound` (grey). There is never a "safe" verdict.
// Reasons shown are the top 3 fired rules by weight, using compiled strings only (C10).
//
// Fail-closed floors (H7, tool-threat-model C3/C4): when the checker could not look at all of
// the message (empty input, cut at 8,000 characters, mostly a script the rules can't read, or a
// screenshot it couldn't read), the result is at least `.beCareful`, never grey.
//
// Storage: none. Input text, OCR text and the verdict live only in memory (§5.3, §12.2).
// Logging: only rule IDs and the verdict (enum raw values), never the text (§5.6).

import Foundation

// MARK: - Rule IDs

/// Stable rule IDs from the §5.3 table. Raw values never change: tests and the reason strings
/// are keyed on them.
public enum RuleID: String, CaseIterable, Sendable, Hashable {
    case brandLinkMismatch = "brand_link_mismatch"
    case lookalikeDomain = "lookalike_domain"
    case asksForCode = "asks_for_code"
    case payUnusual = "pay_unusual"
    case aiInjection = "ai_injection"
    case remoteAccess = "remote_access"
    case pasteTerminal = "paste_terminal"
    case warningWithPhone = "warning_with_phone"
    case newNumberFamily = "new_number_family"
    case tollDeliveryTaxLure = "toll_delivery_tax_lure"
    case linkShortener = "link_shortener"
    case oddTLD = "odd_tld"
    case urgencySecrecy = "urgency_secrecy"
    case romanceInvestment = "romance_investment"

    /// The §5.3 weight.
    public var weight: Int {
        switch self {
        case .brandLinkMismatch, .lookalikeDomain, .asksForCode, .payUnusual, .aiInjection,
             .remoteAccess, .pasteTerminal:
            5
        case .warningWithPhone: 4
        case .newNumberFamily, .tollDeliveryTaxLure, .romanceInvestment: 3
        case .linkShortener, .oddTLD, .urgencySecrecy: 2
        }
    }

    /// The localization key for the plain-language reason ("scam.reason.asks_for_code").
    public var reasonKey: String { "scam.reason.\(rawValue)" }

    /// The compiled English reason (6th–8th grade). Shown on the Result screen (§10.1 screen 10).
    public var reasonText: String {
        switch self {
        case .brandLinkMismatch:
            "It uses a company's name, but the link goes to a different website."
        case .lookalikeDomain:
            "The link is made to look like a real company's website, but it is not."
        case .asksForCode:
            "It asks for a code, PIN or password. Real companies never ask you for these."
        case .payUnusual:
            "It asks you to pay with gift cards, crypto, a wire, or a \"safe account.\" Real companies and agencies never do this."
        case .aiInjection:
            "It has hidden or strange text that tries to fool a scam checker."
        case .remoteAccess:
            "It asks to get into your computer or phone, or to install an app."
        case .pasteTerminal:
            "It tells you to paste or type a command into your computer."
        case .warningWithPhone:
            "It is a warning with a phone number to call. Real warnings never come with a number to call."
        case .newNumberFamily:
            "Someone says they are family writing from a new number."
        case .tollDeliveryTaxLure:
            "It is about a toll, a package, a tax refund, a benefit or a store refund. Scammers often send these."
        case .linkShortener:
            "The link hides where it really goes."
        case .oddTLD:
            "The link ends in a way that scammers often use."
        case .urgencySecrecy:
            "It rushes you, threatens you, or tells you to keep it secret."
        case .romanceInvestment:
            "It promises easy money or an investment, or comes from a new online friend."
        }
    }

    /// The most relevant Family Rule (§7, numbered 1–6) for this reason.
    public var familyRuleNumber: Int {
        switch self {
        case .asksForCode: 2
        case .payUnusual, .romanceInvestment: 3
        case .warningWithPhone: 4
        // "Let us into your computer": check who it really is with a number you find yourself.
        case .remoteAccess: 1
        case .pasteTerminal: 5
        case .newNumberFamily: 6
        case .brandLinkMismatch, .lookalikeDomain, .aiInjection, .tollDeliveryTaxLure, .linkShortener,
             .oddTLD, .urgencySecrecy:
            1
        }
    }

    /// Order in the §5.3 table, used to break ties between rules with the same weight.
    var tableOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Rule protocol

/// Everything a rule may look at. Built once per check.
public struct RuleContext: Sendable {
    public let normalized: NormalizedText
    public let extraction: Extraction
    /// Brands named in the text or inside a link's host.
    public let namedBrands: [Brand]

    public init(normalized: NormalizedText, extraction: Extraction, namedBrands: [Brand]) {
        self.normalized = normalized
        self.extraction = extraction
        self.namedBrands = namedBrands
    }

    public init(text: String) {
        let normalized = Normalizer.normalize(text)
        let extraction = Extractor.extract(from: normalized)
        self.init(
            normalized: normalized,
            extraction: extraction,
            namedBrands: BrandDomains.brandsNamed(in: normalized, links: extraction.links)
        )
    }

    /// The text rules match phrases against: lowercased, look-alike letters folded.
    public var text: String { normalized.folded }
}

/// One weighted rule from the §5.3 table.
public protocol ScamRule: Sendable {
    var id: RuleID { get }
    func fires(in context: RuleContext) -> Bool
}

// MARK: - Result

/// Why a check could not look at the whole message.
public enum ScamLimitation: String, CaseIterable, Sendable, Hashable {
    /// Nothing to check.
    case emptyInput = "empty_input"
    /// Longer than 8,000 characters; only the start was checked.
    case truncated
    /// Mostly letters the English rules can't read.
    case unreadableScript = "unreadable_script"
    /// A screenshot couldn't be read, or had no text.
    case unreadableImage = "unreadable_image"
}

/// The outcome of one check. In memory only; never stored, logged or synced (§12.2).
public struct ScamAssessment: Sendable, Hashable {
    public let verdict: Verdict
    /// Every rule that fired, most important first (weight, then §5.3 table order).
    public let firedRules: [RuleID]
    /// Sum of the fired rules' weights.
    public let score: Int
    public let limitations: Set<ScamLimitation>
    /// True when the message holds something that looks like a one-time code (4–8 digits next to
    /// the word "code", "PIN" or "passcode"). The Result screen then says "If the message has a
    /// code in it, don't send the code." (§10.1 screen 10.)
    public let containsCode: Bool

    public init(verdict: Verdict, firedRules: [RuleID], score: Int, limitations: Set<ScamLimitation>, containsCode: Bool) {
        self.verdict = verdict
        self.firedRules = firedRules
        self.score = score
        self.limitations = limitations
        self.containsCode = containsCode
    }

    /// The reasons to show: the top 3 fired rules by weight (§5.3).
    public var reasons: [RuleID] { Array(firedRules.prefix(ScamRules.maxReasons)) }

    /// The Family Rule (§7, 1–6) to show under the result: the one tied to the top reason, or
    /// rule 1 ("Hang up and look it up") when nothing fired.
    public var familyRuleNumber: Int { firedRules.first?.familyRuleNumber ?? 1 }
}

// MARK: - Engine

public enum ScamRules {
    public static let maxReasons = 3
    /// "Any rule with weight 5 … → danger."
    public static let dangerRuleWeight = 5
    /// "… or a total ≥ 6 → danger."
    public static let dangerScore = 6
    /// "Total 3–5 → beCareful."
    public static let beCarefulScore = 3

    /// Every rule in the §5.3 table, in table order.
    public static let all: [any ScamRule] = [
        BrandLinkMismatchRule(),
        LookalikeDomainRule(),
        AsksForCodeRule(),
        PayUnusualRule(),
        AIInjectionRule(),
        RemoteAccessRule(),
        PasteTerminalRule(),
        WarningWithPhoneRule(),
        NewNumberFamilyRule(),
        TollDeliveryTaxLureRule(),
        LinkShortenerRule(),
        OddTLDRule(),
        UrgencySecrecyRule(),
        RomanceInvestmentRule(),
    ]

    /// Runs the whole pipeline on pasted or OCR'd text.
    public static func assess(_ text: String) -> ScamAssessment {
        let context = RuleContext(text: text)
        return assess(context)
    }

    public static func assess(_ context: RuleContext, extraLimitations: Set<ScamLimitation> = []) -> ScamAssessment {
        var fired: [RuleID] = []
        if !context.normalized.isEmpty {
            for rule in all where rule.fires(in: context) {
                fired.append(rule.id)
            }
        }
        fired.sort { lhs, rhs in
            lhs.weight != rhs.weight ? lhs.weight > rhs.weight : lhs.tableOrder < rhs.tableOrder
        }

        var limitations = extraLimitations
        if context.normalized.isEmpty { limitations.insert(.emptyInput) }
        if context.normalized.wasTruncated { limitations.insert(.truncated) }
        if context.normalized.isMostlyUnreadableScript { limitations.insert(.unreadableScript) }

        let score = fired.reduce(0) { $0 + $1.weight }
        var verdict = verdict(for: fired)
        if !limitations.isEmpty { verdict = max(verdict, .beCareful) }

        let assessment = ScamAssessment(
            verdict: verdict,
            firedRules: fired,
            score: score,
            limitations: limitations,
            containsCode: CodeDetector.containsCode(context.text)
        )
        Log.scam.info(
            "scam.assess verdict=\(verdict.rawValue, privacy: .public) rules=\(fired.map(\.rawValue).joined(separator: ","), privacy: .public)"
        )
        return assessment
    }

    /// The §5.3 scoring on its own: weight-5 rule or total ≥ 6 → danger; 3–5 → be careful.
    public static func verdict(for fired: [RuleID]) -> Verdict {
        let unique = Set(fired)
        let total = unique.reduce(0) { $0 + $1.weight }
        if unique.contains(where: { $0.weight >= dangerRuleWeight }) || total >= dangerScore { return .danger }
        if total >= beCarefulScore { return .beCareful }
        return .noCommonSignsFound
    }
}

/// Finds one-time codes so "Send to Ben" never carries one (§0 H2: Family Shield never handles
/// a 2FA code) and the UI can say the code was left out.
public enum CodeDetector {
    private static let patterns = [
        #"(code|pin|passcode|otp)[^0-9\n]{0,30}\d{4,8}"#,
        #"\d{4,8}[^0-9\n]{0,30}(code|pin|passcode|otp)"#,
        #"g-\d{6}"#,
    ]
    private static let matcher = PhraseMatcher(patterns)

    static func containsCode(_ text: String) -> Bool { matcher.matches(text) }

    /// The same code shapes, found in the person's own text (any case, any digits), so the
    /// digits can be masked where they are.
    private static let rawCode: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(?:"# + patterns.joined(separator: "|") + #")(?![\p{L}\p{N}])"#,
        options: [.caseInsensitive]
    )

    /// `text` with every digit of every one-time code replaced by "•", or nil when a code can
    /// still be read afterwards (written with look-alike digits or hidden characters that only
    /// the normalized reading shows), so the caller leaves the text out entirely.
    public static func redactingCodes(in text: String) -> String? {
        var masked = text
        if let rawCode {
            let ns = text as NSString
            var digits: [NSRange] = []
            for match in rawCode.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var index = match.range.location
                while index < match.range.location + match.range.length {
                    let range = ns.rangeOfComposedCharacterSequence(at: index)
                    if ns.substring(with: range).unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
                        digits.append(range)
                    }
                    index = range.location + range.length
                }
            }
            let result = NSMutableString(string: text)
            for range in digits.reversed() { result.replaceCharacters(in: range, with: "•") }
            masked = result as String
        }
        return containsCode(Normalizer.normalize(masked).folded) ? nil : masked
    }
}

// MARK: - Facade for the app

/// The entry points the "Is this a scam?" screens call. Nothing is stored.
public enum ScamChecker {
    /// Pasted text.
    public static func assess(text: String) -> ScamAssessment {
        ScamRules.assess(text)
    }

    /// A screenshot (PNG/JPEG/HEIC data). OCR runs first (§5.3 step 2). If the image can't be
    /// read or holds no text, the answer is "Be careful", never grey (fail closed).
    public static func assess(imageData: Data) async -> ScamAssessment {
        do {
            let text = try await OCR.recognizeText(in: imageData)
            return assessRecognized(text)
        } catch {
            Log.scam.notice("scam.ocr failed")
            return unreadableImage()
        }
    }

    static func assessRecognized(_ text: String) -> ScamAssessment {
        let context = RuleContext(text: text)
        if context.normalized.isEmpty { return unreadableImage() }
        return ScamRules.assess(context)
    }

    static func unreadableImage() -> ScamAssessment {
        ScamAssessment(verdict: .beCareful, firedRules: [], score: 0, limitations: [.unreadableImage], containsCode: false)
    }
}
