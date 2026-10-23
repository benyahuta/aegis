// link_shortener (weight 2, SPEC §5.3): bit.ly, tinyurl and the like, or an IP-address URL.
//
// Also a destination hidden on purpose when there is no link to read at all: "Scan the QR code
// below to unlock it", "Tap below to restore access", "using the link below". A screenshot of a
// button-based phish OCRs to the button label only, so this is the usual shape there. It counts
// only when the message is about an account, a payment, a delivery or a prize (`LureContext`):
// "Scan the QR code on the table to see the menu" stays quiet. The reason shown, "The link hides
// where it really goes", fits both.

import Foundation

struct LinkShortenerRule: ScamRule {
    let id = RuleID.linkShortener

    static let hiddenDestination = PhraseMatcher([
        #"scan (the |this |our |a )?(attached |following |enclosed )?(qr|q\.r\.|q r) ?code"#,
        #"(qr|q\.r\.) ?code (below|attached|above|in this (email|message|letter))"#,
        #"(tap|click|press|touch|select|use) (the )?(button|link|banner|box) (below|above)"#,
        #"(tap|click|press) (below|above)"#,
        #"(using|via|through|at|with|from) the (link|button) (below|above|provided)"#,
        #"(link|button) (below|above) to (verify|confirm|update|restore|unlock|review|pay|claim|secure|reactivate|sign in|log in|continue)"#,
    ], negatable: true)

    func fires(in context: RuleContext) -> Bool {
        let hasHiddenLink = context.extraction.webLinks.contains { link in
            link.isIPAddress || BrandDomains.isShortener(host: link.host)
        }
        if hasHiddenLink { return true }
        return Self.hiddenDestination.matches(in: context) && LureContext.subjectMatches(context)
    }
}
