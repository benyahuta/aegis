// brand_link_mismatch (weight 5, SPEC §5.3): a brand is named (Apple, USPS, IRS, Amazon, PayPal,
// banks, Medi-Cal, E-ZPass/FasTrak, carriers, …) and a link goes to a domain that is not on that
// brand's allowlist (BrandDomains.swift).
//
// A brand counts as named when the text says it or when a link's host carries its name
// ("usps-redelivery.top"). A link is fine when it is allowed for ANY named brand (an Amazon
// message with a real ups.com tracking link names UPS through the host and passes), or when it
// goes to a large neutral site (news, YouTube, Wikipedia, tax filing).
//
// A link on a user-content host (Google Sites and Forms, Dropbox, OneDrive, site builders) does
// not name its owner, so "Chase: restore access at sites.google.com/view/chase-login" is checked
// against Chase's allowlist, where google.com is not (SPEC §5.3: the named brand's allowlist).
//
// A plain mention is not impersonation: a brand name next to a link to another ordinary site
// fires only when the message tries to get the reader to act (`LureContext`: an account, a
// payment, a delivery, a prize, tied to that link), or the host itself looks like a lure
// ("-secure", "-billing", an odd TLD) or names a brand. "Apple announced new iPhones, read it on
// theverge.com" and "Dad, your Amazon order arrived. Recipe here: allrecipes.com/…" stay quiet.
//
// Email addresses count only when they look like a company desk ("support@", "billing@",
// "apple-help@…"), so a relative's own address next to the word "Apple" does not fire.

import Foundation

struct BrandLinkMismatchRule: ScamRule {
    let id = RuleID.brandLinkMismatch

    static let roleWords = [
        "support", "help", "service", "billing", "security", "account", "team", "noreply", "no-reply",
        "admin", "verify", "verification", "care", "desk", "refund", "claims", "alert", "notice",
        "customer", "dept", "department", "fraud", "official", "resolution", "center", "office",
    ]

    func fires(in context: RuleContext) -> Bool {
        let brands = context.namedBrands
        guard !brands.isEmpty else { return false }
        let lure = LureContext.forLinks(context)
        for link in context.extraction.links {
            // A company desk at a free mail provider ("apple.support@gmail.com") is impersonation,
            // even though the provider itself (Google) is then "named" by the address.
            // A club's "office@gmail.com" with no other brand named does not count.
            if link.kind == .email, BrandDomains.isFreeMail(host: link.host),
               brands.contains(where: { !$0.allows(host: link.host) }),
               Self.looksLikeCompanyDesk(link, brands: brands)
            {
                return true
            }
            if BrandDomains.isAllowed(host: link.host, forAnyOf: brands) { continue }
            if BrandDomains.isNeutral(host: link.host) { continue }
            switch link.kind {
            case .web:
                if lure(link) { return true }
                if BrandDomains.isUserContent(host: link.host) { continue }
                if link.isIPAddress || BrandDomains.isShortener(host: link.host) { return true }
                if BrandDomains.hostLooksLikeLure(link.host) { return true }
                if BrandDomains.brands.contains(where: { BrandDomains.hostNames($0, host: link.host) }) { return true }
            case .email:
                if Self.looksLikeCompanyDesk(link, brands: brands) { return true }
            }
        }
        return false
    }

    static func looksLikeCompanyDesk(_ link: ExtractedLink, brands: [Brand]) -> Bool {
        let local = link.emailLocalPart
        if roleWords.contains(where: { local.contains($0) }) { return true }
        // "appleid.verify@gmail.com": the brand name in the address itself.
        let probe = ExtractedLink(kind: .web, host: local.replacingOccurrences(of: "_", with: "-") + ".x")
        return brands.contains { BrandDomains.hostNames($0, host: probe.host) }
    }
}
