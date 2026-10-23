import XCTest
@testable import ShieldCore
import LocalAuthentication

/// SPEC §13.1 CatalogLintTests, plus §6.4 service checks and the §12.4 URL-constant rule.
final class CatalogLintTests: XCTestCase {
    static let catalog: CheckCatalog = {
        do { return try CheckCatalog.bundled() } catch { fatalError("catalog.json failed to load: \(error)") }
    }()

    var catalog: CheckCatalog { Self.catalog }

    // MARK: Catalog ↔ CheckID

    func testCatalogKeysEqualCheckIDAllCases() {
        XCTAssertEqual(catalog.unknownIDs, [], "catalog.json has IDs that are not CheckID cases")
        XCTAssertEqual(catalog.duplicateIDs, [], "catalog.json has duplicate IDs")
        XCTAssertEqual(Set(catalog.entries.map(\.id)), Set(CheckID.allCases))
        XCTAssertEqual(catalog.entries.count, CheckID.allCases.count)
        XCTAssertGreaterThan(catalog.version, 0)
    }

    func testSharedCatalogLoads() {
        XCTAssertEqual(CheckCatalog.shared.entries.count, CheckID.allCases.count)
    }

    func testEveryKeyHasTitleWhyPassFailStrings() {
        for entry in catalog.entries {
            XCTAssertFalse(entry.platforms.isEmpty, entry.id.rawValue)
            for platform in entry.platforms {
                guard let variant = entry.variant(for: platform) else {
                    XCTFail("\(entry.id.rawValue) missing \(platform)")
                    continue
                }
                for key in variant.allStringKeys {
                    XCTAssertTrue(ShieldStrings.contains(key), "\(entry.id.rawValue)/\(platform): missing string \(key)")
                    let text = ShieldStrings.text(key)
                    XCTAssertNotEqual(text, key, key)
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
                }
            }
        }
    }

    func testStepsByOSMajorCoverSupportedMajors() {
        for entry in catalog.entries {
            for (platform, variant) in entry.variants {
                let expected: Set<Int> = platform == .ios ? [18, 26, 27] : [14, 15, 26, 27]
                XCTAssertEqual(Set(variant.stepsByOSMajor.keys), expected, "\(entry.id.rawValue)/\(platform)")
                for (major, steps) in variant.stepsByOSMajor {
                    if variant.kind == .accountRollup {
                        XCTAssertTrue(steps.isEmpty, "rollup steps come from Services: \(entry.id.rawValue)")
                    } else {
                        XCTAssertFalse(steps.isEmpty, "\(entry.id.rawValue)/\(platform)/\(major) has no steps")
                    }
                }
            }
        }
    }

    /// A screen shows the steps and then the notes, so a note must never repeat a step (the
    /// credit freezes once said "Choose the free freeze, not a paid lock." twice).
    func testNotesNeverRepeatASteps() {
        for entry in catalog.entries {
            for (platform, variant) in entry.variants {
                let notes = Set(variant.noteKeys.map { ShieldStrings.plain($0) })
                for (major, steps) in variant.stepsByOSMajor {
                    for step in steps {
                        XCTAssertFalse(notes.contains(ShieldStrings.plain(step)),
                                       "\(entry.id.rawValue)/\(platform)/\(major): \(step) is also a note")
                    }
                }
            }
        }
    }

    func testStepFallbackPicksNearestLowerMajor() throws {
        let variant = try XCTUnwrap(catalog.variant(.screenUnknown, platform: .ios))
        XCTAssertEqual(variant.steps(forOSMajor: 18), variant.stepsByOSMajor[18])
        XCTAssertEqual(variant.steps(forOSMajor: 28), variant.stepsByOSMajor[27])
        XCTAssertEqual(variant.steps(forOSMajor: 17), variant.stepsByOSMajor[18])
        XCTAssertNotEqual(variant.stepsByOSMajor[18], variant.stepsByOSMajor[26], "iOS 18 has different wording")
    }

    func testKindsSourcesAndPlatforms() throws {
        // Measured on the Mac, self-reported on iOS (§6.2 / §6.3).
        for id in [CheckID.autoUpdates, .findMy] {
            XCTAssertEqual(catalog.variant(id, platform: .mac)?.kind, .measured, id.rawValue)
            XCTAssertEqual(catalog.variant(id, platform: .ios)?.kind, .selfCheck, id.rawValue)
        }
        for id in CheckID.accountRollups {
            XCTAssertEqual(Set(try XCTUnwrap(catalog[id]).platforms), [.ios, .mac])
            XCTAssertEqual(catalog.variant(id, platform: .ios)?.kind, .accountRollup)
            XCTAssertEqual(catalog.variant(id, platform: .ios)?.paceGroup, 3)
        }
        for id in CheckID.neverFails {
            let entry = try XCTUnwrap(catalog[id])
            for variant in entry.variants.values { XCTAssertEqual(variant.kind, .optional, id.rawValue) }
        }
        XCTAssertEqual(catalog[.adp]?.sameAs, .advancedDataProtection)
        XCTAssertEqual(Set(try XCTUnwrap(catalog[.osPatched]).platforms), [.ios, .mac])
        XCTAssertEqual(try XCTUnwrap(catalog[.passcodeSet]).platforms, [.ios])
        XCTAssertEqual(try XCTUnwrap(catalog[.filevault]).platforms, [.mac])
        XCTAssertEqual(Set(try XCTUnwrap(catalog[.recoveryContact]).platforms), [.ios, .mac])
        XCTAssertEqual(try XCTUnwrap(catalog[.carrierLock]).platforms, [.ios])
        XCTAssertEqual(catalog.variant(.familyCodeWord, platform: .ios)?.answerStyle, .codeWord)
    }

    func testAudience() {
        let benOnly: Set<CheckID> = [.appBuildFresh, .betaCatalog, .persistenceNewItem, .chromeExtForced]
        for entry in catalog.entries {
            XCTAssertEqual(entry.audience, benOnly.contains(entry.id) ? .ben : .family, entry.id.rawValue)
        }
    }

    /// §5.1: red means ONLY exploited-and-fixed, unexpected MDM, no passcode, Gatekeeper/SIP off.
    func testTierRules() throws {
        let redBase: Set<CheckID> = [.passcodeSet, .gatekeeper, .sip, .mdmUnexpected]
        let redUrgent: Set<CheckID> = [.osPatched, .remoteAccessOff]
        for entry in catalog.entries {
            XCTAssertEqual(entry.tier == .red, redBase.contains(entry.id), "base tier \(entry.id.rawValue)")
            XCTAssertEqual(entry.urgentTier == .red, redUrgent.contains(entry.id), "urgent tier \(entry.id.rawValue)")
            if entry.urgentTier != nil {
                XCTAssertTrue(redUrgent.contains(entry.id), entry.id.rawValue)
            }
        }
        let firewall = try XCTUnwrap(catalog[.firewall])
        XCTAssertEqual(firewall.tier, .yellow)
        XCTAssertNil(firewall.urgentTier)
        XCTAssertEqual(catalog[.osPatched]?.tier, .amber)
        XCTAssertEqual(catalog[.remoteAccessOff]?.tier, .yellow)
        XCTAssertNotNil(catalog.variant(.osPatched, platform: .ios)?.failUrgentKey)
        XCTAssertNotNil(catalog.variant(.osPatched, platform: .mac)?.failUrgentKey)
    }

    func testPaceGroupsMatchSpec() {
        let iOS = Pacing(catalog: catalog, platform: .ios, includedPriorities: [.p0, .p1, .p2])
        XCTAssertEqual(iOS.selfChecks(inGroup: 1), [.autoUpdates, .findMy, .stolenDeviceProtection, .recoveryContact, .screenUnknown, .familyCodeWord].sortedByCatalog(catalog))
        XCTAssertEqual(Set(iOS.selfChecks(inGroup: 1)), [.autoUpdates, .stolenDeviceProtection, .recoveryContact, .screenUnknown, .findMy, .familyCodeWord])
        XCTAssertEqual(Set(iOS.selfChecks(inGroup: 2)), [.carrierLock, .creditFreezeEquifax, .creditFreezeExperian, .creditFreezeTransunion])
        XCTAssertEqual(Set(iOS.selfChecks(inGroup: 3)), [.passwordsAlertsClear, .fraudWebsiteWarning, .safetyCheckQuarterly])
        let mac = Pacing(catalog: catalog, platform: .mac, includedPriorities: [.p0])
        XCTAssertEqual(Set(mac.selfChecks(inGroup: 1)), [.recoveryContact, .familyCodeWord])
        XCTAssertEqual(Set(mac.selfChecks(inGroup: 2)), [.creditFreezeEquifax, .creditFreezeExperian, .creditFreezeTransunion])
        XCTAssertEqual(mac.selfChecks(inGroup: 3), [], "P1 checks stay hidden by default")
        for entry in catalog.entries {
            for variant in entry.variants.values where variant.kind == .measured {
                XCTAssertNil(variant.paceGroup, "measured checks are never paced: \(entry.id.rawValue)")
            }
        }
    }

    func testPriorities() {
        let p1: Set<CheckID> = [.timeMachine, .persistenceNewItem, .passwordsAlertsClear, .fraudWebsiteWarning, .safetyCheckQuarterly]
        let p2: Set<CheckID> = [.chromeExtForced, .advancedDataProtection]
        for entry in catalog.entries {
            let expected: Priority = p1.contains(entry.id) ? .p1 : (p2.contains(entry.id) ? .p2 : .p0)
            XCTAssertEqual(entry.priority, expected, entry.id.rawValue)
        }
    }

    // MARK: Exact spec copy (§6.1, §6.2, §6.3)

    func testMeasuredCopyIsVerbatimFromSpec() {
        let expected: [(CheckID, Platform, String, String?, String?)] = [
            (.osPatched, .ios, "iPhone updates", "Your iPhone has the latest safety fixes.", "An update with safety fixes is ready."),
            (.deviceSupported, .ios, "iPhone age", "Apple still sends safety fixes for this iPhone.", "Apple no longer sends safety fixes for this iPhone. Talk to Ben about a newer one."),
            (.passcodeSet, .ios, "Passcode", "Your iPhone has a passcode.", "Your iPhone has no passcode. Anyone who picks it up can open it."),
            (.biometricsEnrolled, .ios, "Face ID / Touch ID", "Face ID or Touch ID is set up.", "Set up Face ID or Touch ID. It protects you if your iPhone is stolen."),
            (.appBuildFresh, .ios, "App build age", nil, "Family Shield needs a new version soon. Ask Ben."),
            (.osPatched, .mac, "Mac updates", "Your Mac has the latest safety fixes.", "An update with safety fixes is ready."),
            (.osUpdateStuck, .mac, "Update trouble", nil, "Your Mac tried to update and couldn't. Please call Ben."),
            (.betaCatalog, .mac, "Beta updates", nil, "This Mac is on beta updates."),
            (.deviceSupported, .mac, "Mac age", "Apple still sends safety fixes for this Mac.", "Apple no longer sends safety fixes for this Mac. Talk to Ben."),
            (.autoUpdates, .mac, "Automatic updates", "Automatic updates are on.", "Turn on automatic updates so fixes install by themselves."),
            (.filevault, .mac, "FileVault (disk lock)", "Your Mac's files are locked if it's lost.", "Turn on FileVault so no one can read your files if your Mac is lost. Pick the option to unlock with your Apple Account."),
            (.gatekeeper, .mac, "App safety check", "Your Mac checks apps before they open.", "A safety setting that checks apps is off. Please call Ben."),
            (.sip, .mac, "System protection", "Your Mac's system is protected.", "A built-in system protection is off. Please call Ben."),
            (.xprotectCurrent, .mac, "Apple's malware protection", "Apple's built-in malware protection is up to date.", "Apple's built-in malware protection is out of date. Updating your Mac usually fixes this."),
            (.screenLock, .mac, "Screen lock", "Your Mac locks when you step away.", "Set your Mac to ask for your password right after it sleeps."),
            (.findMy, .mac, "Find My Mac", "Find My is on. You can find this Mac if it's lost.", "Turn on Find My so you can find this Mac if it's lost."),
            (.firewall, .mac, "Firewall", "The firewall is on.", "Turning on the firewall adds a little extra protection."),
            (.remoteAccessOff, .mac, "Remote access", "No one can connect to this Mac from outside.", "Remote access to this Mac is on. If you didn't turn it on, call Ben."),
            (.mdmUnexpected, .mac, "Device management", "No one else is managing this Mac.", "This Mac is being managed by an organization. If you didn't expect that, please call Ben."),
            (.timeMachine, .mac, "Backup", "Your Mac is backing up.", "Set up a backup so you never lose your photos."),
            (.persistenceNewItem, .mac, "Startup items", nil, "New startup item on this Mac looks unusual."),
        ]
        for (id, platform, title, pass, fail) in expected {
            guard let variant = catalog.variant(id, platform: platform) else {
                XCTFail("missing \(id.rawValue)/\(platform)")
                continue
            }
            XCTAssertEqual(ShieldStrings.text(variant.titleKey), title, id.rawValue)
            if let pass { XCTAssertEqual(ShieldStrings.text(variant.passKey), pass, id.rawValue) }
            if let fail { XCTAssertEqual(ShieldStrings.text(variant.failKey), fail, id.rawValue) }
        }
        XCTAssertEqual(ShieldStrings.text(catalog.variant(.osPatched, platform: .ios)!.failUrgentKey!),
                       "Please update your iPhone today. Apple fixed a problem that criminals are already using.")
        XCTAssertEqual(ShieldStrings.text(catalog.variant(.osPatched, platform: .mac)!.failUrgentKey!),
                       "Please update your Mac today. Apple fixed a problem that criminals are already using.")
        XCTAssertEqual(ShieldStrings.text(catalog.variant(.osPatched, platform: .ios)!.unknownKey!),
                       "Can't confirm. Check Software Update.")
        XCTAssertEqual(catalog.variant(.osPatched, platform: .ios)?.noteKeys.map(ShieldStrings.text(_:)),
                       ["If you see iOS 27.0.1 or iOS 26.7.1 (or newer), either one is fine."])
    }

    func testSelfCheckTitlesAndWhyAreVerbatimFromSpec() {
        let expected: [(CheckID, Platform, String, String)] = [
            (.autoUpdates, .ios, "Automatic updates", "Fixes install by themselves, even while you sleep."),
            (.stolenDeviceProtection, .ios, "Stolen Device Protection", "If a thief learns your passcode, they still can't change your Apple Account."),
            (.recoveryContact, .ios, "Recovery contact", "If you ever get locked out of your Apple Account, this person can help you get back in. They can't see your photos, messages or anything else."),
            (.recoveryContact, .mac, "Recovery contact", "If you ever get locked out of your Apple Account, this person can help you get back in. They can't see your photos, messages or anything else."),
            (.screenUnknown, .ios, "Screen unknown callers and texts", "Strangers have to say who they are before your phone rings."),
            (.findMy, .ios, "Find My iPhone", "You can find, lock or erase a lost iPhone."),
            (.familyCodeWord, .ios, "Family code word", "If someone calls sounding like family and asks for money, ask for the word."),
            (.carrierLock, .ios, "Phone number lock", "Stops criminals from moving your number to their phone."),
            (.creditFreezeEquifax, .ios, "Freeze: Equifax", "Stops anyone from opening a loan in your name."),
            (.creditFreezeExperian, .mac, "Freeze: Experian", "Stops anyone from opening a loan in your name."),
            (.creditFreezeTransunion, .ios, "Freeze: TransUnion", "Stops anyone from opening a loan in your name."),
            (.passwordsAlertsClear, .ios, "Password warnings", "Your iPhone warns you about leaked or reused passwords."),
            (.fraudWebsiteWarning, .ios, "Safari scam-site warning", "Safari warns you before opening known fake sites."),
            (.safetyCheckQuarterly, .ios, "Safety Check", "Make sure only the right people can see your location and photos."),
        ]
        for (id, platform, title, why) in expected {
            guard let variant = catalog.variant(id, platform: platform) else {
                XCTFail("missing \(id.rawValue)/\(platform)")
                continue
            }
            XCTAssertEqual(ShieldStrings.text(variant.titleKey), title, id.rawValue)
            XCTAssertEqual(ShieldStrings.text(variant.whyKey), why, id.rawValue)
        }
        let sdp = catalog.variant(.stolenDeviceProtection, platform: .ios)!.noteKeys.map(ShieldStrings.text(_:))
        XCTAssertEqual(sdp, ["This may already be on. Just check.", "Changing some settings will take one hour. That's the point."])
        let codeWordSteps = catalog.variant(.familyCodeWord, platform: .ios)!.steps(forOSMajor: 26).map(ShieldStrings.text(_:))
        XCTAssertEqual(codeWordSteps.first, "Decide it together, out loud. Don't type it anywhere, not even here.")
        let carrierNotes = catalog.variant(.carrierLock, platform: .ios)!.noteKeys.map(ShieldStrings.text(_:))
        XCTAssertEqual(carrierNotes, ["Menu names may differ a little.", "If they ask you to make a PIN, keep it to yourself. Don't type it into Family Shield."])
    }

    func testGlobalCopyIsVerbatimFromSpec() {
        XCTAssertEqual(ShieldStrings.text("trust.line"), "Family Shield never asks for passwords, codes or money. It never changes your settings. The only person it asks you to call is Ben.")
        XCTAssertEqual((1...6).map { ShieldStrings.text("rules.\($0)") }, [
            "Hang up and look it up. Call back using a number you find yourself.",
            "Never read a code to anyone. Not the bank, not Apple, not 'Ben'.",
            "No gift cards, crypto or wire transfers for anyone you met online or on the phone.",
            "Real warnings never come with a phone number to call.",
            "Never paste anything into Terminal because a website told you to.",
            "Our family code word. Decide it together, out loud. Don't type it anywhere.",
        ])
        XCTAssertEqual(ShieldStrings.text("selfcheck.footer"), "Family Shield will never ask you to type a password, code or PIN.")
        XCTAssertEqual(ShieldStrings.text("selfcheck.notSure.response"), "That's okay. Ben can help next visit.")
        XCTAssertEqual(ShieldStrings.text("answer.didIt"), "I did it")
        XCTAssertEqual(ShieldStrings.text("answer.notSure"), "Not sure")
        XCTAssertEqual(ShieldStrings.text("answer.notNow"), "Not now")
        XCTAssertEqual(ShieldStrings.text("answer.codeWord.haveOne"), "We have one")
        XCTAssertEqual(ShieldStrings.text("answer.codeWord.notYet"), "Not yet")
        XCTAssertEqual(ShieldStrings.text("home.protected"), "You're protected. Nothing to do.")
        XCTAssertEqual(ShieldStrings.text("pace.doItAllNow"), "Do it all now with Ben")
        XCTAssertEqual(ShieldStrings.text("buildAge.banner"), "Family Shield needs a new version soon. Ask Ben.")
    }

    func testPluralsAndMarkdown() {
        XCTAssertEqual(ShieldStrings.plural("home.toDo", count: 1), "1 thing to do")
        XCTAssertEqual(ShieldStrings.plural("home.toDo", count: 3), "3 things to do")
        XCTAssertEqual(ShieldStrings.plural("home.toDoToday", count: 1), "1 thing to do today.")
        XCTAssertEqual(ShieldStrings.plural("home.moreForLater", count: 2), "2 more for later")
        XCTAssertEqual(ShieldStrings.plural("menubar.toDo", count: 1), "1 to do")
        XCTAssertEqual(ShieldStrings.plain("step.ios.softwareUpdate"), "Open Settings → General → Software Update.")
        XCTAssertEqual(ShieldStrings.text("no.such.key"), "no.such.key")
        XCTAssertFalse(ShieldStrings.contains("no.such.key"))
    }

    // MARK: Links

    func testEveryURLConstantIsHTTPSOrSystemPreferences() throws {
        var checked = 0
        for entry in catalog.entries {
            for (platform, variant) in entry.variants {
                if let url = variant.supportURL {
                    XCTAssertEqual(url.scheme, "https", entry.id.rawValue)
                    XCTAssertNotNil(url.host, entry.id.rawValue)
                    checked += 1
                }
                if let link = variant.deepLink {
                    XCTAssertEqual(link.platform, platform, "deep link platform: \(entry.id.rawValue)")
                }
            }
        }
        for link in DeepLink.allCases {
            if link == .iosAppSettings {
                XCTAssertNil(link.urlString)
                continue
            }
            if link == .iosSettingsHome {
                // The Settings home screen, no pane path (iOS 26 ignores pane paths).
                XCTAssertEqual(link.urlString, "App-prefs:")
                continue
            }
            let string = try XCTUnwrap(link.urlString)
            XCTAssertTrue(string.hasPrefix("x-apple.systempreferences:com.apple."), string)
            XCTAssertNotNil(link.url, string)
            checked += 1
        }
        for service in Services.all {
            if let string = service.officialURLString {
                XCTAssertNotNil(OfficialLinks.httpsURL(string), string)
                XCTAssertNotNil(service.officialURL)
                checked += 1
            }
        }
        for string in OfficialLinks.allStrings {
            XCTAssertNotNil(OfficialLinks.httpsURL(string), string)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 40)
        XCTAssertNil(OfficialLinks.httpsURL("http://example.com"))
        XCTAssertNil(OfficialLinks.httpsURL("App-prefs:root=General"))
        XCTAssertNil(OfficialLinks.httpsURL("https://"))
    }

    func testTelURLKeepsOnlyDigits() {
        XCTAssertEqual(OfficialLinks.telURL("(415) 555-0100")?.absoluteString, "tel:4155550100")
        XCTAssertEqual(OfficialLinks.telURL(" +1 415 555 0100")?.absoluteString, "tel:+14155550100")
        XCTAssertEqual(OfficialLinks.telURL("415;rm -rf")?.absoluteString, "tel:415")
        XCTAssertNil(OfficialLinks.telURL("Ben"))
        XCTAssertNil(OfficialLinks.telURL("1234567890123456"))
    }

    @MainActor
    func testOpenableURLRespectsPlatform() {
        #if os(macOS)
        XCTAssertNil(DeepLink.iosAppSettings.openableURL)
        XCTAssertEqual(DeepLink.macFileVault.openableURL, DeepLink.macFileVault.url)
        #else
        XCTAssertNotNil(DeepLink.iosAppSettings.openableURL)
        XCTAssertNil(DeepLink.macFileVault.openableURL)
        #endif
        XCTAssertEqual(DeepLink.macFirewall.buttonTitleKey, "deeplink.open.mac")
        XCTAssertEqual(DeepLink.iosAppSettings.buttonTitleKey, "deeplink.open.ios")
    }

    func testCatalogRejectsNonHTTPSSupportURL() {
        let json = """
        {"catalogVersion": 1, "checks": [{"id": "sip", "priority": "P0", "tier": "red", "platforms": ["mac"],
          "byPlatform": {"mac": {"kind": "measured", "titleKey": "a", "whyKey": "b", "passKey": "c", "failKey": "d",
          "stepsByOSMajor": {"26": ["e"]}, "supportURL": "http://example.com"}}}]}
        """
        XCTAssertThrowsError(try CheckCatalog.load(from: Data(json.utf8)))
    }

    func testCatalogReportsUnknownIDsInsteadOfCrashing() throws {
        let json = """
        {"catalogVersion": 2, "checks": [{"id": "gmail", "priority": "P0", "tier": "amber", "platforms": ["ios"],
          "byPlatform": {"ios": {"kind": "selfCheck", "titleKey": "a", "whyKey": "b", "passKey": "c", "failKey": "d",
          "stepsByOSMajor": {"26": ["e"]}}}}]}
        """
        let catalog = try CheckCatalog.load(from: Data(json.utf8))
        XCTAssertEqual(catalog.unknownIDs, ["gmail"])
        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertThrowsError(try CheckCatalog.load(from: Data("{".utf8)))
    }

    // MARK: Services (§6.4)

    func testServiceCatalogCoversEveryServiceOnce() {
        XCTAssertEqual(Services.all.map(\.key), ServiceKey.allCases, "one service per key, in spec order")
        let categories: [ServiceKey: AccountCategory] = [
            .gmail: .email, .icloudMail: .email, .outlook: .email, .yahoo: .email, .aol: .email,
            .bank: .money, .creditCard: .money, .paypal: .money, .venmo: .money, .zelle: .money, .cashApp: .money, .brokerage: .money,
            .facebook: .social, .instagram: .social, .whatsapp: .social, .x: .social, .tiktok: .social, .linkedin: .social, .snapchat: .social,
            .amazon: .shopping, .carrierAccount: .shopping, .ssa: .government, .irsIPPin: .government,
            .healthPortal: .health, .creditBureaus: .credit,
        ]
        for service in Services.all {
            XCTAssertEqual(service.category, categories[service.key], service.key.rawValue)
        }
        XCTAssertEqual(Services.service(.carrierAccount)?.linkedChecks, [.carrierLock])
        XCTAssertEqual(Services.service(.creditBureaus)?.linkedChecks, [.creditFreezeEquifax, .creditFreezeExperian, .creditFreezeTransunion])
    }

    func testEveryServiceHasAtLeastOneApplicableStepAndAllCopy() {
        for service in Services.all {
            XCTAssertGreaterThanOrEqual(service.steps.count, 1, service.key.rawValue)
            XCTAssertEqual(Set(service.steps).count, service.steps.count, "duplicate steps: \(service.key.rawValue)")
            XCTAssertTrue(service.stepOverrides.isSubset(of: Set(service.steps)), service.key.rawValue)
            XCTAssertFalse(service.symbolName.isEmpty)
            for key in service.allStringKeys {
                XCTAssertTrue(ShieldStrings.contains(key), "\(service.key.rawValue): missing \(key)")
            }
            if service.officialURLString == nil {
                XCTAssertNotNil(service.whereKey, "no URL means the copy must say where: \(service.key.rawValue)")
            }
            XCTAssertEqual(service.steps.contains(.trustedContact), service.key == .brokerage)
        }
        for step in AccountStep.allCases {
            XCTAssertTrue(ShieldStrings.contains(step.genericCopyKey), step.rawValue)
        }
        XCTAssertEqual(ShieldStrings.text("accounts.step.2fa"), "Turn on two-step sign-in (or a passkey).")
        XCTAssertEqual(ShieldStrings.text("accounts.step.checkup"), "Run the company's own security check.")
        XCTAssertEqual(ShieldStrings.text("service.zelle.where"), "Zelle lives inside your bank's app. Use the bank steps.")
        XCTAssertEqual(ShieldStrings.text("service.bank.where"), "Open your bank's own app, then Settings → Security and Alerts. Never use a link from a text.")
    }

    /// A service's "where" card sits right above its steps (ServiceStepsScreen): it says where
    /// the account lives and never repeats a step's words (SSA and IRS once did, word for word).
    func testServiceWhereNeverRepeatsAStep() {
        func sentences(_ text: String) -> [String] {
            text.lowercased().replacingOccurrences(of: "**", with: "")
                .split(whereSeparator: { ".!?".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.split(separator: " ").count >= 4 }
        }
        for service in Services.all {
            guard let whereKey = service.whereKey else { continue }
            let whereText = ShieldStrings.text(whereKey)
            let stepText = service.steps.map { ShieldStrings.text(service.copyKey(for: $0)).lowercased().replacingOccurrences(of: "**", with: "") }
                .joined(separator: " ")
            // A path ("Settings → [your name] → …") may be repeated by the step that goes there.
            for sentence in sentences(whereText) where !sentence.contains("→") {
                XCTAssertFalse(stepText.contains(sentence), "\(service.key.rawValue): where repeats a step: \(sentence)")
            }
            XCTAssertFalse(whereText.contains("uses the"), "\(service.key.rawValue): say where, not 'uses the … steps'")
        }
    }

    /// A "talk to Ben first" warning card is the one place that says it: no step repeats it
    /// (Advanced Data Protection once said it in the step and again in the card below).
    func testTalkToBenWarningIsSaidOnce() {
        let catalog = CheckCatalog.shared
        var warned = 0
        for id in CheckID.allCases {
            for platform in Platform.allCases {
                guard let variant = catalog.variant(id, platform: platform),
                      variant.noteKeys.contains(where: { ShieldStrings.text($0).contains("Talk to Ben") }) else { continue }
                warned += 1
                for major in [14, 15, 18, 26, 27] {
                    for key in variant.steps(forOSMajor: major) {
                        XCTAssertFalse(ShieldStrings.text(key).contains("Talk to Ben"), "\(id.rawValue) \(platform): \(key)")
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(warned, 2, "Advanced Data Protection on iPhone and Mac")
    }

    /// Every `service.<key>.step.<step>` string must be a declared override (catches typos).
    func testNoOrphanServiceStepStrings() throws {
        let keys = try Self.rawStringCatalog().entries.keys
        for key in keys where key.hasPrefix("service.") && key.contains(".step.") {
            let parts = key.split(separator: ".").map(String.init)
            XCTAssertEqual(parts.count, 4, key)
            guard parts.count == 4, let service = ServiceKey(rawValue: parts[1]).flatMap(Services.service),
                  let step = AccountStep(rawValue: parts[3]) else {
                XCTFail("unknown service step string \(key)")
                continue
            }
            XCTAssertTrue(service.stepOverrides.contains(step), "orphan override \(key)")
        }
    }

    /// Every service step shows a one-sentence "why" under it (ServiceStepsScreen): the
    /// service's own reason when it differs, else the generic `accounts.why.<step>`.
    func testEveryServiceStepHasAWhy() {
        for step in AccountStep.allCases {
            XCTAssertTrue(ShieldStrings.contains(step.genericWhyKey), "missing generic why for \(step.rawValue)")
        }
        var overrides = 0
        for service in Services.all {
            XCTAssertTrue(service.whyOverrides.isSubset(of: Set(service.steps)), "why override for a step the service skips: \(service.key.rawValue)")
            overrides += service.whyOverrides.count
            for step in service.steps {
                let key = service.whyKey(for: step)
                XCTAssertTrue(ShieldStrings.contains(key), "\(service.key.rawValue)/\(step.rawValue): missing \(key)")
                XCTAssertTrue(service.allStringKeys.contains(key), key)
                let text = ShieldStrings.text(key)
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, key)
                XCTAssertFalse(text.contains("**"), "the why line is plain text: \(key)")
                XCTAssertTrue(text.hasSuffix("."), "\(key): \(text)")
                XCTAssertLessThanOrEqual(text.split(separator: " ").count, 30, "keep the why short: \(key)")
                XCTAssertNotEqual(ShieldStrings.plain(service.copyKey(for: step)), text, "why repeats the step: \(key)")
            }
        }
        XCTAssertGreaterThan(overrides, 20)
        XCTAssertEqual(Services.service(.bank)?.whyKey(for: .alerts), "service.bank.why.alerts")
        XCTAssertEqual(Services.service(.bank)?.whyKey(for: .twoFactor), "accounts.why.2fa")
        XCTAssertEqual(ShieldStrings.text("accounts.step.whyLine").replacingOccurrences(of: "{why}", with: "x"), "Why: x")
    }

    /// Every `service.<key>.why.<step>` string must be a declared override (catches typos).
    func testNoOrphanServiceWhyStrings() throws {
        let keys = try Self.rawStringCatalog().entries.keys
        var found = 0
        for key in keys where key.hasPrefix("service.") && key.contains(".why.") {
            found += 1
            let parts = key.split(separator: ".").map(String.init)
            guard parts.count == 4, let service = ServiceKey(rawValue: parts[1]).flatMap(Services.service),
                  let step = AccountStep(rawValue: parts[3]) else {
                XCTFail("unknown service why string \(key)")
                continue
            }
            XCTAssertTrue(service.whyOverrides.contains(step), "orphan why override \(key)")
        }
        XCTAssertGreaterThan(found, 20)
        for key in keys where key.hasPrefix("accounts.why.") {
            XCTAssertNotNil(AccountStep(rawValue: String(key.dropFirst("accounts.why.".count))), "unknown generic why \(key)")
        }
    }

    /// Each step says where to start and what to do; only `unique_pw` may fall back to the
    /// generic copy (it is the same Passwords-app path everywhere).
    func testEveryServiceStepIsSpecific() {
        for service in Services.all {
            for step in service.steps where step != .uniquePassword {
                XCTAssertTrue(service.stepOverrides.contains(step), "\(service.key.rawValue)/\(step.rawValue) uses the generic copy")
            }
            for step in service.steps {
                let text = ShieldStrings.text(service.copyKey(for: step))
                // "Open the official page" is the button on this screen: only where there is one.
                if text.contains("Open the official page") {
                    XCTAssertNotNil(service.officialURL, "\(service.key.rawValue)/\(step.rawValue) points at a button that isn't there")
                }
                // Family Shield never collects a password, code or PIN (H1).
                if text.contains("Family Shield") {
                    XCTAssertTrue(text.contains("Never type it into Family Shield"), "\(service.key.rawValue)/\(step.rawValue): \(text)")
                }
                XCTAssertNil(text.range(of: "account number", options: .caseInsensitive), "\(service.key.rawValue)/\(step.rawValue)")
            }
        }
    }

    func testCategoriesMapToRollups() {
        XCTAssertNil(AccountCategory.credit.rollup)
        XCTAssertEqual(AccountCategory.allCases.compactMap(\.rollup), CheckID.accountRollups)
        for id in CheckID.accountRollups { XCTAssertNotNil(AccountCategory(rollup: id)) }
        for category in AccountCategory.allCases { XCTAssertTrue(ShieldStrings.contains(category.nameKey)) }
    }

    /// Face ID / Touch ID wording (docs/verified/AUDITED.md §1 #8): every swapped key is used by
    /// the catalog, both variants exist, and only `.unknown` keeps the copy that names both.
    func testBiometryStepVariants() {
        var used = Set<String>()
        for entry in catalog.entries {
            for platform in entry.platforms {
                guard let variant = catalog.variant(entry.id, platform: platform) else { continue }
                for major in [18, 26, 27] { used.formUnion(variant.steps(forOSMajor: major)) }
            }
        }
        for (key, variant) in Biometry.stepVariants {
            XCTAssertTrue(used.contains(key), "\(key) is not a catalog step")
            for swapped in [variant.faceID, variant.touchID] {
                XCTAssertTrue(ShieldStrings.contains(swapped), swapped)
            }
            XCTAssertEqual(Biometry.unknown.stepKey(key), key)
            XCTAssertFalse(ShieldStrings.text(variant.faceID).contains("Touch ID"), variant.faceID)
            XCTAssertFalse(ShieldStrings.text(variant.touchID).contains("Face ID"), variant.touchID)
        }
        XCTAssertEqual(ShieldStrings.plain(Biometry.touchID.stepKey("step.ios.faceIDPasscode")),
                       "Open Settings → Touch ID & Passcode.")
        XCTAssertEqual(ShieldStrings.plain(Biometry.faceID.stepKey("step.ios.faceIDPasscode")),
                       "Open Settings → Face ID & Passcode.")
        XCTAssertEqual(Biometry.touchID.stepKey("step.ios.softwareUpdate"), "step.ios.softwareUpdate")
        XCTAssertEqual(Biometry.from(.touchID), .touchID)
        XCTAssertEqual(Biometry.from(.faceID), .faceID)
        XCTAssertEqual(Biometry.from(.none), .unknown)
    }

    func testCarrierStrings() {
        for carrier in Carrier.allCases {
            XCTAssertTrue(ShieldStrings.contains(carrier.nameKey), carrier.rawValue)
            XCTAssertFalse(carrier.stepKeys.isEmpty)
            for key in carrier.stepKeys { XCTAssertTrue(ShieldStrings.contains(key), key) }
            XCTAssertFalse(ShieldStrings.contains("carrier.\(carrier.rawValue).step.\(carrier.stepKeys.count + 1)"),
                           "step count out of date for \(carrier.rawValue)")
        }
    }

    // MARK: Strings hygiene

    /// §13.1: no string contains a digit sequence that looks like a phone number (H6: phone
    /// numbers are never shown from data; "Call Ben" uses the contact picked on the device).
    func testNoStringLooksLikeAPhoneNumber() throws {
        let raw = try Self.rawStringCatalog()
        XCTAssertGreaterThan(raw.entries.count, 300)
        let patterns = [
            #"\(?\b\d{3}\)?[\s.\-]\d{3}[\s.\-]\d{4}\b"#,   // (800) 555-1212, 800-555-1212
            #"\b1[\s.\-]\d{3}[\s.\-]\d{3}"#,                // 1-888-397…
            #"\+\d"#,                                        // +1…
            #"\d{7,}"#,                                      // 8005551212
        ]
        for (key, entry) in raw.entries {
            for value in [entry.single, entry.one, entry.other].compactMap({ $0 }) {
                for pattern in patterns {
                    XCTAssertNil(value.range(of: pattern, options: .regularExpression), "\(key): \(value)")
                }
            }
        }
    }

    func testStringsNeverAskForSecretsOrBanWords() throws {
        let raw = try Self.rawStringCatalog()
        let banned = ["App-prefs:", "antivirus", "virus", "CRITICAL", "%", "delete"]
        for (key, entry) in raw.entries {
            for value in [entry.single, entry.one, entry.other].compactMap({ $0 }) {
                for word in banned where word != "%" {
                    XCTAssertNil(value.range(of: word, options: .caseInsensitive), "\(key) contains \(word)")
                }
                // Only format specifiers, never percentages (§10 "no percentages").
                let stripped = value.replacingOccurrences(of: "%lld", with: "")
                XCTAssertFalse(stripped.contains("%"), "\(key): \(value)")
            }
        }
    }

    /// §12.4: every displayed URL comes from DeepLinks.swift, Services.swift or catalog.json.
    /// `URL(string:` or an http(s) literal anywhere else in app or ShieldCore code fails.
    /// Exception: `Version/` holds the SOFA feed endpoints (network inputs, never displayed).
    func testURLConstantsLiveOnlyInAllowedFiles() throws {
        let root = Self.repoRoot
        let scanRoots = ["ShieldCore/Sources", "ShieldiOS", "ShieldMac", "ShieldShare"].map { root.appendingPathComponent($0) }
        let fm = FileManager.default
        guard fm.fileExists(atPath: scanRoots[0].path) else {
            throw XCTSkip("sources not readable from this test host")
        }
        let allowedFiles: Set<String> = ["DeepLinks.swift", "Services.swift"]
        var scanned = 0
        for scanRoot in scanRoots where fm.fileExists(atPath: scanRoot.path) {
            guard let enumerator = fm.enumerator(at: scanRoot, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                scanned += 1
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                let text = try String(contentsOf: url, encoding: .utf8)
                for (number, line) in text.components(separatedBy: .newlines).enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { continue }
                    XCTAssertFalse(line.contains("App-prefs:") && url.lastPathComponent != "DeepLinks.swift", "\(relative):\(number + 1) App-prefs: is allowed only in DeepLinks.swift")
                    let hasURL = line.contains("URL(string:") || line.contains("https://") || line.contains("http://")
                    guard hasURL else { continue }
                    let allowed = allowedFiles.contains(url.lastPathComponent)
                        || relative.hasPrefix("ShieldCore/Sources/ShieldCore/Version/")
                    XCTAssertTrue(allowed, "\(relative):\(number + 1): URL constant outside DeepLinks/Services/catalog")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 10)
    }

    // MARK: Helpers

    static var repoRoot: URL {
        // .../ShieldCore/Tests/ShieldCoreTests/CatalogLintTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The String Catalog JSON: the source file when readable, else the bundled raw copy.
    static func rawStringCatalog() throws -> RawStringCatalog {
        let source = repoRoot.appendingPathComponent("ShieldCore/Sources/ShieldCore/Catalog/Strings/Localizable.xcstrings")
        if let data = try? Data(contentsOf: source), let parsed = RawStringCatalog(data: data) {
            return parsed
        }
        guard !RawStringCatalog.shared.entries.isEmpty else {
            throw XCTSkip("String Catalog source not readable from this test host")
        }
        return RawStringCatalog.shared
    }
}

extension Array where Element == CheckID {
    func sortedByCatalog(_ catalog: CheckCatalog) -> [CheckID] {
        sorted { (catalog[$0]?.order ?? 0) < (catalog[$1]?.order ?? 0) }
    }
}
