// Shared phrase matching for the scam rules.
//
// Patterns are ICU regex alternatives matched against `NormalizedText.folded` (lowercased) and
// its second "leet" reading (`leetFolded`, "g1ft c4rds" → "gift cards"); see `matches(in:)`.
// Each alternative is wrapped in letter/digit boundaries, so "ups" never matches inside "groups".
// A phrase that starts or ends with punctuation ("applescript://", "<|system|>") needs no boundary
// on that side.
//
// Negation: real banks and Apple write "Never share this code" and "We will never ask you to
// send money to yourself". A `negatable` phrase does not count when a negation word comes before
// it in the same clause. A clause ends at . ! ? ; : , a line break, or "and" / "but" / "then" / "so".
// A negation that belongs to a pushy idiom ("don't hesitate to", "don't forget to", "I will not
// hang up") does not negate what follows: "Don't hesitate to read me the code" is a request.

import Foundation

struct PhraseMatcher: @unchecked Sendable {
    // NSRegularExpression is immutable and documented as thread-safe.
    /// One regex per alternative. ICU runs a single alternation of dozens of phrases at every
    /// position of the text and loses its literal-prefix shortcuts, which made one rule take
    /// seconds on an 8,000-character paste; separate regexes cost the sum of their parts.
    private let regexes: [NSRegularExpression]
    let negatable: Bool

    init(_ alternatives: [String], negatable: Bool = false) {
        // Word boundaries only where the phrase itself starts or ends with a letter or digit, so
        // "applescript://…" and "[INST]" still match next to other text.
        regexes = alternatives.map { alternative in
            let pattern = #"(?:(?<![\p{L}\p{N}])|(?![\p{L}\p{N}]))(?:"# + alternative + #")(?:(?<![\p{L}\p{N}])|(?![\p{L}\p{N}]))"#
            do {
                return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            } catch {
                // A bad pattern is a programming error caught by ScamRulesTests.testAllPatternsCompile.
                preconditionFailure("Invalid scam rule pattern: \(error)")
            }
        }
        self.negatable = negatable
    }

    /// True when the phrase counts in either reading of the message (`folded` or `leetFolded`).
    func matches(in context: RuleContext) -> Bool {
        let normalized = context.normalized
        if matches(normalized.folded) { return true }
        return normalized.leetFolded != normalized.folded && matches(normalized.leetFolded)
    }

    /// True when at least one match counts (is not negated, for a negatable phrase). After a
    /// negated match the search restarts one character later, so an overlapping phrase that is
    /// not negated ("call … immediately" negated, "immediately" alone not) still counts.
    func matches(_ text: String) -> Bool {
        // Non-ASCII text gets one UTF-16 copy shared by all the regexes; a native Swift string
        // would be transcoded again on every call. ASCII text bridges for free.
        let ns = text.utf8.count == text.utf16.count ? text as NSString : NSString(string: text)
        let utf16 = ns as String
        for regex in regexes {
            var start = 0
            while start < ns.length,
                  let match = regex.firstMatch(in: utf16, range: NSRange(location: start, length: ns.length - start))
            {
                if !negatable || !Self.isNegated(ns, at: match.range.location) { return true }
                start = match.range.location + 1
            }
        }
        return false
    }

    // MARK: - Negation

    private static let negation: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?<![\p{L}])(never|not|don't|dont|do not|doesn't|does not|won't|will not|wouldn't|would not|no one|nobody|cannot|can't|nor|isn't|is not|aren't|are not|neither)(?![\p{L}])"#,
            options: [.caseInsensitive]
        )
    }()

    private static let clauseBreakWords: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?<![\p{L}])(and|but|then|so|instead|just|only|except)(?![\p{L}])"#, options: [.caseInsensitive])
    }()

    static let negationWindowWords = 5

    /// Negations that belong to an idiom urging the reader on, not to the phrase after them.
    private static let pushyIdiom: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?<![\p{L}])(never|not|don't|dont|do not|won't|will not|cannot|can't|please don't)( ever)? (hesitate|forget|delay|wait|hang up|disconnect|ignore|miss|fail|waste (any )?time|put (this|it) off|let (this|it) (slide|go|wait))(?![\p{L}])"#,
            options: [.caseInsensitive]
        )
    }()

    static func isNegated(_ text: NSString, at location: Int) -> Bool {
        // Walk back to the start of the clause (at most 100 UTF-16 units).
        let floor = max(0, location - 100)
        var start = floor
        var index = location - 1
        while index >= floor {
            let unit = text.character(at: index)
            if let scalar = Unicode.Scalar(unit), ".!?;:,\n()".unicodeScalars.contains(scalar) {
                start = index + 1
                break
            }
            index -= 1
        }
        guard start < location else { return false }
        let clause = text.substring(with: NSRange(location: start, length: location - start))
        if reportedSpeech.firstMatch(in: clause, range: NSRange(location: 0, length: (clause as NSString).length)) != nil {
            return true
        }
        // "Scammers will call you. They ask you to pay with gift cards": "they" after scammers.
        if theyDo.firstMatch(in: clause, range: NSRange(location: 0, length: (clause as NSString).length)) != nil {
            let before = text.substring(to: start)
            if scamWord.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil { return true }
        }
        var prefix = clause as NSString

        // Cut at the last clause-joining word ("Don't hang up and read me the code").
        let breaks = clauseBreakWords.matches(in: prefix as String, range: NSRange(location: 0, length: prefix.length))
        if let last = breaks.last {
            let cut = last.range.location + last.range.length
            prefix = prefix.substring(from: cut) as NSString
        }
        // A negation reaches at most `negationWindowWords` words ahead: "We will never ask you to
        // verify your account" is negated, but in "If you did not make this payment call 1-800…
        // immediately" the "not" belongs to "make", not to "immediately".
        let words = (prefix as String).split(whereSeparator: { $0.isWhitespace })
        if words.count > negationWindowWords {
            prefix = words.suffix(negationWindowWords).joined(separator: " ") as NSString
        }
        // Blank out pushy idioms ("don't hesitate", "do not forget") before looking for a negation.
        let scope = pushyIdiom.stringByReplacingMatches(
            in: prefix as String, range: NSRange(location: 0, length: prefix.length), withTemplate: " "
        )
        return negation.firstMatch(in: scope, range: NSRange(location: 0, length: (scope as NSString).length)) != nil
    }

    private static let theyDo: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?<![\p{L}])they (often |usually |may |might |will |can |could |sometimes |always |typically |also |then |even )*(ask|tell|want|demand|pretend|say|insist|push|try|request|instruct|claim)"#,
            options: [.caseInsensitive]
        )
    }()

    private static let scamWord: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?<![\p{L}])(scam|scams|scammers?|fraudsters?|con artists?|crooks|imposters?|impostors?)(?![\p{L}])"#,
            options: [.caseInsensitive]
        )
    }()

    /// Advice about scams quotes them: "If anyone ever asks you to pay with gift cards, call me",
    /// "Scammers often ask people to pay with gift cards. Real agencies never do."
    private static let reportedSpeech: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?<![\p{L}])((if|when|whenever) (anyone|anybody|someone|somebody|anything|a (caller|stranger|message|website|site|text|email|company|person|pop-?up)) (ever )?(says|tells|asks|wants|calls|texts|emails)|(scammers?|a scammer|the scammers?|fraudsters?|crooks|con artists?|criminals|thieves|imposters?|impostors?|fake (callers|agents)) (often |usually |may |might |will |can |could |sometimes |always |typically |commonly |also |then |even |now )*(ask|asks|tell|tells|want|wants|demand|demands|pretend|pretends|say|says|insist|insists|push|pushes|try|tries|request|requests|instruct|instructs|claim|claims|use|uses|call|calls|text|texts|get|gets|trick|tricks|pose|poses))"#,
            options: [.caseInsensitive]
        )
    }()
}
