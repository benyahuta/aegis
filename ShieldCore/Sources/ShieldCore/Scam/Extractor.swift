// Scam pipeline step 2 (SPEC §5.3): pull links and phone numbers out of the normalized text.
//
// NSDataDetector is the base (§3), but on its own it misses or mis-cuts the hosts scammers use
// most: it ignores bare "usps-redelivery.top/track", it cuts "e-zpass.com-billing.sbs" down to the
// real "e-zpass.com", and it drops "https://paypal.com@evil.top". So a host scanner runs too and the
// two results are merged. A wrongly cut host can only ADD a link here, never hide one, because the
// rules fire on any bad link.
//
// Which endings count as a top-level domain:
//   - with "https://" in front, or a "/" path after it, any alphabetic ending (new gTLDs appear
//     every year: ".pics", ".homes", ".autos");
//   - written bare, an ending on the known list, or a longer list of real gTLDs and country codes
//     when the host looks built ("netflix-billing.hair", three or more labels) and the ending is
//     not a capitalized word starting a sentence ("great day.Fun times").
// A missing space ("see chase.com.Thanks") drops one trailing word, but only when nothing else
// marks the token as a URL and what is left still ends in a known TLD. A real attacker host is
// never cut back to the brand domain it embeds ("paypal.com.account-review.pics").
//
// The app never opens, fetches or resolves any of these links (tool-threat-model C7, F3).

import Foundation

/// One link found in a message. Never logged, stored or sent.
public struct ExtractedLink: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case web
        case email
    }

    public let kind: Kind
    /// Lowercased host, without "www." removed. For an email, the part after "@".
    public let host: String
    /// For an email, the part before "@" (lowercased). Empty for web links.
    public let emailLocalPart: String
    /// True for "https://real.com@evil.com/" style links, where the part before "@" is itself a
    /// domain meant to be read as the destination.
    public let hasDeceptiveUserInfo: Bool

    public init(kind: Kind, host: String, emailLocalPart: String = "", hasDeceptiveUserInfo: Bool = false) {
        self.kind = kind
        self.host = host.lowercased()
        self.emailLocalPart = emailLocalPart.lowercased()
        self.hasDeceptiveUserInfo = hasDeceptiveUserInfo
    }

    public var labels: [String] { host.split(separator: ".").map(String.init) }

    /// Last label ("top" in "usps-redelivery.top").
    public var tld: String { labels.last ?? "" }

    public var isIPAddress: Bool { Extractor.isIPv4(host) || host.contains(":") }

    /// Any label is IDNA-encoded ("xn--").
    public var isPunycode: Bool { labels.contains { $0.hasPrefix("xn--") } }

    /// The host has non-ASCII letters (an internationalized domain written in Unicode).
    public var hasNonASCII: Bool { host.unicodeScalars.contains { !$0.isASCII } }

    /// A simplified registrable domain: the last two labels, or three for common two-part public
    /// suffixes like "co.uk". Good enough for comparing against an allowlist.
    public var registrableDomain: String {
        let parts = labels
        guard parts.count > 2 else { return host }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if Extractor.twoPartSuffixes.contains(lastTwo) {
            return parts.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// The registrable domain without its public suffix ("paypa1" in "paypa1.com").
    public var registrableLabel: String {
        String(registrableDomain.split(separator: ".").first ?? "")
    }
}

/// Everything step 2 found.
public struct Extraction: Sendable, Hashable {
    public let links: [ExtractedLink]
    /// Phone numbers, digits only (a leading "+" kept). Vanity numbers keep their letters.
    public let phoneNumbers: [String]

    public init(links: [ExtractedLink], phoneNumbers: [String]) {
        self.links = links
        self.phoneNumbers = phoneNumbers
    }

    public var webLinks: [ExtractedLink] { links.filter { $0.kind == .web } }
    public var hasPhoneNumber: Bool { !phoneNumbers.isEmpty }
}

public enum Extractor {
    public static func extract(from normalized: NormalizedText) -> Extraction {
        extract(text: normalized.text)
    }

    public static func extract(text input: String) -> Extraction {
        let text = undoDefanging(input)

        var links: [ExtractedLink] = []
        var seen = Set<String>()
        func add(_ link: ExtractedLink) {
            let key = "\(link.kind)|\(link.host)|\(link.emailLocalPart)|\(link.hasDeceptiveUserInfo)"
            if seen.insert(key).inserted { links.append(link) }
        }

        scanHosts(in: text, add: add)
        scanIPs(in: text, add: add)

        var phones: [String] = []
        var seenPhones = Set<String>()
        func addPhone(_ raw: String) {
            let cleaned = cleanPhone(raw)
            guard cleaned.filter(\.isNumber).count >= 7 || cleaned.contains(where: \.isLetter) else { return }
            if seenPhones.insert(cleaned).inserted { phones.append(cleaned) }
        }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        for match in Detectors.dataDetector.matches(in: text, range: fullRange) {
            switch match.resultType {
            case .link:
                guard let url = match.url else { continue }
                if url.scheme?.lowercased() == "mailto" {
                    let address = url.absoluteString.dropFirst("mailto:".count)
                    let parts = address.split(separator: "@", maxSplits: 1).map(String.init)
                    if parts.count == 2, let host = parts[1].split(separator: "?").first, host.contains(".") {
                        add(ExtractedLink(kind: .email, host: String(host), emailLocalPart: parts[0]))
                    }
                } else if let scheme = url.scheme?.lowercased(), ["http", "https", "ftp"].contains(scheme),
                          let host = url.host,
                          isAcceptableDetectorHost(host, explicitScheme: Self.hasExplicitScheme(ns.substring(with: match.range)))
                {
                    add(ExtractedLink(kind: .web, host: host))
                }
            case .phoneNumber:
                if let number = match.phoneNumber { addPhone(number) }
            default:
                break
            }
        }

        // Fallback for US numbers NSDataDetector can miss in odd spacing, and vanity numbers.
        for match in Detectors.usPhone.matches(in: text, range: fullRange) {
            addPhone(ns.substring(with: match.range))
        }
        // The letter O written for zero ("1-8OO-555-O199"), to slip past filters that look for
        // digits. Only in a number shape with at least six real digits, so "Room 1O1" stays text.
        for match in Detectors.ohPhone.matches(in: text, range: fullRange) {
            let raw = ns.substring(with: match.range)
            guard raw.contains(where: { $0 == "O" || $0 == "o" }), raw.filter({ $0.isASCII && $0.isNumber }).count >= 6 else { continue }
            addPhone(String(raw.map { $0 == "O" || $0 == "o" ? "0" : $0 }))
        }
        // Numbers spaced out digit by digit ("8 8 8 5 5 5 0 1 2 3") or spelled out ("eight eight
        // eight, five five five …"), a common way to slip a callback number past carrier filters.
        for number in spacedOrSpelledPhoneNumbers(in: text) {
            addPhone(number)
        }

        return Extraction(links: links, phoneNumbers: phones)
    }

    // MARK: - Host scanner

    private static func scanHosts(in text: String, add: (ExtractedLink) -> Void) {
        let ns = text as NSString
        for match in Detectors.host.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let hasScheme = match.range(at: 1).location != NSNotFound
            let userInfo = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)) : nil
            let original = ns.substring(with: match.range(at: 3))
            var host = original.lowercased()
            var originalLabels = original.split(separator: ".").map(String.init)
            while host.hasSuffix(".") { host.removeLast() }
            while originalLabels.last?.isEmpty == true { originalLabels.removeLast() }

            // A path, query or port right after the host marks the token as a URL ("…top/pay",
            // "…top?id=3", "…top:8080"). A "?" ending a question or a ":" before a word does not.
            let end = match.range.location + match.range.length
            let hasPath = Self.isURLContinuation(ns, at: end)
            let isURL = hasScheme || hasPath

            var labels = host.split(separator: ".").map(String.init)
            guard labels.count >= 2 else { continue }
            if !acceptsTLD(labels: labels, originalTLD: originalLabels.last ?? "", isURL: isURL) {
                // A missing space ("chase.com.thanks"): drop one trailing word, if what is left is a
                // host on its own. Never for a URL, and never more than one label.
                let last = labels[labels.count - 1]
                let trimmed = Array(labels.dropLast())
                if !isURL, trimmed.count >= 2, last.allSatisfy({ $0.isASCII && $0.isLetter }),
                   tldClass(trimmed[trimmed.count - 1]) == .known
                {
                    labels = trimmed
                } else if labels.count >= 3, tldClass(last) != .invalid,
                          labels.dropFirst().dropLast().contains(where: { tldClass($0) == .known })
                {
                    // "paypal.com.account-review.zzz": a real domain followed by more labels is
                    // the embedded-brand trick, whatever the ending. Keep the whole host.
                } else {
                    continue
                }
            }
            guard labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 }) else { continue }
            // A host made of digits only ("3.14") is not a host.
            guard labels.dropLast().contains(where: { $0.contains(where: \.isLetter) }) else { continue }
            host = labels.joined(separator: ".")

            if let userInfo {
                if hasScheme || looksLikeDomain(userInfo) {
                    add(ExtractedLink(kind: .web, host: host, hasDeceptiveUserInfo: looksLikeDomain(userInfo)))
                } else {
                    add(ExtractedLink(kind: .email, host: host, emailLocalPart: userInfo))
                }
            } else {
                add(ExtractedLink(kind: .web, host: host))
            }
        }
    }

    static func isURLContinuation(_ text: NSString, at index: Int) -> Bool {
        guard index < text.length else { return false }
        let next = index + 1 < text.length ? Unicode.Scalar(text.character(at: index + 1)) : nil
        switch Unicode.Scalar(text.character(at: index)) {
        case "/": return true
        case "?", "#": return next.map { !$0.properties.isWhitespace && !"!?.,)\"'".unicodeScalars.contains($0) } ?? false
        case ":": return next.map { ("0"..."9").contains($0) } ?? false
        default: return false
        }
    }

    // MARK: - Top-level domains

    enum TLDClass: Equatable {
        /// On the known list: a link even when written bare.
        case known
        /// A real gTLD or country code that is also a common word or abbreviation: a link when
        /// written bare only if the host looks built.
        case word
        /// Alphabetic, but on neither list: a link only with a scheme or a path.
        case unlisted
        /// Not a TLD at all (digits, too long).
        case invalid
    }

    static func tldClass(_ label: String) -> TLDClass {
        let tld = label.lowercased()
        if tld.hasPrefix("xn--") || knownTLDs.contains(tld) || BrandDomains.oddTLDs.contains(tld) { return .known }
        guard (2...24).contains(tld.count), tld.allSatisfy({ $0.isASCII && $0.isLetter }) else { return .invalid }
        if wordTLDs.contains(tld) || tld.count == 2 { return .word }
        return .unlisted
    }

    /// True when `labels` end in something this scanner treats as a TLD.
    static func acceptsTLD(labels: [String], originalTLD: String, isURL: Bool) -> Bool {
        let tld = labels[labels.count - 1]
        let tldKind = tldClass(tld)
        if tldKind == .invalid { return false }
        if isURL { return true }
        // "great day.Fun times", "a good cut.Hair is next": a capital letter after a period
        // starts a sentence. Short endings (com, net, top) keep working however they are typed.
        // An odd ending after a built label ("usps-track.Click", "parcel-usps.Homes") is a link
        // however it is capitalized: prose has no hyphenated or numbered word glued to a period.
        let builtLabel = labels.dropLast().last.map { $0.contains("-") || $0.contains(where: \.isNumber) } ?? false
        let capitalizedWord = tld.count >= 4 && originalTLD.first?.isUppercase == true
            && originalTLD.dropFirst().contains(where: \.isLowercase)
            && !(builtLabel && BrandDomains.oddTLDs.contains(tld))
        switch tldKind {
        case .known:
            return !capitalizedWord
        case .word:
            let built = labels.count >= 3
                || labels.dropLast().contains { label in label.contains("-") || label.contains(where: \.isNumber) }
            return built && !capitalizedWord && !originalTLD.contains(where: \.isUppercase)
        case .unlisted, .invalid:
            return false
        }
    }

    private static func scanIPs(in text: String, add: (ExtractedLink) -> Void) {
        let ns = text as NSString
        for match in Detectors.ipURL.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let group = match.range(at: 1).location != NSNotFound ? 1 : 2
            let ip = ns.substring(with: match.range(at: group))
            if isIPv4(ip) { add(ExtractedLink(kind: .web, host: ip)) }
        }
    }

    /// NSDataDetector also turns "ok.so" into a link; keep only hosts with a TLD the scanner would
    /// accept (or an IP address). With "https://" typed in front, any alphabetic ending counts.
    static func isAcceptableDetectorHost(_ host: String, explicitScheme: Bool = false) -> Bool {
        if isIPv4(host) || host.contains(":") { return true }
        let labels = host.lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2, let last = labels.last else { return false }
        return acceptsTLD(labels: labels, originalTLD: last, isURL: explicitScheme)
    }

    static func hasExplicitScheme(_ matched: String) -> Bool {
        let lower = matched.lowercased()
        return ["http", "https", "ftp"].contains { lower.hasPrefix($0 + "://") }
    }

    // MARK: - Defanging

    /// Undoes the ways scammers (and security write-ups) break a link so filters miss it:
    /// "usps[.]com", "paypal(dot)com", "paypal {.} com", "hxxp://", "paypal-secure .com",
    /// "usps-track dot top", "paypal-secure,com/login".
    static func undoDefanging(_ input: String) -> String {
        var text = input
            .replacingOccurrences(of: "[.]", with: ".")
            .replacingOccurrences(of: "(.)", with: ".")
            .replacingOccurrences(of: "[dot]", with: ".")
            .replacingOccurrences(of: "hxxp", with: "http", options: .caseInsensitive)
        for (pattern, template) in Detectors.defang {
            text = pattern.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template
            )
        }
        return text
    }

    // MARK: - Spaced-out and spelled-out phone numbers

    static let spelledDigits: [String: Character] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    /// 10- or 11-digit US numbers written one digit at a time, with digits or number words.
    static func spacedOrSpelledPhoneNumbers(in text: String) -> [String] {
        var out: [String] = []
        let ns = text as NSString
        for match in Detectors.spacedDigits.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let digits = ns.substring(with: match.range).filter { $0.isASCII && $0.isNumber }
            if isPlausibleUSNumber(digits) { out.append(digits) }
        }
        // Number words: a run of them, separated only by spaces, commas, dashes or periods.
        var run = ""
        func flush() {
            if isPlausibleUSNumber(run) { out.append(run) }
            run = ""
        }
        for word in text.lowercased().split(whereSeparator: { " ,.-\n".contains($0) }) {
            if let digit = spelledDigits[String(word)] {
                run.append(digit)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    static func isPlausibleUSNumber(_ digits: String) -> Bool {
        let body = digits.count == 11 && digits.hasPrefix("1") ? String(digits.dropFirst()) : digits
        guard body.count == 10, let first = body.first, first != "0", first != "1" else { return false }
        return true
    }

    static func looksLikeDomain(_ text: String) -> Bool {
        let parts = text.lowercased().split(separator: ".")
        guard parts.count >= 2, let last = parts.last else { return false }
        return isKnownTLD(String(last))
    }

    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), let value = Int(part) else { return false }
            return value <= 255
        }
    }

    private static func cleanPhone(_ raw: String) -> String {
        var out = ""
        for (index, ch) in raw.enumerated() {
            if ch.isNumber && ch.isASCII { out.append(ch) }
            else if ch.isLetter && ch.isASCII { out.append(Character(ch.uppercased())) }
            else if ch == "+" && index == 0 { out.append(ch) }
        }
        return out
    }

    // MARK: - TLDs

    public static func isKnownTLD(_ label: String) -> Bool {
        let tld = label.lowercased()
        return tld.hasPrefix("xn--") || knownTLDs.contains(tld) || BrandDomains.oddTLDs.contains(tld)
    }

    /// Top-level domains the host scanner accepts. Two-letter country codes that are also common
    /// English words ("in", "is", "it", "at", "be", "to", "no", "so", "do", "my") are left out, so a
    /// missing space after a period ("ok.so") is not read as a link.
    static let knownTLDs: Set<String> = [
        "com", "net", "org", "gov", "edu", "mil", "int", "info", "biz", "name", "pro", "mobi",
        "io", "co", "us", "me", "app", "dev", "ai", "tv", "ly", "gl", "gd", "cc", "ws", "pw",
        "ms", "gle", "page", "link", "help", "support", "services", "service", "news",
        "uk", "ca", "au", "de", "fr", "es", "nl", "ru", "cn", "jp", "br", "mx", "nz", "ie",
        "ch", "se", "dk", "fi", "pl", "pt", "cz", "ua", "kr", "tw", "hk", "sg", "ph", "vn",
        "th", "za", "ng", "pk", "ar", "cl", "pe", "ve", "tr", "il", "eg", "sa", "ae", "ir",
        "su", "tk", "ml", "ga", "cf", "gq", "cm", "la", "ac", "sh", "fm", "am", "li", "lt",
        "lv", "ee", "ro", "bg", "gr", "hu", "sk", "si", "hr", "rs", "by", "kz", "uz", "id",
        "nu", "vc", "gs", "tc",
        "shop", "store", "online", "site", "website", "live", "life", "world", "space",
        "tech", "cloud", "email", "digital", "network", "center", "solutions", "agency", "group",
        "company", "finance", "financial", "bank", "money", "pay", "cash", "credit", "loans",
        "fund", "capital", "exchange", "trade", "market", "markets", "deals", "sale",
        "delivery", "express", "post", "parcel", "global", "zone", "social", "chat", "games", "club",
    ]

    /// Real gTLDs that are also everyday words or abbreviations ("fun", "one", "today", "art"),
    /// and anything else delegated by IANA that scammers register. Accepted bare only when the
    /// host looks built (see `acceptsTLD`). Any two-letter ending counts the same way, since
    /// nearly every pair is a country code ("in", "it", "at", "to", "so", "be").
    static let wordTLDs: Set<String> = [
        "academy", "accountants", "actor", "adult", "airforce", "apartments", "army", "art", "associates",
        "attorney", "auction", "audio", "auto", "baby", "band", "bar", "bargains", "beer", "best", "bet",
        "bike", "bingo", "bio", "black", "blog", "blue", "boo", "boutique", "box", "build", "builders",
        "business", "cab", "cafe", "camera", "camp", "car", "cards", "care", "career", "careers", "cars",
        "casa", "casino", "catering", "charity", "cheap", "christmas", "church", "city", "claims",
        "cleaning", "clinic", "clothing", "coach", "codes", "coffee", "college", "community", "computer",
        "condos", "construction", "consulting", "contact", "contractors", "cooking", "cool", "coupons",
        "courses", "creditcard", "cruises", "dad", "dance", "dating", "day", "deal", "degree", "democrat",
        "dental", "dentist", "design", "diamonds", "diet", "direct", "directory", "discount", "doctor",
        "dog", "domains", "earth", "eco", "education", "energy", "engineer", "engineering", "enterprises",
        "equipment", "esq", "estate", "events", "expert", "exposed", "fail", "family", "fan", "fans",
        "farm", "fashion", "film", "fish", "fit", "fitness", "flights", "florist", "flowers", "foo",
        "football", "forsale", "foundation", "free", "fun", "furniture", "futbol", "fyi", "gallery",
        "game", "garden", "gay", "gift", "gifts", "gives", "glass", "gmbh", "gold", "golf", "graphics",
        "gratis", "green", "gripe", "guide", "guru", "haus", "health", "healthcare", "hockey", "holdings",
        "holiday", "horse", "hospital", "host", "hosting", "hot", "house", "how", "immo", "inc",
        "industries", "ing", "ink", "institute", "insure", "international", "investments", "jewelry",
        "kids", "kitchen", "land", "law", "lawyer", "lease", "legal", "limited", "limo", "llc", "love",
        "ltd", "luxury", "management", "marketing", "mba", "media", "meme", "memorial", "menu",
        "mortgage", "movie", "music", "navy", "new", "ninja", "now", "nyc", "one", "ooo", "organic",
        "partners", "parts", "pet", "phd", "photo", "photography", "photos", "pictures", "pink", "pizza",
        "place", "plumbing", "plus", "poker", "porn", "press", "productions", "prof", "promo",
        "properties", "property", "pub", "realty", "recipes", "red", "rehab", "rent", "rentals", "repair",
        "report", "republican", "restaurant", "reviews", "rich", "rip", "rocks", "rodeo", "rsvp", "run",
        "salon", "school", "security", "shoes", "show", "singles", "ski", "soccer", "software", "solar",
        "spot", "studio", "style", "sucks", "supplies", "supply", "surf", "surgery", "systems", "tax",
        "taxi", "team", "technology", "tennis", "theater", "theatre", "tips", "tires", "today", "tools",
        "tours", "town", "toys", "training", "travel", "tube", "university", "uno", "vacations", "vegas",
        "ventures", "vet", "video", "villas", "vin", "vision", "vodka", "vote", "voting", "voyage",
        "watch", "webcam", "wedding", "wiki", "wine", "wtf", "yoga", "you",
    ]

    /// Two-part public suffixes, so "evil.co.uk" has the registrable domain "evil.co.uk".
    static let twoPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "gov.uk", "ac.uk", "me.uk", "com.au", "net.au", "org.au", "co.nz",
        "co.jp", "com.br", "com.mx", "co.in", "com.cn", "com.hk", "com.sg", "co.za", "com.tr",
        "com.ar", "co.kr", "com.ph", "com.vn", "com.ng", "com.pk", "com.ua", "co.il",
    ]

    // MARK: - Compiled patterns

    /// NSDataDetector and NSRegularExpression are immutable after creation and documented as safe
    /// to use from several threads at once.
    private struct Detectors: @unchecked Sendable {
        let dataDetector: NSDataDetector
        let host: NSRegularExpression
        let ipURL: NSRegularExpression
        let usPhone: NSRegularExpression
        let ohPhone: NSRegularExpression
        let spacedDigits: NSRegularExpression
        let defang: [(NSRegularExpression, String)]

        static let shared = Detectors()

        static var dataDetector: NSDataDetector { shared.dataDetector }
        static var host: NSRegularExpression { shared.host }
        static var ipURL: NSRegularExpression { shared.ipURL }
        static var usPhone: NSRegularExpression { shared.usPhone }
        static var ohPhone: NSRegularExpression { shared.ohPhone }
        static var spacedDigits: NSRegularExpression { shared.spacedDigits }
        static var defang: [(NSRegularExpression, String)] { shared.defang }

        init() {
            // swiftlint:disable:next force_try
            dataDetector = try! NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            )
            // Groups: 1 scheme, 2 user info / email local part, 3 host. Not right after "/", so a
            // file name in a path ("/s/abc/tahoe.zip") is not read as another host.
            let label = #"[\p{L}\p{N}](?:[\p{L}\p{N}_-]{0,61}[\p{L}\p{N}])?"#
            let hostPattern =
                #"(?<![\p{L}\p{N}._@/-])((?:https?|ftp)://)?(?:([\p{L}\p{N}._%+-]{1,64})@)?((?:"# + label + #"\.)+"#
                + label + #")\.?"#
            // swiftlint:disable:next force_try
            host = try! NSRegularExpression(pattern: hostPattern, options: [.caseInsensitive])
            // swiftlint:disable:next force_try
            ipURL = try! NSRegularExpression(
                pattern: #"(?:https?|ftp)://(\d{1,3}(?:\.\d{1,3}){3})|(?<![\d.])(\d{1,3}(?:\.\d{1,3}){3})(?=[:/])"#,
                options: [.caseInsensitive]
            )
            // swiftlint:disable:next force_try
            usPhone = try! NSRegularExpression(
                pattern: #"(?<![\d\w])(?:\+?1[\s.-]?)?\(?[2-9]\d{2}\)?[\s.-]?\d{3}[\s.-]?\d{4}(?!\d)|(?<![\d\w])1?[\s.-]?8(?:00|33|44|55|66|77|88)[\s.-]?[A-Z0-9]{3}[\s.-]?[A-Z0-9]{4}(?![\w])"#,
                options: []
            )
            // swiftlint:disable:next force_try
            ohPhone = try! NSRegularExpression(
                pattern: #"(?<![\w])(?:\+?1[\s.-]?)?\(?[2-9][0-9Oo]{2}\)?[\s.-]?[0-9Oo]{3}[\s.-]?[0-9Oo]{4}(?![\w])"#,
                options: []
            )
            // Ten or eleven digits, each on its own, separated by spaces, dots or dashes.
            // swiftlint:disable:next force_try
            spacedDigits = try! NSRegularExpression(
                pattern: #"(?<![\w])\+?\d(?:[ .-]{1,3}\d){9,10}(?![\w])"#,
                options: []
            )
            let tld = #"(com|net|org|gov|edu|info|biz|us|co|io|me|app|top|xyz|click|icu|cyou|buzz|sbs|rest|cfd|bond|vip|shop|store|online|site|live|life|support|help|pics|homes|autos|boats|hair|skin|lat|ru|cn|uk|ca)"#
            let oddTLD = #"(top|xyz|click|icu|cyou|buzz|sbs|rest|cfd|bond|vip|pics|homes|autos|boats|hair|skin|lat|lol|mom|cam|monster|quest)"#
            func regex(_ pattern: String) -> NSRegularExpression {
                // swiftlint:disable:next force_try
                try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            }
            defang = [
                // "paypal(dot)com", "paypal {.} com", "paypal [ dot ] com". Each pattern starts only
                // where a run starts (a look-behind), so a long run of spaces or letters is read once,
                // not again from every position in it.
                (regex(#"(?<!\s)\s*[\[\(\{]\s*(?:\.|dot)\s*[\]\)\}]\s*"#), "."),
                // "paypal-secure .com", "paypal-secure . com": a space before the dot, then a TLD.
                (regex(#"(?<=[a-z0-9])\s+\.\s*(?="# + tld + #"(?![a-z0-9]))"#), "."),
                // "usps-redelivery. top/track": a space after the dot, then a TLD and a path.
                (regex(#"(?<=[a-z0-9])\.[ ]{1,2}(?="# + tld + #"/)"#), "."),
                // "usps-redelivery. top": the same with no path, only after a built label (a hyphen
                // or digit in it) and a lowercase odd ending, so "the well-known dog. Top that" stays prose.
                (regex(#"(?<![a-z0-9.-])(?=[a-z0-9-]*[-0-9])([a-z0-9-]++)(?<=[a-z0-9])\.[ ]{1,2}(?=(?-i:"# + oddTLD + #")(?![a-z0-9]))"#), "$1."),
                // "usps-track dot top": only after a built label (a hyphen or digit in it), so "the
                // dot com bubble" and "polka dot dress" stay prose.
                (regex(#"(?<![a-z0-9.-])(?=[a-z0-9-]*[-0-9])([a-z0-9-]++)(?<=[a-z0-9])\s+dot\s+(?="# + tld + #"(?![a-z0-9]))"#), "$1."),
                // "paypal-secure,com/login": a comma for the dot after a hyphenated label.
                (regex(#"(?<![a-z0-9.-])(?=[a-z0-9]+-)([a-z0-9-]++)(?<=[a-z0-9]),(?="# + tld + #"(?![a-z0-9]))"#), "$1."),
            ]
        }
    }
}
