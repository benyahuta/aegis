// Shared lexicon: does the message try to get the reader to act on an account, a payment, a
// delivery or a prize? Not a rule of its own (it has no weight). It keeps link rules from firing
// on links that are only shared for information: "Apple announced new iPhones, read it on
// theverge.com" names a brand next to another site, but asks nothing of the reader.
//
// Two kinds of words:
//   - asks to act ("verify", "suspended", "refund", "on hold", "click here", "update your"):
//     count anywhere in the message;
//   - everyday nouns a relative writes about too ("order", "paid", "bill", "delivered",
//     "account"): count for a link only in the same sentence as the link, or when the brand
//     opens the message as its sender ("Amazon: your order …"). "Dad, your Amazon order
//     arrived. Recipe here: allrecipes.com/…" shares a recipe; it does not ask anything.

import Foundation

enum LureContext {
    /// Words that ask the reader to act on an account, a payment, a delivery or a prize.
    static let asksToAct = PhraseMatcher([
        #"(verify|verification|password|passcode|log ?in|sign ?in|sign-in|login|credentials)"#,
        #"(refund|refunds|claim|reward|rewards|prize|winner|won|congratulations)"#,
        #"(unlock|restore|reactivate|deactivated?|suspend|suspended|suspension|locked|limited|restricted|disabled|frozen|expired?|expires|expiring)"#,
        #"(secure|security|alert|alerts|warning|fraud|fraudulent|unusual|suspicious|unauthori[sz]ed)"#,
        #"(redelivery|customs|toll|tolls|fee|fees|penalty|charged|card number|gift ?cards?|wallet|crypto|bitcoin)"#,
        #"(urgent|urgently|immediately|on hold|is held|was held|being held|held at|held for)"#,
        #"(confirm|update) (your|the|my|this) "#, #"(to|please) (confirm|update)"#, #"update (now|required|needed)"#,
        #"(update|confirm|verify|pay|resolve|reschedule|settle) (here|now|at|via|online|below|today)"#,
        // "schedule" is also a noun ("the weekly schedule at ourtownlibrary.org"): only "schedule now/here".
        #"schedule (here|now|via|online|below|today)"#, #"reschedule\s*:"#,
        #"(cancel|dispute|stop|refund) (here|now|at|via|online|today|it|this|the (charge|payment|renewal|subscription|order|transaction))"#,
        #"(renewed|auto-?renewed|charged|billed|debited|deducted) (for |of |at |with )?\$\d"#,
        #"(restore|regain) access"#, #"track (your|the|my) (package|order|shipment|parcel|delivery)"#,
        #"(could not|couldn't|unable to|failed to|cannot|can't|was not|wasn't) (be )?(deliver|delivered|complete|completed|process|processed)"#,
        #"(payment|delivery|order|shipment|package|transaction|card) (failed|declined|unsuccessful|pending|issue|problem|error|was declined|has failed|could not)"#,
    ])

    /// Everyday words about an account, a payment or a delivery.
    static let everyday = PhraseMatcher([
        #"(accounts?|payment|payments|pay|paid|billing|bill|bills|invoice|transaction|transactions|purchase|order|orders|bank|banking|credit card|debit card)"#,
        #"(delivery|deliver|delivered|package|parcel|shipment|shipping|subscription|membership|renewal|renew)"#,
    ])

    /// What the message is about, either kind (for rules that do not depend on one link).
    static func subjectMatches(_ context: RuleContext) -> Bool {
        asksToAct.matches(in: context) || everyday.matches(in: context)
    }

    /// A push to follow a link.
    static let callToAction = PhraseMatcher([
        #"(click|tap|press) (here|below|the link|this link|the button|on the link)"#, #"(link|button) below"#,
    ])

    /// True when the message tries to get the reader to act on an account, a payment, a delivery
    /// or a prize, or pushes them to follow a link.
    static func matches(_ context: RuleContext) -> Bool {
        subjectMatches(context) || callToAction.matches(in: context)
    }

    /// `matches`, link by link: everyday words count only next to the link or under a brand
    /// sender line. Built once per check; call it for each link.
    static func forLinks(_ context: RuleContext) -> (ExtractedLink) -> Bool {
        if asksToAct.matches(in: context) || callToAction.matches(in: context) { return { _ in true } }
        guard everyday.matches(in: context) else { return { _ in false } }
        if brandIsSender(context) { return { _ in true } }
        let lowercased = context.normalized.lowercased
        return { link in
            // A host written in a way the text search can't find (defanged, look-alike letters):
            // count the words anywhere, as before.
            guard let sentence = sentence(containing: link.host, in: lowercased) else { return true }
            return everyday.matches(sentence)
        }
    }

    /// The message opens with a sender label that names a brand ("Amazon:", "USPS Notice:",
    /// "Wells Fargo -").
    static func brandIsSender(_ context: RuleContext) -> Bool {
        guard !context.namedBrands.isEmpty else { return false }
        let text = context.normalized.text
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let separators = [": ", " - ", ":\n"]
        guard let cut = separators.compactMap({ firstLine.range(of: $0)?.lowerBound }).min() else {
            return firstLine.hasSuffix(":") && labelNamesBrand(String(firstLine.dropLast()))
        }
        return labelNamesBrand(String(firstLine[..<cut]))
    }

    private static func labelNamesBrand(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        // A sender label is a short name, not a sentence ("Dad, your Amazon order arrived").
        guard !trimmed.isEmpty, trimmed.count <= 40,
              trimmed.split(separator: " ").count <= 6,
              !trimmed.contains(where: { ",.!?".contains($0) })
        else { return false }
        return !BrandDomains.brandsNamedInText(Normalizer.normalize(trimmed + ":")).isEmpty
    }

    /// The sentence of `text` that holds `needle`, or nil when it is not there. A sentence ends
    /// at a line break, "!" or "?", or a "." followed by a space (not the dots inside a host).
    static func sentence(containing needle: String, in text: String) -> String? {
        guard !needle.isEmpty, let found = text.range(of: needle) else { return nil }
        func isEnd(_ index: String.Index) -> Bool {
            let ch = text[index]
            if ch == "\n" || ch == "!" || ch == "?" { return true }
            if ch == "." {
                let next = text.index(after: index)
                return next == text.endIndex || text[next].isWhitespace
            }
            return false
        }
        var start = found.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            if isEnd(previous) { break }
            start = previous
        }
        var end = found.upperBound
        while end < text.endIndex, !isEnd(end) { end = text.index(after: end) }
        return String(text[start..<end])
    }
}
