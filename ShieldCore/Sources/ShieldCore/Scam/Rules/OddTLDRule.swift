// odd_tld (weight 2, SPEC §5.3): a link or sender address ending in .top .xyz .click .icu .cyou
// .buzz .sbs .rest and the other endings in `BrandDomains.oddTLDs`.

import Foundation

struct OddTLDRule: ScamRule {
    let id = RuleID.oddTLD

    func fires(in context: RuleContext) -> Bool {
        context.extraction.links.contains { BrandDomains.oddTLDs.contains($0.tld) }
    }
}
