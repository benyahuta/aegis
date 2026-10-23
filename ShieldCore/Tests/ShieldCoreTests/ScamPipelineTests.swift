import XCTest
@testable import ShieldCore

// Normalizer, Extractor and BrandDomains (SPEC §5.3 steps 1–2).

final class NormalizerTests: XCTestCase {
    func testStripsZeroWidthAndBidiControls() {
        let input = "gi\u{200B}ft\u{200C} ca\u{200D}rd\u{200E}\u{200F}\u{2060}\u{FEFF} \u{202A}a\u{202B}b\u{202C}c\u{202D}d\u{202E}e\u{2066}f\u{2067}g\u{2068}h\u{2069}"
        let n = Normalizer.normalize(input)
        XCTAssertEqual(n.text, "gift card abcdefgh")
        XCTAssertEqual(n.removedInvisibleCount, 16)
        XCTAssertFalse(n.text.unicodeScalars.contains(where: Normalizer.isInvisible))
    }

    func testCountsHiddenCharactersInsideWordsOnly() {
        XCTAssertEqual(Normalizer.normalize("gi\u{200B}ft ca\u{200B}rd").hiddenInWordCount, 2)
        // ZWJ inside an emoji family sequence is not "in a word".
        XCTAssertEqual(Normalizer.normalize("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} photo").hiddenInWordCount, 0)
        // A zero-width space between words is stripped but not counted.
        XCTAssertEqual(Normalizer.normalize("hello \u{200B}world").hiddenInWordCount, 0)
    }

    func testOnlyBidiOverridesAreCounted() {
        XCTAssertEqual(Normalizer.normalize("a\u{202E}cod.exe").bidiOverrideCount, 1)
        XCTAssertEqual(Normalizer.normalize("a\u{202D}b").bidiOverrideCount, 1)
        // Isolates that some apps add around names when copying are stripped but not counted.
        XCTAssertEqual(Normalizer.normalize("\u{2068}Ben\u{2069} says hi").bidiOverrideCount, 0)
    }

    func testNFKC() {
        // Full-width letters, ligatures and styled math letters fold to plain ASCII.
        XCTAssertEqual(Normalizer.normalize("\u{FF27}\u{FF49}\u{FF46}\u{FF54}").text, "Gift")
        XCTAssertEqual(Normalizer.normalize("\u{FB01}nal").text, "final")
        XCTAssertEqual(Normalizer.normalize("\u{1D407}\u{1D41E}\u{1D425}\u{1D425}\u{1D428}").text, "Hello")
    }

    func testFoldsQuotesDashesAndSpaces() {
        let n = Normalizer.normalize("Don\u{2019}t\u{00A0}\u{00A0}tell \u{201C}anyone\u{201D} \u{2014} ok\r\nbye")
        XCTAssertEqual(n.text, "Don't tell \"anyone\" - ok\nbye")
    }

    func testCapsAt8000Characters() {
        let n = Normalizer.normalize(String(repeating: "a", count: 9_000))
        XCTAssertEqual(n.text.count, Normalizer.maxCharacters)
        XCTAssertTrue(n.wasTruncated)
        XCTAssertFalse(Normalizer.normalize("short").wasTruncated)
    }

    func testFoldsSpoofedMixedScriptWordsButNotRealCyrillic() {
        let spoof = Normalizer.normalize("Your \u{0410}pple ID")  // Cyrillic А
        XCTAssertEqual(spoof.mixedScriptWordCount, 1)
        XCTAssertEqual(spoof.folded, "your apple id")

        let russian = Normalizer.normalize("Привет, мама! Как дела? Позвоню вечером после работы.")
        XCTAssertEqual(russian.mixedScriptWordCount, 0)
        XCTAssertEqual(russian.folded, russian.lowercased)
        XCTAssertTrue(russian.isMostlyUnreadableScript)

        // A Ukrainian word with a stray Latin "i" is not a spoof (most letters have no look-alike).
        XCTAssertEqual(Normalizer.normalize("привiт").mixedScriptWordCount, 0)
    }

    func testEmpty() {
        XCTAssertTrue(Normalizer.normalize("  \n\u{200B} ").isEmpty)
        XCTAssertFalse(Normalizer.normalize("hi").isEmpty)
    }
}

final class ExtractorTests: XCTestCase {
    func hosts(_ text: String) -> [String] {
        Extractor.extract(text: text).links.map(\.host)
    }

    func testBareOddTLDHostsThatNSDataDetectorMisses() {
        XCTAssertTrue(hosts("Pay now at usps-redelivery.top/track").contains("usps-redelivery.top"))
        XCTAssertTrue(hosts("go to stopandshop-refund.cyou/claim").contains("stopandshop-refund.cyou"))
    }

    func testDoesNotCutAFakeHostDownToTheRealDomain() {
        // NSDataDetector alone returns "e-zpass.com" here.
        XCTAssertTrue(hosts("toll at e-zpass.com-billing.sbs").contains("e-zpass.com-billing.sbs"))
        XCTAssertTrue(hosts("usps.com.parcel-help.xyz").contains("usps.com.parcel-help.xyz"))
    }

    func testDeceptiveUserInfo() {
        let links = Extractor.extract(text: "https://paypal.com@evil.top/login").links
        let link = try? XCTUnwrap(links.first { $0.host == "evil.top" })
        XCTAssertEqual(link?.hasDeceptiveUserInfo, true)
    }

    func testEmailAddresses() {
        let links = Extractor.extract(text: "Write to apple.support.team@gmail.com today").links
        let email = links.first { $0.kind == .email }
        XCTAssertEqual(email?.host, "gmail.com")
        XCTAssertEqual(email?.emailLocalPart, "apple.support.team")
        XCTAssertEqual(email?.hasDeceptiveUserInfo, false)
    }

    func testIPAddressURLs() {
        let links = Extractor.extract(text: "visit http://45.137.21.9/ezdrive now").links
        XCTAssertTrue(links.contains { $0.host == "45.137.21.9" && $0.isIPAddress })
        XCTAssertFalse(Extractor.isIPv4("999.1.1.1"))
        XCTAssertTrue(Extractor.isIPv4("10.0.0.1"))
    }

    func testPunycodeAndUnicodeHosts() {
        XCTAssertTrue(Extractor.extract(text: "https://xn--pple-43d.com/login").links.contains(where: \.isPunycode))
        XCTAssertTrue(Extractor.extract(text: "go to \u{0430}pple.com/verify").links.contains(where: { $0.isPunycode || $0.hasNonASCII }))
    }

    func testDefangedLinks() {
        XCTAssertTrue(hosts("usps[.]com-track[.]top").contains("usps.com-track.top"))
    }

    func testNotLinks() {
        XCTAssertTrue(hosts("e.g. Mr.Smith went.home at 3.30, ok.so see you").isEmpty)
        XCTAssertTrue(hosts("Your total is $45.99 on 10/22").isEmpty)
    }

    func testTrailingPunctuationAndMissingSpace() {
        XCTAssertEqual(hosts("Visit chase.com."), ["chase.com"])
        XCTAssertTrue(hosts("See chase.com.Thanks").contains("chase.com"))
    }

    func testRegistrableDomain() {
        XCTAssertEqual(ExtractedLink(kind: .web, host: "tools.usps.com").registrableDomain, "usps.com")
        XCTAssertEqual(ExtractedLink(kind: .web, host: "a.b.evil.co.uk").registrableDomain, "evil.co.uk")
        XCTAssertEqual(ExtractedLink(kind: .web, host: "paypa1.com").registrableLabel, "paypa1")
        XCTAssertEqual(ExtractedLink(kind: .web, host: "usps-redelivery.top").tld, "top")
    }

    func testPhoneNumbers() {
        let phones = Extractor.extract(text: "Call (800) 555-0199, 1-888-555-0143, +1 415 555 0101 or 1-800-MY-APPLE").phoneNumbers
        XCTAssertTrue(phones.contains("8005550199"))
        XCTAssertTrue(phones.contains("18885550143"))
        XCTAssertTrue(phones.contains { $0.hasSuffix("4155550101") })
        XCTAssertTrue(phones.contains { $0.contains("MYAPPLE") })
        // One-time codes are not phone numbers.
        XCTAssertTrue(Extractor.extract(text: "Your code is 482915.").phoneNumbers.isEmpty)
    }
}

final class BrandDomainsTests: XCTestCase {
    func brand(_ id: String) throws -> Brand {
        try XCTUnwrap(BrandDomains.brands.first { $0.id == id })
    }

    func testAllowlistIsSuffixBased() throws {
        let usps = try brand("usps")
        XCTAssertTrue(usps.allows(host: "usps.com"))
        XCTAssertTrue(usps.allows(host: "tools.usps.com"))
        XCTAssertTrue(usps.allows(host: "informeddelivery.usps.com"))
        XCTAssertFalse(usps.allows(host: "usps.com.track-pkg.top"))
        XCTAssertFalse(usps.allows(host: "notusps.com"))
        XCTAssertFalse(usps.allows(host: "usps-redelivery.top"))
    }

    func testGovernmentBrandsAcceptAnyGovHost() throws {
        XCTAssertTrue(try brand("dmv").allows(host: "dmv.ca.gov"))
        XCTAssertTrue(try brand("irs").allows(host: "irs.gov"))
        XCTAssertFalse(try brand("irs").allows(host: "irs.gov.refund-status.xyz"))
        XCTAssertFalse(try brand("dmv").allows(host: "ny.gov-dmv.xin"))
    }

    func testBrandIDsAndDomainsAreClean() {
        XCTAssertEqual(Set(BrandDomains.brands.map(\.id)).count, BrandDomains.brands.count)
        for brand in BrandDomains.brands {
            XCTAssertFalse(brand.patterns.isEmpty && brand.caseSensitivePatterns.isEmpty, brand.id)
            for domain in brand.domains {
                XCTAssertEqual(domain, domain.lowercased(), domain)
                XCTAssertTrue(domain.allSatisfy(\.isASCII), domain)
                XCTAssertFalse(domain.hasPrefix("www."), domain)
                XCTAssertTrue(domain.contains("."), domain)
            }
        }
    }

    func testSpecListedBrandsArePresent() {
        let ids = Set(BrandDomains.brands.map(\.id))
        for id in ["apple", "usps", "irs", "amazon", "paypal", "medical", "tolls", "chase", "verizon", "att", "tmobile", "ahold"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }

    func testSpecOddTLDsArePresent() {
        for tld in ["top", "xyz", "click", "icu", "cyou", "buzz", "sbs", "rest"] {
            XCTAssertTrue(BrandDomains.oddTLDs.contains(tld), tld)
        }
        XCTAssertFalse(BrandDomains.oddTLDs.contains("com"))
    }

    func testSkeleton() {
        XCTAssertEqual(BrandDomains.skeleton("paypa1"), BrandDomains.skeleton("paypal"))
        XCTAssertEqual(BrandDomains.skeleton("arnazon"), BrandDomains.skeleton("amazon"))
        XCTAssertEqual(BrandDomains.skeleton("p\u{0430}ypal"), BrandDomains.skeleton("paypal"))
        XCTAssertEqual(BrandDomains.skeleton("netfl\u{00ED}x"), BrandDomains.skeleton("netflix"))
        XCTAssertNotEqual(BrandDomains.skeleton("paypals"), BrandDomains.skeleton("paypal"))
    }

    func testBrandNamedInTextOrHost() {
        func named(_ text: String) -> Set<String> {
            let n = Normalizer.normalize(text)
            return Set(BrandDomains.brandsNamed(in: n, links: Extractor.extract(from: n).links).map(\.id))
        }
        XCTAssertTrue(named("Your USPS package").contains("usps"))
        XCTAssertTrue(named("go to usps-redelivery.top").contains("usps"))
        XCTAssertTrue(named("Pay at paypa1-secure.com").contains("paypal"))
        XCTAssertTrue(named("UPS: out for delivery").contains("ups"))
        XCTAssertFalse(named("life has ups and downs").contains("ups"))
        XCTAssertFalse(named("Grandma made apple pie").contains("apple"))
        XCTAssertFalse(named("I'll chase the dog").contains("chase"))
        XCTAssertTrue(named("Chase: your card").contains("chase"))
        XCTAssertFalse(named("Book at baymedicalgroup.com").contains("medical"))
    }

    func testShortenersAndNeutralSites() {
        XCTAssertTrue(BrandDomains.isShortener(host: "bit.ly"))
        XCTAssertTrue(BrandDomains.isShortener(host: "www.tinyurl.com"))
        XCTAssertFalse(BrandDomains.isShortener(host: "amzn.to"))
        XCTAssertTrue(BrandDomains.isNeutral(host: "www.youtube.com"))
        XCTAssertFalse(BrandDomains.isNeutral(host: "youtube.com.evil.top"))
    }
}
