// Brand allowlist for `brand_link_mismatch` and `lookalike_domain` (SPEC §5.3).
//
// Each brand has the names scammers use in messages and the domains the real company sends
// links from. A host is allowed for a brand when it equals one of the brand's domains or is a
// subdomain of one ("tools.usps.com" is allowed for USPS; "usps.com.track-pkg.top" is not).
// Government brands also accept any ".gov" host, since only US government bodies can register
// one and state agencies use many different .gov names.
//
// This list is compiled into the app (H6). Nothing here is downloaded.

import Foundation

public struct Brand: Sendable, Hashable, Identifiable {
    /// Stable ID, e.g. "usps". Never shown to anyone and never synced.
    public let id: String
    /// Domains the real brand uses, lowercase ASCII, no "www.".
    public let domains: [String]
    /// True for US government agencies: any ".gov" or ".mil" host is also allowed.
    public let isGovernment: Bool
    /// Regex alternatives matched (case-insensitive) against the folded, lowercased message.
    let patterns: [String]
    /// Regex alternatives matched case-sensitively against the normalized text, for brand names
    /// that are also everyday words ("UPS" vs "ups and downs", "Chase" vs "chase the dog").
    let caseSensitivePatterns: [String]
    /// Whole host tokens (split on "." and "-") that name the brand: "usps" in "usps-help.top".
    let hostTokens: [String]
    /// Substrings that name the brand anywhere in a host label with hyphens removed:
    /// "paypal" in "securepaypal-login.com". Only long, distinctive tokens go here.
    let hostSubstrings: [String]
    /// Host tokens that are also everyday words or names ("ups" in "sign-ups.com", "courts" in
    /// "tennis-courts.com", "apple" in "apple-valley-dental.com"). They name the brand only in a
    /// host that also looks like a lure ("ups-redelivery.com", "chase-secure.pics"): a lure word
    /// in the host, or an odd TLD.
    let wordTokens: Set<String>
    /// Substrings like `hostSubstrings` that are also part of other organizations' names
    /// ("norton" in nortonhealthcare.org, "medicare" in aetnamedicare.com, "dmv" in dmvsmiles.com,
    /// a dental office in the DC-Maryland-Virginia "DMV"). They name the brand only in a host that
    /// also looks like a lure ("nortonrenewal-billing.com", "dmv-renewal.top").
    let lureSubstrings: [String]

    init(
        id: String,
        domains: [String],
        government: Bool = false,
        patterns: [String],
        caseSensitive: [String] = [],
        hostTokens: [String] = [],
        hostSubstrings: [String] = [],
        wordTokens: [String] = [],
        lureSubstrings: [String] = []
    ) {
        self.id = id
        self.domains = domains
        self.isGovernment = government
        self.patterns = patterns
        self.caseSensitivePatterns = caseSensitive
        self.hostTokens = hostTokens
        self.hostSubstrings = hostSubstrings
        self.wordTokens = Set(wordTokens)
        self.lureSubstrings = lureSubstrings
    }

    /// True when `host` belongs to this brand.
    public func allows(host rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        if isGovernment, host.hasSuffix(".gov") || host.hasSuffix(".mil") || host == "gov" { return true }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

public enum BrandDomains {
    // MARK: - Link lists used by other rules

    /// `odd_tld` (§5.3): ".top .xyz .click .icu .cyou .buzz .sbs .rest", plus other endings that
    /// abuse trackers (Spamhaus, Interisle) report as mostly used for phishing and smishing.
    public static let oddTLDs: Set<String> = [
        "top", "xyz", "click", "icu", "cyou", "buzz", "sbs", "rest",
        "cfd", "bond", "qpon", "lol", "mom", "vip", "win", "cam", "monster", "quest", "work",
        "zip", "mov", "country", "kim", "men", "loan", "date", "racing", "review", "stream",
        "download", "gdn", "bid", "accountant", "science", "party", "faith", "cricket", "xin",
        "tk", "ml", "ga", "cf", "gq", "pw", "su",
        "online", "site", "live", "life",
        // Spamhaus and Interisle's most-abused list for 2024–26 smishing.
        "homes", "autos", "boats", "yachts", "hair", "skin", "makeup", "beauty", "motorcycles", "pics",
        "lat",
    ]
    // .shop, .store, .info, .help and .support are left out: real small businesses use them too much.
    // Country codes (.ru, .cn) are left out: they are not "odd" for relatives who live there.

    /// `link_shortener` (§5.3). Brand-owned shorteners (amzn.to, apple.co, aka.ms, g.co) are not
    /// here; they are on their brand's allowlist instead.
    public static let shorteners: Set<String> = [
        "bit.ly", "bitly.com", "bit.do", "tinyurl.com", "tiny.cc", "t.co", "goo.gl", "ow.ly", "is.gd",
        "v.gd", "buff.ly", "rebrand.ly", "cutt.ly", "shorturl.at", "shorturl.com", "rb.gy", "t.ly",
        "s.id", "bl.ink", "short.io", "shorte.st", "adf.ly", "tr.im", "x.co", "soo.gd", "u.to",
        "clck.ru", "qrco.de", "2u.pw", "lnkd.in", "trib.al", "urlz.fr", "shrtco.de", "rotf.lol",
        "t2m.io", "smarturl.it", "ssur.cc", "is.am", "linktr.ee", "tiny.one", "surl.li", "l.ead.me",
        "lc.cx", "inx.lv", "gg.gg", "1url.com", "han.gl", "me2.do", "mcaf.ee",
    ]

    /// Hosts that can be linked next to a brand name without being impersonation: large media,
    /// reference and tax-filing sites that do not host sign-in pages for the brands below.
    public static let neutralDomains: [String] = [
        "youtube.com", "youtu.be", "wikipedia.org", "nytimes.com", "washingtonpost.com", "cnn.com",
        "nbcnews.com", "apnews.com", "reuters.com", "npr.org", "bbc.com", "bbc.co.uk", "latimes.com",
        "consumerreports.org", "aarp.org", "ftc.gov", "consumer.ftc.gov", "reportfraud.ftc.gov",
        "forbes.com", "cbsnews.com", "abcnews.go.com", "foxnews.com", "cnbc.com", "bloomberg.com",
        "usatoday.com", "wsj.com", "theguardian.com", "time.com", "theverge.com", "techcrunch.com",
        "wired.com", "engadget.com", "macrumors.com", "9to5mac.com", "arstechnica.com", "weather.com",
        "accuweather.com", "espn.com", "imdb.com", "snopes.com", "nerdwallet.com", "kiplinger.com",
        "investopedia.com", "turbotax.com", "intuit.com", "hrblock.com", "taxact.com", "freetaxusa.com",
    ]

    /// Hosts where anyone can publish a page, form or file under the owner's real domain (Google
    /// Sites and Forms, Dropbox and OneDrive shares, site builders). A link there is not the
    /// owner's own message: it does not make the owner a "named" brand, and it is allowed only for
    /// a brand the text itself names that owns the host. Matched as the host or a parent domain.
    public static let userContentDomains: [String] = [
        "sites.google.com", "docs.google.com", "drive.google.com", "forms.gle", "script.google.com",
        "storage.googleapis.com", "firebasestorage.googleapis.com", "googleusercontent.com",
        "forms.office.com", "forms.microsoft.com", "sway.office.com", "sharepoint.com",
        "onedrive.live.com", "1drv.ms", "dropbox.com", "dropboxusercontent.com", "db.tt", "box.com",
        "notion.site", "canva.site", "github.io", "web.app", "firebaseapp.com", "weebly.com",
        "wixsite.com", "vercel.app", "netlify.app", "pages.dev", "workers.dev", "glitch.me",
        "blogspot.com", "wordpress.com", "godaddysites.com", "square.site", "webflow.io",
        "framer.website", "carrd.co", "jotform.com", "typeform.com", "surveymonkey.com", "wufoo.com",
        // Anyone's beta app (the usual way "trading apps" reach iPhones in pig-butchering scams).
        "testflight.apple.com",
    ]

    /// Words in a host that make it look like a lure ("secure", "verify", "billing"). Used for
    /// brand names that are everyday words (`Brand.wordTokens`) and for near-miss names.
    /// Lure words that also end real organizations' host names when glued on.
    static let gluedSuffixExceptions: Set<String> = ["center", "service", "services", "online"]

    static let lureHostTokens: Set<String> = [
        "secure", "security", "verify", "verification", "login", "signin", "logon", "account", "accounts",
        "billing", "bill", "pay", "payment", "payments", "update", "support", "help", "helpdesk", "service",
        "services", "alert", "alerts", "notice", "unlock", "restore", "refund", "refunds", "claim", "track",
        "tracking", "delivery", "deliver", "redelivery", "parcel", "package", "shipping", "id", "auth",
        "confirm", "online", "portal", "center", "fraud", "protect", "recovery", "reset", "wallet", "card",
        "cards", "fee", "fees", "invoice", "order", "orders", "prize", "reward", "rewards",
        "cancel", "cancellation", "renew", "renewal", "dispute",
    ]

    /// Brand labels (`lookalike_domain` near misses) that are everyday words, so one letter off is
    /// usually another everyday word or a name ("carter", "chapter" → charter; "officer", "offices"
    /// → office; "squire" → square). A near miss of these counts only when the message names the
    /// brand.
    static let everydayWordLabels: Set<String> = [
        "charter", "discover", "office", "regions", "square", "target", "windows", "outlook", "spectrum",
        "messenger", "vanguard", "fidelity", "synchrony", "huntington", "audible", "android",
    ]

    /// Everyday words one letter from a distinctive brand label (from a scan of the system word
    /// list against `brandLabelSkeletons`): not typo-squats ("trust" → truist, "goggle" → google,
    /// "medicate" → medicare, "papal" → paypal, "surpass" → sunpass).
    static let nearMissStopWords: Set<String> = [
        "trust", "truism", "trist", "goggle", "googly", "medicate", "papal", "surpass", "subpass",
        "amazona", "applecart", "gianthood", "peacod", "riverling", "unbank", "upbank", "synchrone",
    ]

    /// Free email providers: an address there that claims to be a brand's support desk is a sign.
    public static let freeMailDomains: [String] = [
        "gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "aol.com", "icloud.com", "me.com",
        "proton.me", "protonmail.com", "gmx.com", "mail.com", "yandex.com", "zoho.com",
    ]

    // MARK: - Brands

    public static let brands: [Brand] = [
        // Apple
        Brand(
            id: "apple",
            domains: ["apple.com", "icloud.com", "me.com", "mac.com", "apple.co", "itunes.com", "applecard.apple"],
            patterns: [
                #"apple ?id"#, #"apple (account|support|care|pay|card|cash|store|music|tv|one|inc)"#, "applecare",
                "icloud", "itunes", "app store", "apple watch", "iphone (support|security)",
            ],
            caseSensitive: [#"\b(Apple|APPLE)\b(?! (pie|juice|cider|sauce|crisp|tree|trees|orchard|picking|butter|crumble|bread|cake|slices?))"#],
            hostTokens: ["apple", "icloud", "appleid", "itunes"],
            hostSubstrings: ["appleid", "icloud", "applesupport", "itunes"],
            wordTokens: ["apple"]
        ),
        Brand(
            id: "microsoft",
            domains: [
                "microsoft.com", "live.com", "outlook.com", "office.com", "microsoftonline.com", "aka.ms",
                "hotmail.com", "xbox.com", "windows.com", "bing.com", "microsoft365.com", "skype.com",
                // Teams, Forms and Loop links ("teams.cloud.microsoft"), MSN, and Office's old name.
                "cloud.microsoft", "msn.com", "office365.com",
            ],
            patterns: [
                "microsoft", "windows (defender|security|support|firewall)", "office ?365",
                // "outlook" alone is also the weather outlook.
                #"outlook(\.com| (account|mail|email|e-mail|password|login|log-in|sign-?in|team|support|security|inbox|web ?app|storage|mailbox|calendar|app))"#,
                #"(your|my|an|the) outlook (account|mail|email|password|inbox|mailbox|storage)"#,
                "hotmail", "xbox", "msn",
            ],
            caseSensitive: [#"\bOutlook(?= (account|mail|email|password|login|team|support|security|inbox|mailbox|storage))"#],
            hostTokens: ["microsoft", "windows", "outlook", "office365", "msft"],
            hostSubstrings: ["microsoft", "office365"],
            wordTokens: ["windows", "outlook"]
        ),
        Brand(
            id: "google",
            domains: [
                "google.com", "gmail.com", "g.co", "youtube.com", "android.com", "googlemail.com",
                "withgoogle.com", "forms.gle", "goo.gl",
            ],
            patterns: ["google", "gmail", "google play", "youtube"],
            hostTokens: ["google", "gmail", "googleplay"],
            hostSubstrings: ["google", "gmail"]
        ),
        Brand(
            id: "amazon",
            domains: [
                "amazon.com", "amazon.co.uk", "amazon.ca", "amzn.com", "amzn.to", "a.co", "primevideo.com",
                "audible.com", "amazon.jobs", "amazonpay.com",
            ],
            patterns: ["amazon", "amzn", "prime video", "prime membership", "amazon prime"],
            hostTokens: ["amazon", "amzn"],
            hostSubstrings: ["amazon"]
        ),
        Brand(
            id: "disney",
            domains: ["disneyplus.com", "disney.com"],
            patterns: ["disney\\+", "disney plus", "disneyplus"],
            hostTokens: ["disneyplus"],
            hostSubstrings: ["disneyplus"]
        ),
        Brand(
            id: "hulu",
            domains: ["hulu.com"],
            patterns: ["hulu"],
            hostTokens: ["hulu", "hu1u"],
            hostSubstrings: ["hulu"]
        ),
        Brand(
            id: "netflix",
            domains: ["netflix.com"],
            patterns: ["netflix"],
            hostTokens: ["netflix"],
            hostSubstrings: ["netflix"]
        ),
        Brand(
            id: "meta",
            // Facebook sends every notification and security email from facebookmail.com.
            domains: [
                "facebook.com", "fb.com", "meta.com", "instagram.com", "whatsapp.com", "messenger.com", "wa.me",
                "facebookmail.com", "fb.me", "threads.net", "threads.com",
            ],
            patterns: ["facebook", "instagram", "whatsapp (support|team|security)", "meta (support|verified|business)"],
            hostTokens: ["facebook", "instagram"],
            hostSubstrings: ["facebook", "instagram"]
        ),
        Brand(
            id: "paypal",
            domains: ["paypal.com", "paypal.me", "paypalobjects.com"],
            patterns: ["paypal", "pay pal"],
            hostTokens: ["paypal"],
            hostSubstrings: ["paypal"]
        ),
        Brand(
            id: "venmo",
            domains: ["venmo.com"],
            patterns: ["venmo"],
            hostTokens: ["venmo"],
            hostSubstrings: ["venmo"]
        ),
        Brand(
            id: "zelle",
            domains: ["zellepay.com", "zelle.com"],
            patterns: ["zelle"],
            // Not a bare "zelle" substring: it ends "gazelle".
            hostTokens: ["zelle", "zellepay"],
            hostSubstrings: ["zellepay"]
        ),
        Brand(
            id: "cashapp",
            domains: ["cash.app", "cash.me", "square.com", "squareup.com", "block.xyz"],
            patterns: [#"cash ?app"#],
            hostTokens: ["cashapp"],
            hostSubstrings: ["cashapp"]
        ),
        Brand(
            id: "coinbase",
            domains: ["coinbase.com"],
            patterns: ["coinbase"],
            hostTokens: ["coinbase"],
            hostSubstrings: ["coinbase"]
        ),
        Brand(
            id: "ebay",
            domains: ["ebay.com"],
            patterns: ["ebay"],
            hostTokens: ["ebay"]
        ),
        Brand(
            id: "walmart",
            domains: ["walmart.com"],
            patterns: ["walmart"],
            hostTokens: ["walmart"],
            hostSubstrings: ["walmart"]
        ),
        Brand(
            id: "costco",
            domains: ["costco.com"],
            patterns: ["costco"],
            hostTokens: ["costco"],
            hostSubstrings: ["costco"]
        ),
        Brand(
            id: "target",
            domains: ["target.com"],
            patterns: ["target (order|circle|redcard|store|gift card|account)"],
            hostTokens: ["target"],
            wordTokens: ["target"]
        ),
        Brand(
            id: "bestbuy",
            domains: ["bestbuy.com", "geeksquad.com"],
            patterns: ["best buy", "bestbuy", "geek squad", "geeksquad"],
            hostTokens: ["bestbuy", "geeksquad"],
            hostSubstrings: ["geeksquad", "bestbuy"]
        ),
        Brand(
            id: "norton",
            domains: ["norton.com", "nortonlifelock.com", "gen.com", "lifelock.com"],
            // Not a bare "norton": Norton Healthcare, Norton Children's and the surname are not the
            // antivirus. The product, or a renewal or bill for it, is what the scams name.
            patterns: [
                #"norton ?(360|lifelock|anti-?virus|security|internet security|protection|subscription|renewal|auto-?renewal|membership|plan|account|support|team|billing|invoice|order|customer|deluxe|premium|utilities|vpn|secure vpn|antitrack|identity|password manager|ultimate|plus|standard|family|device security|mobile security)"#,
                #"(renew(ed|al|ing)?|subscri(bed|ption)|charged?|invoice|order|purchase|billed|billing|payment|cancel(l?ed|ling)?)( of| for| to| with| from)?( your| the| our| a)? norton"#,
                "lifelock",
            ],
            caseSensitive: [#"\bNORTON\b|\bNorton(?=\s*[:\-]\s)"#],
            hostTokens: ["norton", "lifelock"],
            wordTokens: ["norton"],
            lureSubstrings: ["norton"]
        ),
        Brand(
            id: "mcafee",
            domains: ["mcafee.com", "mcaf.ee"],
            patterns: ["mcafee", "mc afee"],
            hostTokens: ["mcafee"],
            hostSubstrings: ["mcafee"]
        ),
        Brand(
            id: "docusign",
            domains: ["docusign.com", "docusign.net"],
            patterns: ["docusign", "docu sign"],
            hostTokens: ["docusign"],
            hostSubstrings: ["docusign"]
        ),
        Brand(
            id: "dropbox",
            domains: ["dropbox.com", "dropboxmail.com"],
            patterns: ["dropbox"],
            hostTokens: ["dropbox"]
        ),

        // Delivery
        Brand(
            id: "usps",
            domains: ["usps.com", "usps.gov", "uspis.gov"],
            patterns: [#"usps"#, #"u\.? ?s\.? postal"#, "us postal", "united states postal", "postal service", "post office", "informed delivery"],
            hostTokens: ["usps"],
            hostSubstrings: ["usps"]
        ),
        Brand(
            id: "ups",
            domains: ["ups.com", "theupsstore.com"],
            patterns: ["ups (store|package|delivery|shipment|tracking|my choice)"],
            caseSensitive: [#"\bUPS\b"#],
            hostTokens: ["ups"],
            wordTokens: ["ups"]
        ),
        Brand(
            id: "fedex",
            domains: ["fedex.com"],
            patterns: [#"fed ?ex"#],
            hostTokens: ["fedex"],
            hostSubstrings: ["fedex"]
        ),
        Brand(
            id: "dhl",
            domains: ["dhl.com", "dhl-usa.com", "dhl.de"],
            patterns: ["dhl"],
            hostTokens: ["dhl"]
        ),

        // Government
        Brand(
            id: "irs",
            domains: ["irs.gov"],
            government: true,
            patterns: ["irs", "internal revenue", "treasury department", "us treasury", "u.s. treasury"],
            hostTokens: ["irs"],
            hostSubstrings: ["irsgov", "irsrefund", "irstax"]
        ),
        Brand(
            id: "ssa",
            domains: ["ssa.gov"],
            government: true,
            patterns: ["social security (administration|office|benefits?|payment|card)", "ssa"],
            hostTokens: ["ssa"]
        ),
        Brand(
            id: "medicare",
            // Medicare plans are run by private insurers, which send plan mail from their own
            // domains ("Aetna: your Medicare plan documents are at aetnamedicare.com").
            domains: [
                "medicare.gov", "cms.gov",
                "aetnamedicare.com", "aetna.com", "uhcmedicaresolutions.com", "aarpmedicareplans.com",
                "aarpmedicaresupplement.com", "uhc.com", "myuhc.com", "humana.com", "anthem.com", "cigna.com",
                "wellcare.com", "kp.org", "devoted.com", "bcbs.com", "mutualofomaha.com", "healthnet.com",
            ],
            government: true,
            patterns: ["medicare", "medicaid"],
            // Insurers put "medicare" in their own hosts ("medicare.uhc.com"): it names the brand
            // only in a lure-looking host.
            hostTokens: ["medicare", "medicaid"],
            wordTokens: ["medicare", "medicaid"],
            lureSubstrings: ["medicare", "medicaid"]
        ),
        Brand(
            id: "medical",
            domains: ["dhcs.ca.gov", "medi-cal.ca.gov", "benefitscal.com", "coveredca.com", "mybenefitscalwin.org"],
            government: true,
            patterns: [#"medi-?cal"#, "calfresh", "benefitscal", "covered california", "dhcs"],
            hostTokens: ["calfresh", "dhcs"],
            // "medi-cal" only with its hyphen: "medical" alone is in many real clinic domains.
            hostSubstrings: ["medi-cal", "calfresh", "benefitscal"]
        ),
        Brand(
            id: "dmv",
            domains: [],
            government: true,
            // "DMV" is also the DC-Maryland-Virginia area ("DMV Smiles Dental", "best pizza in the
            // DMV"). The agency is named as a sender, with "the/your/state DMV", or with its business.
            patterns: [
                "department of motor vehicles", "motor vehicle (department|division|commission)",
                #"(the|your|state|county|local|our) dmv(?! area| region)"#,
                #"dmv (notice|notices|alert|alerts|office|offices|department|record|records|registration|license|licence|services?|fines?|fees?|payment|penalty|violation|final|reminder|portal|online|account|system|website|id|appointment|renewal|suspension|ticket|toll)"#,
            ],
            caseSensitive: [#"\bDMV(?=\s*[:\-]\s)"#],
            hostTokens: ["dmv"],
            wordTokens: ["dmv"],
            lureSubstrings: ["dmv"]
        ),
        Brand(
            id: "government",
            domains: [],
            government: true,
            patterns: ["federal (court|government|agent)", "fbi", "u\\.?s\\.? marshals?", "sheriff'?s? (office|department)", "jury duty", "homeland security"],
            hostTokens: ["fbi", "marshal", "marshals", "courts"],
            wordTokens: ["marshal", "marshals", "courts"]
        ),

        // Tolls (E-ZPass, FasTrak, SunPass, TxTag and the rest share one allowlist).
        Brand(
            id: "tolls",
            domains: [
                "e-zpassny.com", "ezpassnj.com", "ezpassva.com", "ezpassmd.com", "ezpassde.com", "ezpassnh.com",
                "ezpassri.com", "ezpassin.com", "ezpassoh.com", "e-zpassiag.com", "e-zpass.com", "ezdrivema.com",
                "paturnpike.com", "maineturnpike.com", "ohioturnpike.org", "njta.com", "mta.info",
                "bayareafastrak.org", "thetollroads.com", "fastrak.org", "sunpass.com", "floridasturnpike.com",
                "txtag.org", "ntta.org", "hctra.org", "peachpass.com", "mygoodtogo.com", "getipass.com",
                "illinoistollway.com", "expresstoll.com", "driveezmd.com", "riverlink.com", "quickpass.us",
                "511.org",
                // Other state operators whose names the patterns below match ("turnpike", "quick pass").
                "ksturnpike.com", "pikepass.com", "ncquickpass.com", "tollsbymailny.com", "indianatollroad.org",
                "cfxway.com",
            ],
            government: true,
            patterns: [
                #"e-? ?z ?pass"#, #"fas ?trak"#, "sunpass", "txtag", "toll ?tag", "ntta", "peach pass", "i-?pass",
                "good to go pass", "toll by plate", "tollbyplate", "the toll roads", "turnpike", "toll (services|service|authority|agency|road|roads|department|bureau|center|billing|enforcement)",
                "e-?zdrive", "riverlink", "quick pass", "expresstoll",
            ],
            hostTokens: ["ezpass", "e-zpass", "fastrak", "sunpass", "txtag", "tolls", "toll", "turnpike", "tollway", "ntta"],
            hostSubstrings: ["ezpass", "fastrak", "sunpass", "txtag", "tollbyplate", "turnpike", "tollway", "tollservice", "tollroad", "tollpay"],
            wordTokens: ["toll", "tolls"]
        ),

        // Banks
        Brand(
            id: "chase",
            domains: ["chase.com", "jpmorganchase.com", "jpmorgan.com"],
            patterns: [
                "chase (bank|card|cards|sapphire|freedom|online|fraud|alert|alerts|account|debit|credit|mobile|app|security|customer|checking|savings|ink|slate|private client)",
                "jp ?morgan",
            ],
            // "Chase" is also a first name ("Hey Chase, the tickets are at …"): the capitalized
            // name counts only as a sender ("Chase:", "Chase -") or in capitals.
            caseSensitive: [#"\bCHASE\b|\bChase(?=\s*[:\-]\s)"#],
            hostTokens: ["chase", "jpmorgan"],
            hostSubstrings: ["chasebank", "chaseonline", "jpmorgan"],
            wordTokens: ["chase"]
        ),
        Brand(
            id: "bankofamerica",
            domains: ["bankofamerica.com", "bofa.com", "ml.com", "merrilledge.com"],
            patterns: ["bank of america", "bofa", "merrill"],
            hostTokens: ["bofa", "bankofamerica"],
            hostSubstrings: ["bankofamerica"]
        ),
        Brand(
            id: "wellsfargo",
            domains: ["wellsfargo.com", "wf.com"],
            patterns: [#"wells ?fargo"#],
            hostTokens: ["wellsfargo"],
            hostSubstrings: ["wellsfargo"]
        ),
        Brand(
            id: "citi",
            domains: ["citi.com", "citibank.com", "citicards.com", "citibankonline.com"],
            // Not a bare "citi": "Citi Field" is a ballpark.
            patterns: [
                #"citi ?bank"#, #"citi ?cards?"#,
                "citi (alert|alerts|account|fraud|online|security|customer|mobile|services|thankyou|double cash|premier|simplicity|custom cash)",
            ],
            caseSensitive: [#"\bCITI\b|\bCiti(?=\s*[:\-]\s)"#],
            hostTokens: ["citi", "citibank"],
            hostSubstrings: ["citibank"]
        ),
        Brand(
            id: "capitalone",
            domains: ["capitalone.com", "capitaloneshopping.com"],
            patterns: [#"capital ?one"#],
            hostTokens: ["capitalone"],
            hostSubstrings: ["capitalone"]
        ),
        Brand(
            id: "usbank",
            domains: ["usbank.com"],
            patterns: [#"u\.?s\.? bank"#, "usbank"],
            hostTokens: ["usbank"],
            hostSubstrings: ["usbank"]
        ),
        Brand(
            id: "pnc",
            domains: ["pnc.com"],
            patterns: ["pnc"],
            hostTokens: ["pnc"]
        ),
        Brand(
            id: "tdbank",
            domains: ["td.com", "tdbank.com"],
            patterns: ["td bank"],
            hostTokens: ["tdbank"],
            hostSubstrings: ["tdbank"]
        ),
        Brand(
            id: "navyfederal",
            domains: ["navyfederal.org"],
            patterns: ["navy federal"],
            hostTokens: ["navyfederal"],
            hostSubstrings: ["navyfederal"]
        ),
        Brand(
            id: "usaa",
            domains: ["usaa.com"],
            patterns: ["usaa"],
            hostTokens: ["usaa"],
            hostSubstrings: ["usaa"]
        ),
        Brand(
            id: "amex",
            domains: ["americanexpress.com", "aexp.com", "amex.com"],
            patterns: ["american express", "amex"],
            hostTokens: ["amex", "americanexpress"],
            hostSubstrings: ["americanexpress"]
        ),
        Brand(
            id: "discover",
            domains: ["discover.com"],
            patterns: ["discover (card|bank|it|account)"],
            hostSubstrings: ["discovercard", "discoverbank"]
        ),
        Brand(
            id: "otherbanks",
            domains: [
                "ally.com", "schwab.com", "fidelity.com", "vanguard.com", "truist.com", "regions.com",
                "huntington.com", "key.com", "citizensbank.com", "53.com", "synchrony.com", "mysynchrony.com",
                "becu.org", "golden1.com", "schoolsfirstfcu.org",
            ],
            patterns: [
                "ally bank", "charles schwab", "fidelity investments", "vanguard", "truist", "regions bank",
                "huntington bank", "keybank", "citizens bank", "fifth third", "synchrony", "golden 1",
            ],
            hostTokens: ["truist", "keybank", "synchrony"]
        ),

        // Phone and internet carriers
        Brand(
            id: "verizon",
            domains: ["verizon.com", "verizonwireless.com", "vzw.com", "verizon.net"],
            patterns: ["verizon"],
            hostTokens: ["verizon", "vzw"],
            hostSubstrings: ["verizon"]
        ),
        Brand(
            id: "att",
            domains: ["att.com", "att.net"],
            patterns: ["at&t", "at & t", "at and t"],
            caseSensitive: [#"\bATT\b"#],
            hostTokens: ["att"]
        ),
        Brand(
            id: "tmobile",
            domains: ["t-mobile.com", "tmobile.com", "t-mo.co", "metrobyt-mobile.com"],
            patterns: [#"t-? ?mobile"#],
            hostTokens: ["t-mobile", "tmobile"],
            hostSubstrings: ["tmobile"]
        ),
        Brand(
            id: "comcast",
            domains: ["xfinity.com", "comcast.com", "comcast.net"],
            patterns: ["xfinity", "comcast"],
            hostTokens: ["xfinity", "comcast"],
            hostSubstrings: ["xfinity", "comcast"]
        ),
        Brand(
            id: "spectrum",
            domains: ["spectrum.com", "spectrum.net", "charter.com"],
            patterns: ["spectrum (internet|mobile|bill|account|tv)", "charter spectrum"]
        ),

        // Grocery (Ahold Delhaize USA brands; §7 `aholdRefundPhish`)
        Brand(
            id: "ahold",
            domains: [
                "stopandshop.com", "foodlion.com", "hannaford.com", "giantfood.com", "giantfoodstores.com",
                "martinsfoods.com", "aholddelhaize.com", "peapod.com",
            ],
            patterns: [
                "stop ?(&|and|n) ?shop", "food lion", "hannaford", "giant food", "the giant company",
                "martin's food", "ahold", "delhaize", "peapod",
            ],
            hostTokens: ["stopandshop", "foodlion", "hannaford", "giantfood", "ahold"],
            hostSubstrings: ["stopandshop", "stopshop", "foodlion", "hannaford", "giantfood", "ahold"]
        ),
    ]

    // MARK: - Queries

    /// True when `host` is allowed for at least one of `brands`.
    public static func isAllowed(host: String, forAnyOf brands: [Brand]) -> Bool {
        brands.contains { $0.allows(host: host) }
    }

    /// True when `host` belongs to any known brand.
    public static func isKnownBrandHost(_ host: String) -> Bool {
        brands.contains { $0.allows(host: host) }
    }

    public static func isNeutral(host rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        return neutralDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public static func isFreeMail(host rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        return freeMailDomains.contains { host == $0 }
    }

    public static func isShortener(host rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return shorteners.contains(bare)
    }

    public static func isUserContent(host rawHost: String) -> Bool {
        let host = rawHost.lowercased()
        return userContentDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Brands named in the message text, or named inside the host of any link in it. A link on a
    /// user-content host (`userContentDomains`) does not name its owner: a Google Sites page is
    /// not a message from Google.
    public static func brandsNamed(in normalized: NormalizedText, links: [ExtractedLink]) -> [Brand] {
        let compiled = CompiledBrands.shared
        let texts = CompiledBrands.Texts(normalized)
        let namingLinks = links.filter { !isUserContent(host: $0.host) }
        var result: [Brand] = []
        for (index, brand) in brands.enumerated() {
            if compiled.textMatches(brandIndex: index, texts: texts)
                || namingLinks.contains(where: { hostNames(brand, host: $0.host) || localPartNames(brand, link: $0) })
            {
                result.append(brand)
            }
        }
        return result
    }

    /// "appleid.verify@gmail.com" names Apple through the part before "@".
    static func localPartNames(_ brand: Brand, link: ExtractedLink) -> Bool {
        guard link.kind == .email, !link.emailLocalPart.isEmpty else { return false }
        return hostNames(brand, host: link.emailLocalPart.replacingOccurrences(of: "_", with: "-") + ".x")
    }

    /// Brands named in the message text only (not through a link's host).
    public static func brandsNamedInText(_ normalized: NormalizedText) -> [Brand] {
        let compiled = CompiledBrands.shared
        let texts = CompiledBrands.Texts(normalized)
        return brands.indices.filter { compiled.textMatches(brandIndex: $0, texts: texts) }.map { brands[$0] }
    }

    /// True when a host looks like a lure: a lure word among its tokens, or an odd TLD.
    static func hostLooksLikeLure(_ host: String) -> Bool {
        let labels = host.lowercased().split(separator: ".").map(String.init)
        if let tld = labels.last, oddTLDs.contains(tld) { return true }
        for label in labels.dropLast() {
            for token in label.split(separator: "-") where lureHostTokens.contains(String(token)) { return true }
            // "chasesecure", "upstracking": a lure word glued to the end of the label. Not the
            // ordinary endings of real organizations' names ("seniorcenter", "lawnservices").
            for word in lureHostTokens where word.count >= 5 && label.count > word.count && label.hasSuffix(word)
                && !gluedSuffixExceptions.contains(word)
            {
                return true
            }
        }
        return false
    }

    /// True when the host's tokens name the brand ("usps-redelivery.top" names USPS). The host is
    /// skeletonized first, so "paypa1-secure.com" also names PayPal. A token that is an everyday
    /// word (`Brand.wordTokens`) counts only in a host that looks like a lure.
    static func hostNames(_ brand: Brand, host: String) -> Bool {
        // The brand's own domain names it ("ups.com" names UPS).
        if brand.allows(host: host) { return true }
        let skeletonLabels = skeleton(host).split(separator: ".").map(String.init)
        let rawLabels = host.lowercased().split(separator: ".").map(String.init)
        let lureLike = hostLooksLikeLure(host)
        let tokenSkeletons = brand.hostTokens.filter { lureLike || !brand.wordTokens.contains($0) }.map { skeleton($0) }
        let substringSkeletons = brand.hostSubstrings.map { skeleton($0) }
        for (label, raw) in zip(skeletonLabels, rawLabels) {
            var tokens = Set(label.split(separator: "-").map(String.init))
            tokens.insert(label)
            if tokenSkeletons.contains(where: { tokens.contains($0) }) { return true }
            let joined = label.replacingOccurrences(of: "-", with: "")
            for (index, substring) in brand.hostSubstrings.enumerated() {
                if raw.contains(substring) { return true }
                if !substring.contains("-"), joined.contains(substringSkeletons[index]) { return true }
            }
            if lureLike, brand.lureSubstrings.contains(where: { raw.contains($0) || joined.contains(skeleton($0)) }) {
                return true
            }
        }
        return false
    }

    // MARK: - Skeleton (look-alike detection)

    /// A "skeleton" of a domain: look-alike characters folded to one form, so "paypa1.com",
    /// "pаypal.com" (Cyrillic "а") and "paypal.com" all share the skeleton "paypal.com".
    /// "rn" → "m", "vv" → "w", "0" → "o", and "1", "i", "l", "|" → "l".
    public static func skeleton(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        let plain = text.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        for scalar in plain.unicodeScalars {
            let folded = Normalizer.foldConfusable(scalar)
            switch folded {
            case "0": scalars.append("o")
            case "1", "i", "|", "!": scalars.append("l")
            case "5": scalars.append("s")
            case "3": scalars.append("e")
            case "@": scalars.append("a")
            default: scalars.append(folded)
            }
        }
        return String(scalars)
            .replacingOccurrences(of: "rn", with: "m")
            .replacingOccurrences(of: "vv", with: "w")
    }

    /// Registrable labels of every allowlisted domain, with their skeletons ("paypal" → "paypal").
    static let brandLabelSkeletons: [(label: String, skeleton: String)] = {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for brand in brands {
            for domain in brand.domains {
                let link = ExtractedLink(kind: .web, host: domain)
                let label = link.registrableLabel
                // Very short labels ("a", "g", "wf", "td", "53") give too many accidental matches.
                guard label.count >= 4, seen.insert(label).inserted else { continue }
                out.append((label, skeleton(label)))
            }
        }
        return out
    }()

    /// Every allowlisted domain, for spotting a real domain embedded in a fake host
    /// ("usps.com.track-pkg.top", "apple.com-verify.icu").
    static let allBrandDomains: [String] = {
        var set = Set<String>()
        for brand in brands { set.formUnion(brand.domains) }
        return set.filter { $0.count >= 6 }.sorted()
    }()

    // MARK: - Split brand names

    // swiftlint:disable:next force_try
    private static let splitInWord = try! NSRegularExpression(pattern: #"(?<=\p{L})[-._](?=(\p{L}+))"#)

    /// Removes a hyphen, dot or underscore between two letters, except a dot before a real
    /// top-level domain, so links stay links ("pp-resolution-center.com" →
    /// "ppresolutioncenter.com", "Pay.Pal" → "paypal").
    static func joinSplitWords(_ text: String) -> String {
        let ns = text as NSString
        let matches = splitInWord.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let out = NSMutableString(string: text)
        for match in matches.reversed() {
            if ns.substring(with: match.range) == ".", Extractor.isKnownTLD(ns.substring(with: match.range(at: 1))) { continue }
            out.replaceCharacters(in: match.range, with: "")
        }
        return out as String
    }

    // MARK: - Compiled regexes

    /// NSRegularExpression is immutable and thread-safe once created.
    private final class CompiledBrands: @unchecked Sendable {
        static let shared = CompiledBrands()

        let lower: [NSRegularExpression?]
        let caseSensitive: [NSRegularExpression?]

        init() {
            func compile(_ alternatives: [String], options: NSRegularExpression.Options) -> NSRegularExpression? {
                guard !alternatives.isEmpty else { return nil }
                let body = alternatives.map { "(?:\($0))" }.joined(separator: "|")
                // Lowercase patterns get word boundaries; case-sensitive ones carry their own.
                let pattern = options.contains(.caseInsensitive) ? #"(?<![\p{L}\p{N}])(?:"# + body + #")(?![\p{L}\p{N}])"# : body
                return try? NSRegularExpression(pattern: pattern, options: options)
            }
            lower = BrandDomains.brands.map { compile($0.patterns, options: [.caseInsensitive]) }
            caseSensitive = BrandDomains.brands.map { compile($0.caseSensitivePatterns, options: []) }
        }

        /// The message with links blanked out: a host names a brand only through `hostNames`, so
        /// "sites.google.com/view/chase-login" does not make Google a named brand by its letters.
        /// One more reading joins letters split by a hyphen, dot or underscore ("Pay-Pal",
        /// "Net.flix" → "paypal", "netflix"), after the links are blanked so hosts stay out of it.
        struct Texts {
            let lower: [String]
            let original: String

            init(_ normalized: NormalizedText) {
                let readings = normalized.leetFolded == normalized.folded ? [normalized.folded] : [normalized.folded, normalized.leetFolded]
                var masked = readings.map(CompiledBrands.maskLinks)
                for reading in readings {
                    let joined = CompiledBrands.maskLinks(BrandDomains.joinSplitWords(reading))
                    if !masked.contains(joined) { masked.append(joined) }
                }
                lower = masked
                original = CompiledBrands.maskLinks(normalized.text)
            }
        }


        // swiftlint:disable:next force_try
        static let linkToken = try! NSRegularExpression(
            // Starts only where a run of host characters starts: without the look-behind, a long run
            // with no dot ("aaaa…", 8,000 Arabic letters) was rescanned from every position.
            pattern: #"(?<![\p{L}\p{N}._%+@-])(?:(?:https?|ftp)://)?[\p{L}\p{N}._%+@-]*[\p{L}\p{N}]\.\p{L}{2,}(?:[./?#=&%+@:~-][^\s]*)?"#,
            options: [.caseInsensitive]
        )

        static func maskLinks(_ text: String) -> String {
            linkToken.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        func textMatches(brandIndex: Int, texts: Texts) -> Bool {
            if let regex = lower[brandIndex] {
                // Both readings: "P@yP@l" and "P a y P a l" name PayPal too.
                for text in texts.lower where regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    return true
                }
            }
            if let regex = caseSensitive[brandIndex],
               regex.firstMatch(in: texts.original, range: NSRange(texts.original.startIndex..., in: texts.original)) != nil
            {
                return true
            }
            return false
        }
    }
}
