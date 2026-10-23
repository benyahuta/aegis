// lookalike_domain (weight 5, SPEC §5.3): punycode "xn--", mixed script, or a skeleton that
// matches an allowlisted brand domain.
//
// Fires for a link when:
//   - any label is punycode ("xn--pple-43d.com");
//   - the host is written in Unicode and either mixes Latin with Cyrillic/Greek in one label or
//     folds to a brand's name ("аpple.com" with a Cyrillic "а");
//   - it is not a brand host but its name folds to a brand's name ("paypa1.com", "arnazon.com");
//   - a real brand domain is embedded in a fake host ("usps.com.track-pkg.top",
//     "apple.com-verify.icu");
//   - the part before "@" pretends to be the destination ("https://paypal.com@evil.top");
//   - a word in the host is one typo away from a brand name of six letters or more ("amazn-track",
//     "amazom-help", "netfilx"). Only same first letter, so "infinity" is not "xfinity" and
//     "cloud" is not "icloud". A single typo is weak evidence, and ordinary words and surnames
//     sit one letter from many brand names ("carter" and "chapter" from Charter, "discovery" from
//     Discover, "window" from Windows, "trust" from Truist), so it counts only when the message
//     names that same brand, or when the host also looks like a lure ("-help", "-track", an odd
//     TLD) and the brand name is not itself an everyday word. A lure word in the text alone
//     ("invoice", "payment") is not enough: real small businesses write those every day.

import Foundation

struct LookalikeDomainRule: ScamRule {
    let id = RuleID.lookalikeDomain

    func fires(in context: RuleContext) -> Bool {
        let links = context.extraction.links
        if links.contains(where: { Self.isLookalike($0) }) { return true }
        for link in links where link.kind == .web {
            let near = Self.nearMissLabels(link)
            guard !near.isEmpty else { continue }
            // The message names the brand the host imitates ("Your Netflix payment failed:
            // netfilx.com").
            let named = Set(context.namedBrands.flatMap { $0.domains.map(Self.registrableLabel) })
            if near.contains(where: named.contains) { return true }
            if BrandDomains.hostLooksLikeLure(link.host), near.contains(where: { !BrandDomains.everydayWordLabels.contains($0) }) {
                return true
            }
        }
        return false
    }

    static func registrableLabel(_ domain: String) -> String { ExtractedLink(kind: .web, host: domain).registrableLabel }

    /// Brand labels one edit (insert, delete, change or swap two letters) from a word in the
    /// host. Words that are everyday English one letter from a brand ("trust", "goggle") are not
    /// typos (`BrandDomains.nearMissStopWords`).
    static func nearMissLabels(_ link: ExtractedLink) -> [String] {
        if link.isIPAddress || link.hasNonASCII || BrandDomains.isKnownBrandHost(link.host) { return [] }
        let brandLabels = BrandDomains.brandLabelSkeletons.map(\.label).filter { $0.count >= 6 && $0.allSatisfy(\.isLetter) }
        var out: [String] = []
        for word in link.registrableLabel.split(separator: "-").map(String.init)
        where word.count >= 5 && !BrandDomains.nearMissStopWords.contains(word) {
            for label in brandLabels where label != word && label.first == word.first && abs(label.count - word.count) <= 1 {
                if editDistanceIsOne(Array(word), Array(label)) { out.append(label) }
            }
        }
        return out
    }

    /// True when a host word is one typo from a brand label.
    static func isNearMiss(_ link: ExtractedLink) -> Bool { !nearMissLabels(link).isEmpty }

    /// Optimal string alignment distance == 1 (Damerau-Levenshtein with adjacent swaps).
    static func editDistanceIsOne(_ a: [Character], _ b: [Character]) -> Bool {
        if a == b { return false }
        var previous2: [Int] = []
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previous2[j - 2] + 1)
                }
            }
            previous2 = previous
            previous = current
        }
        return previous[b.count] == 1
    }

    static func isLookalike(_ link: ExtractedLink) -> Bool {
        if link.isPunycode || link.hasDeceptiveUserInfo { return true }
        if link.isIPAddress { return false }

        if link.hasNonASCII {
            if link.labels.contains(where: mixesScripts) { return true }
            let folded = BrandDomains.skeleton(link.registrableLabel)
            return BrandDomains.brandLabelSkeletons.contains { $0.skeleton == folded }
        }

        if BrandDomains.isKnownBrandHost(link.host) { return false }

        let label = link.registrableLabel
        let folded = BrandDomains.skeleton(label)
        if BrandDomains.brandLabelSkeletons.contains(where: { $0.skeleton == folded && $0.label != label }) {
            return true
        }

        return embedsBrandDomain(link.host)
    }

    /// True when a real brand domain appears inside a host that does not belong to the brand,
    /// starting at a label boundary and followed by "." or "-".
    static func embedsBrandDomain(_ host: String) -> Bool {
        for domain in BrandDomains.allBrandDomains {
            var searchRange = host.startIndex..<host.endIndex
            while let found = host.range(of: domain, range: searchRange) {
                let startsAtBoundary = found.lowerBound == host.startIndex
                    || [".", "-"].contains(host[host.index(before: found.lowerBound)])
                let next = found.upperBound < host.endIndex ? host[found.upperBound] : nil
                if startsAtBoundary, next == "." || next == "-" { return true }
                searchRange = found.upperBound..<host.endIndex
            }
        }
        return false
    }

    static func mixesScripts(_ label: String) -> Bool {
        var scripts = Set<Normalizer.Script>()
        for scalar in label.unicodeScalars where scalar.properties.isAlphabetic {
            let s = Normalizer.script(of: scalar)
            if s != .other { scripts.insert(s) }
        }
        return scripts.count > 1
    }
}
