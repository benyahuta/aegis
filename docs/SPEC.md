# Family Shield: Final Build Spec (v1)

Status: FINAL. Date: 2026-10-22. Owner: Ben.
Base: the "max-protection" proposal, which won all three judge votes. It adds ideas from "max-simplicity" and "feasibility" and fixes every fatal flaw the judges raised. `docs/DECISIONS.md` explains each choice in plain language. Research sources are in `docs/research/`. `docs/REQUIREMENTS-ADDENDUM.md` (online accounts) is part of this spec; see §6.4.

Markers used below: **[V]** = verified in research. **[U]** = unverified, and must be confirmed in the Week-1 spikes (§15) before anyone depends on it.

---

## 0. Hard rules (every builder agent must follow these; a change that breaks one is rejected)

| # | Rule |
|---|---|
| H1 | **$0.** No paid service, no paid API, no Fly.io. Supabase is a documented fallback only and is not deployed in v1. |
| H2 | **Never handle secrets.** No field anywhere accepts a password, passcode, PIN, 2FA code, account number, SSN, IP PIN, carrier PIN, or the family code word. The app never signs in to anything for anyone. |
| H3 | **Read-only on devices.** The app never changes a setting. It shows where the setting is, opens the Settings pane where that is allowed, and asks the person to confirm. |
| H4 | **Zero third-party code.** No SwiftPM, CocoaPods or Carthage dependencies. Apple frameworks only. CI uses only `curl`, `jq` and `openssl`, with Actions pinned by commit SHA. |
| H5 | **Only pass/fail/unknown leaves a device.** The sync payload is exactly the fields in §8. No OS versions, models, app names, paths, service names, account names, message text or verdicts. |
| H6 | **The server never instructs a device.** Every string, URL and phone number the family sees is compiled into the app and chosen by enum. Feeds and records carry only numbers, model IDs, enum IDs and booleans. |
| H7 | **No false green.** Errors, timeouts, missing data and stale data map to `unknown` (grey), never to `pass`. |
| H8 | **No download habit.** The family is never asked to download an app, open a DMG, use Terminal or bypass Gatekeeper. Ben installs and updates the Mac app in person or by AirDrop. |
| H9 | **"Call Ben" is the only action for anything scary.** The app never tells anyone to delete anything. |

---

## 1. Product summary

Family Shield is a free iPhone and Mac app that Ben installs for each relative. It does three jobs, in this order of importance:

1. **"Is this a scam?"** At the moment of doubt, the person pastes a text, picks a screenshot, or answers four questions about a phone call. The app gives an on-device second opinion: *Danger*, *Be careful* or *No common signs found* (grey, never green). Every result has a big **Call Ben** button.
2. **"Am I patched?"** For each device, the app compares the actual OS version against the minimum patched version for that OS line and that model. CVE-2026-86950 showed that "auto-update is on" does not mean "patched". On the Mac it also reads posture: FileVault, Gatekeeper, SIP, failed updates, MDM and so on.
3. **A short, paced, guided checklist** covering what an app can't measure: Stolen Device Protection, recovery contact, carrier SIM lock, credit freezes, a family code word, and the person's **online accounts** (email, money, social, shopping and government). The person marks each item "I did it", and it is labeled "confirmed by you".

Ben sees a **Family** tab in his own copy of the app: people → devices → checks, each shown as ✓ / ✗ / ? with a "measured" or "confirmed by you" badge. Results sync through **CloudKit**, with one private zone per relative, shared only with Ben. There is no server, no sign-in and no cost.

---

## 2. Components

| # | Component | Platform / min OS | Bundle ID | Distribution | Sandbox | Priority |
|---|---|---|---|---|---|---|
| C1 | **ShieldCore**: local Swift package with the shared logic | iOS 18.0 / macOS 14.0 | (library; test bundle `org.example.aegis.core.tests`) | Linked into C2–C4 | n/a | P0 |
| C2 | **Family Shield for iPhone** | iOS 18.0+ (iPhone only) | `org.example.aegis.ios` | TestFlight external testers, **invited by email** | Yes (required) | P0 |
| C3 | **Family Shield for Mac**: window, MenuBarExtra, and itself as the login item | macOS 14.0+ | `org.example.aegis.mac` | Developer ID, Hardened Runtime, notarized. **Ben installs in person or by AirDrop.** | **No** (required for checks [V]) | P0 |
| C4 | **Family tab** (Ben's dashboard), inside C2 and C3 | as host | (same apps) | — | — | P0 |
| C5 | iOS Share Extension "Check with Family Shield" | iOS 18.0+ | `org.example.aegis.ios.share` | Inside C2 | Yes | P1 |
| C6 | Version feed mirror: GitHub Actions cron → GitHub Pages, Ed25519-signed | infra | n/a | **Public** repo `family-shield-feed` that holds only feed scripts | n/a | P1 |
| C7 | Ed25519 signing tool (`tools/feedsign`, a Swift script using CryptoKit; key held in Ben's login Keychain) | macOS 14 | n/a | Runs on Ben's Mac only | n/a | P1 (also signs the Mac version manifest) |
| C8 | Safari content blocker (a small hand-curated list of current-event lookalike domains, not a 20k-rule phishing feed) | iOS 18.0+ | `org.example.aegis.ios.blocker` | Inside C2 | Yes | P2 |
| C9 | SMS filter extension (offline rules; never touches 2FA or transaction texts) | iOS 18.0+ | `org.example.aegis.ios.smsfilter` | Inside C2 | Yes | P2 |

Shared identifiers:
- iCloud container: `iCloud.org.example.aegis`, one container for both platforms.
- App Group (P1, for the Share Extension): `group.org.example.aegis`.
- Signing: C2 uses Apple Development / Apple Distribution. C3 uses Developer ID Application with a **Developer ID provisioning profile** that includes the iCloud container [V that this is allowed; U until the spike].
- There is **no separate helper executable** on the Mac. The main app registers itself with `SMAppService.mainApp` and runs as an `LSUIElement`-style MenuBarExtra app with an optional window. This fixes the judges' "ShieldAgent helper" flaw.

---

## 3. Repository layout

```
family-shield/
  .gitignore                 # .env*, *.p8, *.p12, *.mobileprovision, .insforge/, xcuserdata/, DerivedData/, build/
  FamilyShield.xcodeproj     # one project; targets: ShieldiOS, ShieldMac, (P1) ShieldShare, (P2) ShieldBlocker, ShieldSMSFilter
  ShieldCore/                # local Swift package (Package.swift, swift-tools-version 6.0, zero dependencies)
    Sources/ShieldCore/
      Catalog/               CheckID.swift, CheckCatalog.swift, Tier.swift, Strings/ (en.lproj Localizable.xcstrings),
                             catalog.json (copy keys, tiers, steps per OS major, URLs), Services.swift (online-account services)
      Version/               SOFAModels.swift (defensive Decodable), VersionEvaluator.swift, BundledMinimums.swift,
                             FeedStore.swift (ETag fetch + cache + raise-only), snapshot/ios_min.json, mac_min.json
      Scam/                  Normalizer.swift, Extractor.swift (NSDataDetector), ScamRules.swift, Rules/*.swift,
                             BrandDomains.swift, Verdict.swift, OCR.swift (VNRecognizeTextRequest), CallQuiz.swift
      Sync/                  ResultSink.swift (protocol), CloudKitSink.swift, OwnerStore.swift, Records.swift, SyncQueue.swift
      Evaluate/              StatusEngine.swift (local status, pacing, reminders), SelfReportStore.swift
      Notify/                LocalNotifier.swift
      Support/               Log.swift (os.Logger, private only), DateDay.swift, Clock.swift (injectable)
    Tests/ShieldCoreTests/   VersionEvaluatorTests, FeedDecodeTests (captured fixtures), ScamCorpusTests,
                             StatusEngineTests, RecordsTests, CatalogLintTests
    Tests/Fixtures/          sofa_ios_v2_2026-10-22.json, sofa_macos_v2_2026-10-22.json, rollback_*.json, stale_*.json,
                             scam_corpus.jsonl (>= 80 cases), benign_corpus.jsonl (>= 40 cases)
  ShieldiOS/                 App/, Screens/, Components/, Checks/ (iOSChecks.swift), Info.plist, ShieldiOS.entitlements
  ShieldMac/                 App/, Screens/, MenuBar/, Checks/ (MacChecks/*.swift, ProcessRunner.swift), Info.plist,
                             ShieldMac.entitlements
  ShieldShare/               (P1) ShareViewController.swift
  UITests/                   ShieldiOSUITests (screenshot matrix), ShieldMacUITests
  feed/                      (P1) build.sh, schema.json, reduce.jq, README.md
  .github/workflows/         (P1) feed.yml
  tools/                     feedsign/ (P1), deeplink-test.sh (opens each x-apple.systempreferences URL, checks window title)
  docs/                      SPEC.md, DECISIONS.md, RUNBOOK.md (incident runbook), research/
```

**Swift settings:** Swift 6 toolchain (Xcode 26.6), language mode 6, strict concurrency complete. Build with Xcode 26.6 now. Move to Xcode 27 only after the release Mac reaches macOS 26.6+. Nothing in P0 needs the 27 SDK.

**Frameworks (Apple only):** SwiftUI, Foundation, CloudKit, LocalAuthentication, Vision (`VNRecognizeTextRequest`, which covers both iOS 18 and macOS 14; the newer `RecognizeTextRequest` needs macOS 15), NaturalLanguage, CryptoKit, UserNotifications, BackgroundTasks (iOS), ServiceManagement (Mac), IOKit / `sysctlbyname` (Mac), ContactsUI (`CNContactPickerViewController` on iOS, which needs no Contacts permission; on Mac, `CNContactPicker`), PhotosUI (`PhotosPicker`, which needs no library permission), Network, `os`. **P1:** FoundationModels, gated by `@available(iOS 26, macOS 26, *)` and `SystemLanguageModel.default.availability`.

---

## 4. Entitlements and Info.plist

### C2: iOS app (`ShieldiOS.entitlements`)
```
com.apple.developer.icloud-services          = [CloudKit]
com.apple.developer.icloud-container-identifiers = [iCloud.org.example.aegis]
aps-environment                               = production   (needed for CKDatabaseSubscription silent pushes to Ben; P0 ok to include)
com.apple.security.application-groups         = [group.org.example.aegis]   (P1, with C5)
```
Info.plist: `CKSharingSupported = YES`; `UIBackgroundModes = [fetch, remote-notification]`; `BGTaskSchedulerPermittedIdentifiers = [org.example.aegis.ios.refresh]`; `ITSAppUsesNonExemptEncryption = NO`. There are no usage-description strings for Contacts or Photos, because the pickers need no permission. Do not add `NSContactsUsageDescription`.

### C3: Mac app (`ShieldMac.entitlements`)
```
com.apple.security.app-sandbox                = (absent / false)
com.apple.developer.icloud-services          = [CloudKit]
com.apple.developer.icloud-container-identifiers = [iCloud.org.example.aegis]
com.apple.developer.aps-environment           = production
com.apple.developer.team-identifier           = <TEAM_ID>  (Xcode adds this)
```
Hardened Runtime is on, with **no** exceptions: no JIT, no unsigned-memory, no disable-library-validation, no DYLD env. Info.plist: `CKSharingSupported = YES`; `LSUIElement = YES` (menu-bar app; the window opens from the menu); `LSMinimumSystemVersion = 14.0`.

### C5: Share Extension (P1)
Only the App Group entitlement. **No CloudKit and no network.** The extension runs rules and OCR, then hands off to the main app through the App Group only for the optional LLM step, and stores nothing.

---

## 5. ShieldCore: modules and exact behavior (C1, P0)

### 5.1 `CheckID` and `CheckCatalog`
- `enum CheckID: String, CaseIterable, Codable`. The raw values are exactly the IDs in §6. **This enum is the allowlist.** `CloudKitSink` refuses to write any other value, and `CatalogLintTests` fails if `catalog.json` and the enum differ.
- `enum Status: Int { unknown = 0, pass = 1, fail = 2 }`. This is the wire format. "Not sure" (self-report) is stored locally as `.notSure` and written as `unknown`.
- `enum Source: Int { measured = 0, selfReported = 1 }`.
- `enum Tier { red, amber, yellow, info }`. The tier is computed on the device from `CheckID` plus context and never synced. Red means **only** "an actively exploited bug and the fix is out", "MDM you don't expect", "no passcode", or "Gatekeeper/SIP off".
- `catalog.json` has one entry per check: `titleKey`, `whyKey`, `passKey`, `failKey`, `stepsByOSMajor { "18": [...], "26": [...], "27": [...] }`, `deepLink` (enum `DeepLink`), `supportURL` (Apple or official page), `tier`, `platforms`, `priority`, `paceGroup`. The JSON is compiled into the bundle. Nothing is downloaded.

### 5.2 `VersionEvaluator` (P0)
Inputs: platform; OS version (`ProcessInfo.processInfo.operatingSystemVersion`); device identifier (iOS: `utsname.machine`, or `SIMULATOR_MODEL_IDENTIFIER` on Simulator; Mac: `hw.target` board ID for `SupportedDevices`, plus `hw.model` for `Models`); feed (optional); now.

Algorithm:
1. `bundledMin[platform][major]` comes from `BundledMinimums.swift`, dated 2026-10-22:
   - iOS: `27 → 27.0.1`, `26 → 26.7.1`, `18 → 18.7.10` for `iPhone11,2/4/6/8` (XS/XS Max/XR), and `18 → 18.7.8` for other iPhone models on 18. iPhone 8/X (`iPhone10,*`) → device unsupported.
   - macOS: `27 → 27.0.1`, `26 → 26.7.1`, `15 → 15.8.1`, `14 → 14.8.9`. macOS 13 and earlier → unsupported.
   - Bundled `exploitedUnpatchedBelow`: iOS 26.7.1, macOS 26.7.1, macOS 15.8.1 (CVE-2026-86950).
2. `feedTarget` = the highest `ProductVersion` in `OSVersions[major].SecurityReleases[]` whose `SupportedDevices` contains this identifier, or whose `DeviceScope == "universal"` and the major's device list includes it [V].
3. **Effective minimum = max(bundledMin, lastGoodCachedMin, feedTarget).** This is the raise-only rule. A feed that would lower any major's minimum below the cached or bundled value is rejected as a whole. In that case the app keeps the cache and logs `feed.rejected` privately.
4. Judge by version comparison only, never by whether CVEs are listed (27.0.1 lists 0 CVEs [V]). "Actively exploited" = any `SecurityReleases` entry above the device's version with a non-empty `ActivelyExploitedCVEs`, or a bundled `exploitedUnpatchedBelow` that applies.
5. Freshness, based on the age of the last good feed:
   - Under 7 days: normal.
   - 7–30 days: normal, plus "Last checked N days ago".
   - Over 30 days, or never fetched: if the device is **below** the bundled minimum → `fail` (still true). Otherwise → `unknown` ("Can't confirm. Check Software Update.").
6. Device support: the model is missing from every patched major → `device_supported = fail` (replace). The model's highest major is not the current one but is still patched → `pass`, with a local amber "aging" note shown to Ben only.

`FeedStore` (P0, direct SOFA):
- GET `https://sofafeed.macadmins.io/v2/ios_data_feed.json` (iOS) or `.../macos_data_feed.json` (Mac).
- Headers: `User-Agent: FamilyShield/<version> (+https://github.com/<ben>/family-shield-feed)` and `If-None-Match: <etag>`.
- Timeout 15 s. At most one fetch per 6 h.
- Decode defensively:
  - `CVEs` may be an Int, an object map or an array.
  - `Build` may be null.
  - Unknown keys are ignored.
  - Any decode failure means the fetch is ignored.
- Cache the last good copy in Application Support. A bundled snapshot is the last resort.
- **P1:** switch the primary URL to the GitHub Pages mirror (C6), require a valid Ed25519 signature from one of the two pinned public keys, and fall back to SOFA direct, then to the cache.

### 5.3 `ScamRules` (P0)
Pipeline:
1. Normalize: NFKC; strip zero-width (U+200B–U+200F, U+2060, U+FEFF) and bidi controls (U+202A–U+202E, U+2066–U+2069), and every other invisible format or default-ignorable character (soft hyphen, invisible operators, variation selectors, tag characters, Hangul fillers), counting the ones hidden inside words; cap at 8,000 characters.
2. Extract URLs and phone numbers with `NSDataDetector`. For screenshots, OCR runs first.
3. Apply weighted rules. Each rule has a stable `RuleID` and a plain-language reason key.
4. Score → verdict.

| RuleID | Signal | Weight |
|---|---|---|
| `brand_link_mismatch` | Brand named (Apple, USPS, IRS, Amazon, PayPal, bank names, Medi-Cal, E-ZPass/FasTrak, carrier names, etc.) and a link whose registrable domain isn't on that brand's allowlist (`BrandDomains.swift`) | 5 |
| `lookalike_domain` | Punycode `xn--`, mixed script, or a skeleton that matches an allowlisted brand domain | 5 |
| `asks_for_code` | Asks for a code, PIN, password or verification number ("read me the code", "verify your account") | 5 |
| `pay_unusual` | Gift card, crypto, Bitcoin ATM, wire, Zelle/Venmo/Cash App "to protect your money", "safe account" | 5 |
| `ai_injection` | Text aimed at an AI ("ignore previous", "you are", "output SAFE", "this message is verified") | 5 |
| `remote_access` | AnyDesk, TeamViewer, "let me connect to your computer", "install this app" | 5 |
| `paste_terminal` | "Open Terminal", "paste this command", "press Command-Space then…" (ClickFix) | 5 |
| `warning_with_phone` | A security or virus "warning" that includes a phone number | 4 |
| `new_number_family` | "Hi Mom/Dad", "new number", "lost my phone" | 3 |
| `toll_delivery_tax_lure` | Unpaid toll, package held, IRS/tax refund, Medi-Cal/benefit, Ahold/grocery refund | 3 |
| `link_shortener` | bit.ly, tinyurl, etc., or an IP-address URL | 2 |
| `odd_tld` | `.top .xyz .click .icu .cyou .buzz .sbs .rest` (list in code) | 2 |
| `urgency_secrecy` | "within 24 hours", "final notice", "don't tell anyone", "suspended" | 2 |
| `romance_investment` | Guaranteed returns, crypto platform, "my uncle at the exchange" | 3 |

Verdict: any rule with weight 5, or a total ≥ 6 → `danger`. Total 3–5 → `beCareful`. Otherwise → `noCommonSignsFound` (grey). There is never a "safe" verdict. Reasons shown are the top 3 fired rules by weight, using compiled strings only.

**Call quiz ("Someone called me", P0):** four big-button questions.
1. Who did they say they were? (Bank / Government / Apple or Microsoft / Family member / Police or court / Other)
2. What did they want? (Code / Money moved / Gift card or crypto / Remote access to computer / Personal info / Nothing yet)
3. Did they say to keep it secret or act fast? (Yes / No)
4. Did *you* call *them* at a number you looked up yourself? (Yes / No)

Any "Code", "Money moved", "Gift card or crypto" or "Remote access" answer → `danger`. A Government, Police or Apple/Microsoft claim with "No" to Q4 → `danger`. Anything else → `beCareful`. Never grey for calls.

**Rules for the model (P1):** `final = max(rules, llm)`. Any error, refusal, guardrail hit or timeout over 5 s → at least `beCareful`. Message text goes into the prompt only as a delimited untrusted-data block. Model prose is never shown.

Storage: none. Input, OCR text and verdict live only in memory for the life of the screen.

### 5.4 `StatusEngine` (P0)
- Runs checks and merges them with self-reports. Each self-report expires after 90 days, then becomes `unknown` with a re-ask.
- Computes the Home state:
  - "You're protected. Nothing to do." when nothing is red or amber in the active pace group.
  - Until this launch's first measured checks finish, never "protected" (H7): with nothing else to do, Home says "Checking now. One moment." in grey and the menu bar says "Checking".
  - Otherwise "N thing(s) to do", with **one Next-step card**, the most urgent first, and the rest collapsed as "N more for later".
- **Pacing of self-checks** (fixes the long-onboarding problem):
  - **Group 1** (shown at first run): `auto_updates`, `stolen_device_protection`, `recovery_contact`, `screen_unknown`, `find_my`, `family_code_word`.
  - **Group 2** (unlocks 3 days after Group 1 is answered): `carrier_lock`, `credit_freeze_equifax`, `credit_freeze_experian`, `credit_freeze_transunion`.
  - **Group 3**: the online-accounts checklist (§6.4). Unlocks as soon as the person picks at least one service, and every picked service shows up that day (changed 2026-10-23 after Ben saw nothing for a week). Home still shows one Next step at a time.
  - Ben can unlock all groups during in-person setup with a "Do it all now with Ben" toggle in About, which is local.
- Reminders: one local notification per newly failing red or amber item, plus one reminder 3 days later, then silence until the state changes. Green sends nothing. News alone never notifies; an alert fires only when this device is affected.

### 5.5 `ResultSink` and `CloudKitSink` (P0; see §8)
`protocol ResultSink { func upsert(device: DeviceInfo, results: [CheckResult]) async throws; func leave() async throws }`. `CloudKitSink` implements it. A `SupabaseSink` (§9.2) can replace it in about half a day if the CloudKit spike fails.

### 5.6 Logging
`os.Logger(subsystem: "org.example.aegis", category: ...)`. Every interpolation is `privacy: .private`, except for enum raw values. Never log message text, OCR text, labels, record contents, URLs from user input or tool output.

---

## 6. Shared check catalog

Columns: **ID** (wire value) · **Platform** · **Pri** · **Title** · **Pass copy** · **Fail copy** · **How detected** · **Fix link** · **Tier on fail**.
Deep-link legend:
- **iOS:** fix cards open the Settings app's home screen with the bare `App-prefs:` URL (no pane path: iOS 26 ignores pane paths, tested on the iOS 26.5 simulator). If iOS refuses it, the card falls back to `UIApplication.openSettingsURLString` (Family Shield's own Settings page). Each card always also shows the written path ("Open Settings → General → Software Update"). App Review risk: guideline 2.5.1 (non-public URL scheme); see APP_REVIEW_NOTES.md.
- **Mac:** the `x-apple.systempreferences:` URLs verified on macOS 26.5.1 [V] (`ux-older-adults.md` §2.1). Every card also shows the written path, because a wrong link fails silently.

### 6.1 iPhone, measured (no permissions)

| ID | Pri | Title | Pass copy | Fail copy | How detected | Fix link | Tier |
|---|---|---|---|---|---|---|---|
| `os_patched` | P0 | iPhone updates | "Your iPhone has the latest safety fixes." | "Please update your iPhone today. Apple fixed a problem that criminals are already using." (exploited) / "An update with safety fixes is ready." (not exploited) | §5.2 | Settings → General → Software Update. Note: "If you see iOS 27.0.1 or iOS 26.7.1 (or newer), either one is fine." (iOS 27.0 is superseded by 27.0.1, Apple 100100, 2026-09-28) | Red if exploited, otherwise amber |
| `device_supported` | P0 | iPhone age | "Apple still sends safety fixes for this iPhone." | "Apple no longer sends safety fixes for this iPhone. Talk to Ben about a newer one." | §5.2 step 6 | none (Call Ben) | Amber |
| `passcode_set` | P0 | Passcode | "Your iPhone has a passcode." | "Your iPhone has no passcode. Anyone who picks it up can open it." | `LAContext().canEvaluatePolicy(.deviceOwnerAuthentication)`; `LAError.passcodeNotSet` → fail; other errors → unknown | Settings → Face ID & Passcode | Red |
| `biometrics_enrolled` | P0 | Face ID / Touch ID | "Face ID or Touch ID is set up." | "Set up Face ID or Touch ID. It protects you if your iPhone is stolen." | `.deviceOwnerAuthenticationWithBiometrics`; `biometryNotEnrolled` → fail; `biometryNotAvailable` → unknown | Settings → Face ID & Passcode → **Set Up Face ID** (Touch ID & Passcode → **Add a Fingerprint** on iPhone SE / iPhone Duo; the step names the row for this iPhone's `LAContext.biometryType`, generic copy names both) | Amber |
| `app_build_fresh` | P0 | (Ben only) App build age | — | Family copy at day 60+: "Family Shield needs a new version soon. Ask Ben." | Embedded build date; ≥ 60 days → fail | none | Info (family banner at 60 days) |

### 6.2 Mac, measured (unsandboxed, as the user, no admin, no Full Disk Access, no prompts)

All child processes run through `ProcessRunner`: an absolute path, a fixed argument array, no shell, a 10 s timeout, stdout and stderr captured and capped at 64 KB. A non-zero exit, timeout or parse failure → `unknown`.

| ID | Pri | Title | Pass copy | Fail copy | How detected | Fix link | Tier |
|---|---|---|---|---|---|---|---|
| `os_patched` | P0 | Mac updates | "Your Mac has the latest safety fixes." | "Please update your Mac today. Apple fixed a problem that criminals are already using." / "An update with safety fixes is ready." | `operatingSystemVersion` + `sysctlbyname("hw.target")` → §5.2 | `x-apple.systempreferences:com.apple.Software-Update-Settings.extension` | Red if exploited, otherwise amber |
| `os_update_stuck` | P0 | Update trouble | (not shown) | "Your Mac tried to update and couldn't. Please call Ben." | `CFPreferencesCopyAppValue("DDMPersistedErrorKey", "com.apple.SoftwareUpdate")`: count ≥ 3 with timestamp within 14 days → fail [V] | Software Update link | Amber |
| `beta_catalog` | P0 | (Ben only) Beta updates | — | Ben only: "This Mac is on beta updates." | SoftwareUpdate `CatalogURL` contains "seed" or "beta" [U: verify key], or `/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate CatalogURL`; missing → pass | Software Update link | Info |
| `device_supported` | P0 | Mac age | "Apple still sends safety fixes for this Mac." | "Apple no longer sends safety fixes for this Mac. Talk to Ben." | SOFA `Models[hw.model].OSVersions` | none | Amber |
| `auto_updates` | P0 | Automatic updates | "Automatic updates are on." | "Turn on automatic updates so fixes install by themselves." | SoftwareUpdate prefs `AutomaticallyInstallMacOSUpdates`, `CriticalUpdateInstall`, `AutomaticCheckEnabled`; a missing key = on [V]. Never implies patched. | Software Update link → "Automatic Updates" | Amber |
| `filevault` | P0 | FileVault (disk lock) | "Your Mac's files are locked if it's lost." | "Turn on FileVault so no one can read your files if your Mac is lost. Pick the option to unlock with your Apple Account." | `/usr/bin/fdesetup isactive` exit 0 = on, 1 = off [V] | `...PrivacySecurity.extension?FileVault` | Amber |
| `gatekeeper` | P0 | App safety check | "Your Mac checks apps before they open." | "A safety setting that checks apps is off. Please call Ben." | `/usr/sbin/spctl --status` → "assessments enabled" | `...PrivacySecurity.extension?Security` | Red |
| `sip` | P0 | System protection | "Your Mac's system is protected." | "A built-in system protection is off. Please call Ben." | `/usr/bin/csrutil status` → "enabled" | none (Call Ben) | Red |
| `xprotect_current` | P0 | Apple's malware protection | "Apple's built-in malware protection is up to date." | "Apple's built-in malware protection is out of date. Updating your Mac usually fixes this." | `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist` `CFBundleShortVersionString` ≥ feed `XProtectPayloads` version; no feed → unknown | Software Update link | Amber |
| `screen_lock` | P0 | Screen lock | "Your Mac locks when you step away." | "Set your Mac to ask for your password right after it sleeps." | `/usr/sbin/sysadminctl -screenLock status`; parse **stderr**; "immediate" or ≤ 5 s → pass [V] | `x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension` | Amber |
| `find_my` | P0 | Find My Mac | "Find My is on. You can find this Mac if it's lost." | "Turn on Find My so you can find this Mac if it's lost." | `~/Library/Preferences/MobileMeAccounts.plist` → `Accounts[].Services[]` where `Name == "FIND_MY_MAC"` → `Enabled`. Read only that flag, drop the dictionary immediately, never log or sync anything else from the file [V] | `x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud` | Amber |
| `firewall` | P0 | Firewall | "The firewall is on." | "Turning on the firewall adds a little extra protection." | `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` | `x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall` (opens Network only; the copy says "then click **Firewall**") | Yellow (advisory, never red) |
| `remote_access_off` | P0 | Remote access | "No one can connect to this Mac from outside." | "Remote access to this Mac is on. If you didn't turn it on, call Ben." | `NWConnection` TCP to 127.0.0.1 on ports 22, 5900, 445 and 548, each with a 300 ms timeout; any accepted → fail | `x-apple.systempreferences:com.apple.Sharing-Settings.extension` | Yellow; **red** if port 5900 is open and `os_patched` fails for CVE-2026-65400 |
| `mdm_unexpected` | P0 | Device management | "No one else is managing this Mac." | "This Mac is being managed by an organization. If you didn't expect that, please call Ben." | `/usr/bin/profiles status -type enrollment` → "MDM enrollment: Yes" → fail (Ben can mark "expected" locally on his own Mac only) | `x-apple.systempreferences:com.apple.Profiles-Settings.extension` | Red |
| `time_machine` | P1 | Backup | "Your Mac is backing up." | "Set up a backup so you never lose your photos." | `/usr/bin/tmutil destinationinfo` has ≥ 1 destination | `x-apple.systempreferences:com.apple.Time-Machine-Settings.extension` | Info |
| `persistence_new_item` | P1 | (Ben only) Startup items | — | **Ben's dashboard only:** "New startup item on this Mac looks unusual." **The relative sees nothing.** | Baseline on first run of exactly 3 verified dirs: `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons` [V]. On a new item, run `/usr/sbin/spctl -a -vv -t execute <program>` and do a path check (`/tmp`, `/private/var/folders`, `/Users/Shared`, a hidden dir, or `sh -c`/`bash -c`/`osascript -e` one-liners). Fail only for new + (unsigned, revoked, temp/shared/hidden path, or one-liner). Team-ID allowlist. At most 1 fail per day. Item names and paths stay on the Mac. | none | Info (Ben) |
| `chrome_ext_forced` | P2 | (Ben only) Chrome extensions | — | Ben only | Chrome `Preferences` → `extensions.settings` `location == 5` (policy) on an unmanaged Mac | none | Info (Ben) |
| `lockdown`, `adp` | — | not measured | — | — | Shown only as "check yourself" links; never fail | — | — |

`sfltool dumpbtm` is **never** run automatically (it can prompt for admin). QuarantineEventsV2, browsing data, Mail and Messages are never read.

### 6.3 Guided self-checks (iPhone and Mac; "confirmed by you")

The answers are **[I did it]**, **[Not sure]** and **[Not now]**. "Not sure" → amber, then "That's okay. Ben can help next visit." Every self-check screen has a fixed footer: "Family Shield will never ask you to type a password, code or PIN."

| ID | Platform | Pri | Pace | Title | Why (one sentence) | Steps (iOS 26/27 wording; P0 builder verifies paths on device) | Link | Tier if not done |
|---|---|---|---|---|---|---|---|---|
| `auto_updates` (iOS) | iOS | P0 | 1 | Automatic updates | "Fixes install by themselves, even while you sleep." | Settings → General → Software Update → Automatic Updates → turn on **Automatically Install** under **iOS Updates** and **Automatically Install** under **System Files**; then Settings → Privacy & Security → **Background Security Improvements** → **Automatically Install** (iOS 26/27; BSI starts in 26.1). iOS 18: turn on everything, including **Security Responses & System Files** | Settings | Amber |
| `stolen_device_protection` | iOS | P0 | 1 | Stolen Device Protection | "If a thief learns your passcode, they still can't change your Apple Account." | "This may already be on. Just check." Settings → Face ID & Passcode (Touch ID & Passcode on iPhone SE / iPhone Duo, picked by `LAContext.biometryType`) → passcode → Stolen Device Protection → On → Require Security Delay: **Always** (the other choice is **Away from Familiar Locations**). If the row is missing, set up Face ID or Touch ID first. "Changing some settings will take one hour. That's the point." | Settings | Amber |
| `recovery_contact` | iOS, Mac | P0 | 1 | Recovery contact | "If you ever get locked out of your Apple Account, this person can help you get back in. They can't see your photos, messages or anything else." Advice on who to pick: someone they know well and trust (grown child, sibling, longtime friend) with an iPhone who is easy to reach; never someone who contacted them out of the blue. The app does not name Ben. | Settings → [your name] → Sign-In & Security → **Recovery Contacts** → Add Recovery Contact → the person they picked. iOS 18 / macOS 14–15 say **Account Recovery**. The row shows only with two-factor on; Family Sharing members are added without accepting, others accept in Messages. "Choose a recovery **contact**, not a recovery key." | Settings / `AppleIDSettings` | Amber |
| `screen_unknown` | iOS | P0 | 1 | Screen unknown callers and texts | "Strangers have to say who they are before your phone rings." | Settings → Apps → Phone → Screen Unknown Callers → **Ask Reason for Calling**; Settings → Apps → Messages → Screen Unknown Senders → On | Settings | Amber |
| `find_my` (iOS) | iOS | P0 | 1 | Find My iPhone | "You can find, lock or erase a lost iPhone." | Settings → [your name] → Find My → Find My iPhone → On (plus Find My network, Send Last Location) | Settings | Amber |
| `family_code_word` | iOS, Mac | P0 | 1 | Family code word | "If someone calls sounding like family and asks for money, ask for the word." | "Decide it together, out loud. Don't type it anywhere, not even here." Answers: **[We have one]** / **[Not yet]** | none | Amber |
| `carrier_lock` | iOS | P0 | 2 | Phone number lock | "Stops criminals from moving your number to their phone." | The person picks a carrier (shown locally only; never synced). Verizon: My Verizon → Me → Edit profile and settings → Security → **Number Lock** and **SIM Protection** for each number → Confirm. AT&T: the **AT&T** app → person icon → **Wireless account lock** → swipe to lock. T-Mobile: T-Life → **Account** (some versions say Manage) → gear → Security → **SIM Protection** → Save; then Manage → See plans → Manage add-ons → **Port Out Protection** (free). Visible: Dashboard → Device details → **Line Lock**. Mint: Account → Security → **Number Lock**. Cricket: Settings → Security → **Account Lock**. UScellular: migrated to T-Mobile with SIM Protection and Port-out Protection already on; use the T-Mobile steps. Other: "Ask Ben." Paths per docs/verified/AUDITED.md (2026-10-23). Label: "Menu names may differ a little." "If they ask you to make a PIN, keep it to yourself. Don't type it into Family Shield." | none | Amber |
| `credit_freeze_equifax` | iOS, Mac | P0 | 2 | Freeze: Equifax | "Stops anyone from opening a loan in your name." | "Choose the free **freeze**, not a paid lock." Each item opens its own bureau's free-freeze page (catalog `supportURL`): Equifax `https://www.equifax.com/personal/credit-report-services/credit-freeze/`, Experian `https://www.experian.com/help/credit-freeze/`, TransUnion `https://www.transunion.com/credit-freeze`. The FTC overview is `https://consumer.ftc.gov/articles/credit-freezes-and-fraud-alerts` (it does not link the bureau pages) [V 2026-10-23] | Safari | Amber |
| `credit_freeze_experian` | iOS, Mac | P0 | 2 | Freeze: Experian | same | same | Safari | Amber |
| `credit_freeze_transunion` | iOS, Mac | P0 | 2 | Freeze: TransUnion | same | same | Safari | Amber |
| `passwords_alerts_clear` | iOS, Mac | P1 | 3 | Password warnings | "Your iPhone warns you about leaked or reused passwords." | Passwords app → Security → fix or review any warnings. **Yes/no only. The app never asks how many.** | none | Amber |
| `fraud_website_warning` | iOS | P1 | 3 | Safari scam-site warning | "Safari warns you before opening known fake sites." | Settings → Apps → Safari → Fraudulent Website Warning → On | Settings | Amber |
| `safety_check_quarterly` | iOS | P1 | 3 | Safety Check | "Make sure only the right people can see your location and photos." | Settings → Privacy & Security → Safety Check → **Manage Sharing & Access**. "Don't use Emergency Reset unless you're in danger." | Settings | Info |
| `advanced_data_protection` | iOS, Mac | P2 | — | (optional) Advanced Data Protection | Shown as optional. Never counts against status. | — | — | none |

### 6.4 Online accounts (from REQUIREMENTS-ADDENDUM; iOS and Mac; self-reported; pace group 3; P0)

**Onboarding:** a one-time "Which of these do you use?" picker with big toggle tiles and logos drawn as **text plus SF Symbols only** (no third-party brand art, to stay within guideline 5.2). The selection is stored **locally only**. Each picked service yields a mini-checklist of the 7 standard steps; steps that don't apply to a service are skipped:

| Step key | Plain copy (generic, then filled in per service) |
|---|---|
| `2fa` | "Turn on two-step sign-in (or a passkey)." |
| `unique_pw` | "Open the **Passwords** app and tap **Security**. If this account shows up as reused, weak or leaked, tap it and follow the steps. Passwords can make and save a new one for you." |
| `recovery_info` | "Make sure your recovery phone and email are yours and up to date." |
| `sessions` | "Look at where you're signed in. Sign out of anything you don't recognize." |
| `third_party` | "Remove apps or sites connected to this account that you don't use." |
| `alerts` | "Turn on sign-in alerts (and for money accounts, alerts for every payment)." |
| `checkup` | "Run the company's own security check." (opens the official page) |

**Per-service copy and "why" lines (2026-10-23):** every step of every service has its own start-to-finish copy (`service.<key>.step.<step>`): which app or website to open, the exact menu names in **bold**, and what to tap at the end. Only `unique_pw` may use the generic copy above. Paths come from the companies' official help pages (`docs/verified/`); where no official page confirms a label, the copy stays hedged ("look for …", "Menu names may differ a little"). Website-only steps say "choose", not "tap", so they read right on the Mac. Under each step the screen shows one plain sentence, "Why: …", in smaller secondary text; VoiceOver reads the step and its why as one element. The reason is `accounts.why.<step>` for all 8 step kinds, or `service.<key>.why.<step>` where it differs meaningfully (email recovery info, payment alerts, WhatsApp two-step, SSA, IRS IP PIN, and so on). `OnlineService.whyKey(for:)` picks the override, else the generic key; CatalogLintTests check that every step has one.

**Service catalog** (compiled into `Services.swift`; URLs open in Safari; every URL is checked by `tools/link-check.sh` at build time [U: all URLs to verify]; if a page has no URL, the copy says "in the app: …"):

| Category | Service key | Official page (hard-coded) |
|---|---|---|
| email | `gmail` | `https://myaccount.google.com/security-checkup` |
| email | `icloud_mail` | Settings → [your name] → Sign-In & Security (no URL; covered by Apple steps) |
| email | `outlook` | `https://account.microsoft.com/security` |
| email | `yahoo` | `https://login.yahoo.com/myaccount/security` |
| email | `aol` | `https://login.aol.com/myaccount/security` |
| money | `bank` (generic: "Your bank or credit union") | none: "Open your bank's own app, then Settings → Security and Alerts. Never use a link from a text." |
| money | `credit_card` (generic) | none (same copy) |
| money | `paypal` | `https://www.paypal.com/myaccount/security/`. 2FA: Settings → Security → **Set Up** next to 2-step verification (app or website) |
| money | `venmo` | in the app: Me → Settings → **Face ID & Passcode**; web: Settings → Security |
| money | `zelle` | "Zelle lives inside your bank's app. Use the bank steps." |
| money | `cash_app` | in the app: Profile → Security → **Security Lock** |
| money | `brokerage` (generic: retirement/investment) | none: bank-style copy, plus "Add a **trusted contact** to the account." |
| social | `facebook` | `https://accountscenter.facebook.com/password_and_security` (`/privacy/checkup` is Privacy Checkup, not Security Checkup) |
| social | `instagram` | in the app: Profile → ☰ → Accounts Center → Password and security → Security Checkup |
| social | `whatsapp` | in the app: Settings → Account → **Two-step verification**; passkeys are a separate row, Settings → Account → **Passkeys** |
| social | `x` | `https://x.com/settings/security_and_account_access` |
| social | `tiktok` | in the app: Profile → ☰ → Settings and privacy → **Security & permissions** |
| social | `linkedin` | `https://www.linkedin.com/mypreferences/d/categories/sign-in-and-security` |
| social | `snapchat` | in the app: Settings → My Account → Two-Factor Authentication |
| shopping | `amazon` | `https://www.amazon.com/a/settings/approval` (Two-Step Verification) |
| shopping | `carrier_account` | uses `carrier_lock` (§6.3) |
| government | `ssa` | `https://www.ssa.gov/myaccount/`: "Create your own account before a criminal does." |
| government | `irs_ip_pin` | `https://www.irs.gov/identity-theft-fraud-scams/get-an-identity-protection-pin`: "Get an IP PIN. Keep it to yourself. Never type it into Family Shield." |
| health | `health_portal` (generic) | none: generic copy |
| credit | `credit_bureaus` | uses the three `credit_freeze_*` items (§6.3) |

**What syncs** (category rollups only, to honour "account names never reach the dashboard"):

| ID | Pass when | Unknown when |
|---|---|---|
| `accounts_email` | every step of every picked email service is "I did it" | none picked, or any "Not sure" / unanswered |
| `accounts_money` | same for money services | same |
| `accounts_social` | same for social | same |
| `accounts_shopping` | same for shopping | same |
| `accounts_government` | same for `ssa` + `irs_ip_pin` | same |
| `accounts_health` | same for health | same |

`fail` = any step answered "Not now" for 14+ days. Service names, step-level answers and counts never leave the device. Ben sees "Email accounts: ✓", not "Gmail".

### 6.5 Info-only items (local, never synced)
`scam_checker_available` and `llm_available` are **not synced** (the latter would leak device class). `feed_fresh` is shown on the device as "Last checked …" and on Ben's own device under Feed health.

---

## 7. Behavioral content (compiled into the app)

**Family Rules** (6 cards, each one screen):
1. "Hang up and look it up. Call back using a number you find yourself."
2. "Never read a code to anyone. Not the bank, not Apple, not 'Ben'."
3. "No gift cards, crypto or wire transfers for anyone you met online or on the phone."
4. "Real warnings never come with a phone number to call."
5. "Never paste anything into Terminal because a website told you to."
6. "Our family code word. Decide it together, out loud. Don't type it anywhere." [We have one] / [Not yet]

**Trust line** (Home footer and About; fixed): "Family Shield never asks for passwords, codes or money. It never changes your settings. The only person it asks you to call is Ben."

**Scam bulletins (P1):** compiled cards with stable IDs: `tollText`, `fakeAppleSupportReset`, `mediCalBreachPhish`, `aholdRefundPhish`, `aiVoiceEmergency`, `fakeDownloadClickFix`, `packageHeld`, `irsRefund`. The P1 signed feed may only carry `activeBulletins: [ID]`, which turns compiled cards on or off. There is no remote text.

---

## 8. Backend: CloudKit (primary, P0)

### 8.1 Layout
- Container `iCloud.org.example.aegis`. **Production** environment for every TestFlight and Developer ID build.
- **Ben's private database:**
  - Zone `z_admin`: **never shared**. It holds Ben-only records (labels, enrollment baselines). It also marks the app as "owner": owner mode is on when this zone exists.
  - Zone `z_<random 16 hex>` **per family member**, each with a zone-wide `CKShare(recordZoneID:)`: `publicPermission = .none`, one participant (that person), `permission = .readWrite`. Share title: "Family Shield". No person's name appears in zone names or share metadata that Ben's code sets.
  - Zone `z_self`: Ben's own devices write here directly. It is not shared.
- **A family member's devices** (any number, on one Apple ID) write into their own zone through their **shared database**, after accepting the share.

### 8.2 Record types (the whole schema; deploy to Production before the first external build)

| Record type | Zone | recordName | Fields (type) | Written by |
|---|---|---|---|---|
| `Device` | person zone / `z_self` | `<deviceUUID>` (random UUID v4, created on first launch and kept in the Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) | `platform` (Int64: 0 = ios, 1 = mac), `enrolledOn` (Date, day), `catalogVersion` (Int64), `appBuild` (Int64), `lastReport` (Date, day) | that device |
| `CheckResult` | person zone / `z_self` | `<deviceUUID>_<checkID>` (underscore, not slash) | `deviceID` (String, UUID), `checkID` (String, allowlisted), `status` (Int64: 0/1/2), `source` (Int64: 0/1), `checkedOn` (Date, day precision, 00:00 UTC), `catalogVersion` (Int64) | that device |
| `PersonLabel` | `z_admin` | `<zoneName>` | `label` (String ≤ 40), `createdOn` (Date) | Ben only |
| `DeviceLabel` | `z_admin` | `<deviceUUID>` | `label` (String ≤ 40), `firstCreatorRecordName` (String: the `creatorUserRecordID` seen at enrollment) | Ben only |

Indexes: `CheckResult.deviceID` (queryable), `recordName` (queryable). Nothing else. **No free-text field exists on any shared record type.** The Production schema lock gives a server-side "no extra fields" guarantee.

### 8.3 Access rules (the CloudKit equivalent of RLS)
- The share has `publicPermission = .none`, so only the invited participant (plus Ben as owner) can read or write a person zone.
- Relatives cannot see each other: separate zones and separate shares.
- `z_admin` and `z_self` are never shared.
- Client-side enforcement in ShieldCore:
  - write only allowlisted `checkID`s;
  - `status` ∈ {0,1,2};
  - `checkedOn` truncated to the day;
  - record name must match `^[0-9a-f-]{36}_[a-z0-9_]{1,48}$`.
- Ben's dashboard flags any `CheckResult` whose `creatorUserRecordID` ≠ `DeviceLabel.firstCreatorRecordName` ("written by someone else"). Because the zone is per-person, the only possible writer is that person.

### 8.4 API contract (app ↔ CloudKit)

**Family device: enroll (first launch after the share link)**
1. iOS `windowScene(_:userDidAcceptCloudKitShareWith:)` or Mac `application(_:userDidAcceptCloudKitShareWith:)` → `CKAcceptSharesOperation` → store the accepted `zoneID` in UserDefaults (non-secret).
2. Save `Device` with `CKModifyRecordsOperation(savePolicy: .allKeys)` into the shared DB, in that zone.

**Family device: report**
- When: on app foreground, after any check changes, on the iOS `BGAppRefreshTask` (opportunistic), on the Mac every 24 h and on wake.
- What: `CKModifyRecordsOperation` with all current `CheckResult`s plus `Device.lastReport`. `savePolicy = .changedKeys`. `qualityOfService = .utility`. `isAtomic = false`.
- Skip a write if nothing changed and `lastReport` is today.
- Errors:
  - `.networkUnavailable` / `.serviceUnavailable` / `.requestRateLimited` → queue (`SyncQueue`, last-state-wins) and retry with `retryAfterSeconds`, or exponential backoff from 1 min to 6 h.
  - `.zoneNotFound` / `.userDeletedZone` / `.participantMayNeedVerification` / share revoked → mark the sync state "Not connected to Ben" (shown in About) and keep working locally.
  - `.serverRecordChanged` → overwrite with ours (this device is the only author).
- **A device never reads its own status back from CloudKit.** Local evaluation is the only truth on the device.

**Family device: leave**
About → "Stop sharing with Ben" deletes this device's `Device` and `CheckResult` records, then leaves the share (`CKShare` participant removal through `UICloudSharingController` "Remove Me", or by deleting the shared zone from the shared DB).

**Ben: create a person**
1. Create zone `z_<hex>` → create `CKShare(recordZoneID:)`, `publicPermission = .none` → save both.
2. Present `UICloudSharingController` (iOS) or `NSSharingServicePicker` with `NSItemProvider` registered for the CKShare (Mac). Allowed permission: read-write; private.
3. Save `PersonLabel` in `z_admin`. The label is typed by Ben, or defaults to the participant's `nameComponents` when non-nil.

**Ben: dashboard read**
- `CKFetchRecordZoneChangesOperation` over every zone in his private DB (except `z_admin`), with server change tokens cached.
- **P1:** plus `CKDatabaseSubscription` on the private DB → silent push → recompute → local notification on Ben's device only, red tier only, at most one per device per day: "Mom's iPhone: update needed." The label is mapped locally.

**Staleness (Ben's view):**
- iPhone: no `lastReport` for > 7 days → grey "Not reporting".
- Mac: > 2 days → grey.
- Any device: > 14 days → every chip grey.

### 8.5 Device labels
Labels exist only in Ben's `z_admin`. Family devices never store or send a label. The family-side About screen shows "Ben sees this as: (Ben chooses)".

---

## 9. Fallback backend: Supabase (documented, NOT deployed in v1)

Used only if the Week-1 CloudKit spike fails (§15), or if a non-Apple relative or a web dashboard is ever needed. Free tier. Plain `URLSession` REST, no supabase-swift. Only the `sb_publishable_` key ships. `SupabaseSink: ResultSink`.

### 9.1 Auth
- Family devices: Supabase anonymous sign-in, plus a one-time pairing code that Ben generates. The code is Ben's enrollment token, not a family secret, and it expires in 15 minutes.
- Ben: magic link or Sign in with Apple (iOS only).
- Keep the project awake through the devices' daily upserts.

### 9.2 Schema + RLS SQL
```sql
-- 001_family_shield.sql  (fallback only)
create extension if not exists pgcrypto;

create table public.households (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table public.household_admins (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (household_id, user_id)
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  platform smallint not null check (platform in (0,1)),          -- 0 ios, 1 mac
  enrolled_on date not null default current_date,
  last_report date
  -- no label column: labels live only on Ben's device
);

create table public.pairing_codes (
  code_hash text primary key,                                     -- sha256(code), never plaintext
  household_id uuid not null references public.households(id) on delete cascade,
  expires_at timestamptz not null,
  used_at timestamptz
);

create table public.pairing_failures (
  auth_user_id uuid not null,
  at timestamptz not null default now()
);

create table public.check_results (
  device_id uuid not null references public.devices(id) on delete cascade,
  check_id text not null check (check_id ~ '^[a-z0-9_]{1,48}$'),
  status smallint not null check (status in (0,1,2)),
  source smallint not null check (source in (0,1)),
  checked_on date not null,
  catalog_version int not null,
  primary key (device_id, check_id)
);

alter table public.households        enable row level security;
alter table public.household_admins  enable row level security;
alter table public.devices           enable row level security;
alter table public.pairing_codes     enable row level security;
alter table public.pairing_failures  enable row level security;
alter table public.check_results     enable row level security;

create or replace function public.is_admin(hid uuid) returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.household_admins
                 where household_id = hid and user_id = auth.uid());
$$;

create or replace function public.my_device_id() returns uuid
  language sql stable security definer set search_path = '' as $$
  select id from public.devices where auth_user_id = auth.uid();
$$;

-- check_results: a device writes only its own rows; admins and the device read.
create policy cr_insert_own on public.check_results for insert to authenticated
  with check (device_id = public.my_device_id());
create policy cr_update_own on public.check_results for update to authenticated
  using (device_id = public.my_device_id()) with check (device_id = public.my_device_id());
create policy cr_select on public.check_results for select to authenticated
  using (device_id = public.my_device_id()
         or public.is_admin((select d.household_id from public.devices d where d.id = device_id)));
create policy cr_delete_own on public.check_results for delete to authenticated
  using (device_id = public.my_device_id());

-- devices: admins and self can read; self may update last_report only (column grant); self may delete (leave).
create policy dev_select on public.devices for select to authenticated
  using (auth_user_id = auth.uid() or public.is_admin(household_id));
create policy dev_update_self on public.devices for update to authenticated
  using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());
create policy dev_delete_self on public.devices for delete to authenticated
  using (auth_user_id = auth.uid() or public.is_admin(household_id));
revoke update on public.devices from authenticated;
grant update (last_report) on public.devices to authenticated;

-- households, household_admins, pairing_codes, pairing_failures: no policies => no direct client access.
create policy ha_select_self on public.household_admins for select to authenticated
  using (user_id = auth.uid());

create or replace function public.create_household() returns uuid
  language plpgsql security definer set search_path = '' as $$
declare hid uuid;
begin
  if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'not allowed';
  end if;
  insert into public.households default values returning id into hid;
  insert into public.household_admins values (hid, auth.uid());
  return hid;
end $$;

create or replace function public.create_pairing_code(hid uuid) returns text
  language plpgsql security definer set search_path = '' as $$
declare alphabet text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; code text := ''; i int;
begin
  if not public.is_admin(hid) then raise exception 'not admin'; end if;
  for i in 1..8 loop
    code := code || substr(alphabet, 1 + (get_byte(extensions.gen_random_bytes(1),0) % 32), 1);
  end loop;
  insert into public.pairing_codes(code_hash, household_id, expires_at)
    values (encode(extensions.digest(code,'sha256'),'hex'), hid, now() + interval '15 minutes');
  return code;
end $$;

create or replace function public.redeem_pairing_code(code text, p_platform smallint) returns uuid
  language plpgsql security definer set search_path = '' as $$
declare pc public.pairing_codes; did uuid;
begin
  if auth.uid() is null then raise exception 'no session'; end if;
  if (select count(*) from public.pairing_failures
      where auth_user_id = auth.uid() and at > now() - interval '1 hour') >= 5 then
    raise exception 'too many attempts';
  end if;
  select * into pc from public.pairing_codes
   where code_hash = encode(extensions.digest(upper(code),'sha256'),'hex')
     and used_at is null and expires_at > now()
   for update;
  if not found then
    insert into public.pairing_failures(auth_user_id) values (auth.uid());
    raise exception 'invalid code';
  end if;
  update public.pairing_codes set used_at = now() where code_hash = pc.code_hash;
  insert into public.devices(household_id, auth_user_id, platform)
    values (pc.household_id, auth.uid(), p_platform) returning id into did;
  return did;
end $$;

revoke all on function public.create_household(), public.create_pairing_code(uuid),
  public.redeem_pairing_code(text, smallint) from public, anon;
grant execute on function public.create_household(), public.create_pairing_code(uuid),
  public.redeem_pairing_code(text, smallint) to authenticated;
```
Note: on the free tier, `pgcrypto` installs under the `extensions` schema. Run the Supabase security advisor after applying. **Do not apply this in v1.**

### 9.3 REST contract (fallback)
- `POST /auth/v1/signup` (anonymous) → session.
- `POST /rest/v1/rpc/redeem_pairing_code {code, p_platform}`.
- `POST /rest/v1/check_results` with `Prefer: resolution=merge-duplicates` and an array body.
- `PATCH /rest/v1/devices?id=eq.<id> {last_report}`.
- Ben: `GET /rest/v1/check_results?select=*`.

---

## 10. UX: screens and copy

**Global rules:**
- 6th–8th grade reading level, one main action per screen.
- Primary buttons at least 60 pt tall, full width.
- Every status shows **color + SF Symbol + word**:
  - green `checkmark.shield.fill` "Done"
  - amber `exclamationmark.triangle.fill` "To do" (dark text on amber)
  - red `exclamationmark.octagon.fill` "Today"
  - grey `questionmark.circle` "Can't check"
- No countdowns, threat counts, flashing, "CRITICAL", or percentages.

### 10.1 Family member, iPhone. Ben does the first setup in person: installs TestFlight, accepts the email invite, installs the app, taps the CloudKit link, and picks himself in Contacts.
1. **Welcome.** "Family Shield, made by Ben for our family. It helps you spot scams and keeps your iPhone up to date. It never asks for passwords, codes or money. It never changes your settings." → **[Get started]**
2. **Join Ben's family.** If the share was already accepted: "You're connected to Ben's family. Ben will only see a ✓ or ✗ for each item." → **[Continue]**. If not: "Tap the link Ben texted you." (Ben is there in person.)
3. **Who to call.** "Who should Family Shield call when you're unsure?" → **[Choose Ben from my contacts]** (`CNContactPickerViewController`). The chosen phone number is saved on this device only, in the Keychain. It is never synced.
4. **Reminders.** "Can Family Shield remind you when something needs fixing? At most one reminder." → **[Yes]** (system prompt) / **[No thanks]**
5. **Which accounts do you use?** Tiles by category; "You can change this later." → **[Done]** (may be skipped; it reappears with pace group 3).
6. **Home.**
   - Status: "You're protected. Nothing to do. Checked today at 9:14 AM." or "1 thing to do today."
   - One **Next step** card with **[Show me how]**; "2 more for later" collapsed.
   - Big buttons: **[Is this a scam?]** and **[Call Ben]**.
   - A "Family Rules" row, then the trust line.
   - A footer link to About.
   - A day-60 banner (TestFlight): "Family Shield needs a new version soon. Ask Ben."
7. **Fix step (measured, e.g. update).** "Please update your iPhone today. Apple fixed a problem that criminals are already using." Then one step per screen: "Open **Settings** → **General** → **Software Update**." "If you see iOS 27.0.1 or iOS 26.7.1 (or newer), either one is fine." → **[Open Settings]** / **[Next]** / **[Done]**. The app re-checks when it returns to the foreground. Links: "Why am I seeing this?" (Apple security page), **[Call Ben]**.
8. **Guided step (self).** One "why" sentence → steps → **[I did it]** / **[Not sure]** / **[Not now]**. Badge "Confirmed by you". Footer: "Family Shield will never ask you to type a password, code or PIN."
9. **Is this a scam?** "Got a text, email, pop-up or call that worries you?" → **[Paste a message]** **[Choose a screenshot]** **[Someone called me]**.
10. **Result.**
    - Danger (red octagon): "This looks like a scam."
    - Be careful (amber triangle): "Be careful."
    - No signs (grey circle): "We didn't find common warning signs. Still follow the rules below."
    - Then up to 3 reasons, the most relevant Family Rule, **[Call Ben]**, **[Send to Ben]** (system share sheet; "If the message has a code in it, don't send the code."), "Report it at ReportFraud.ftc.gov" (hard-coded), and "Nothing you check here is saved or sent."
11. **Family Rules.** Six cards (§7).
12. **About & Privacy.**
    - Who made it (Ben).
    - "What Ben can see": a live sample showing exactly the check titles with ✓/✗/?.
    - Build date, "Last checked".
    - Sync state ("Connected to Ben" / "Not connected").
    - "Do it all now with Ben" (unlock all pace groups).
    - "Change my accounts list".
    - **[Stop sharing with Ben]** (confirm sheet).

### 10.2 Family member, Mac
- The same screens in one window. A **menu-bar shield** shows a word: "Protected", "1 to do" or "Today" ("Checking" until the first check of a launch finishes). No counts out of totals.
- First launch, before registering the login item: "Your Mac will show a notice that says 'Background Items Added' and names Family Shield. That's expected, that's us." (macOS 13+ titles its notification "Background Items Added"; it never says "added to Login Items".) → **[Keep checking in the background]** calls `SMAppService.mainApp.register()`. If the status is `.requiresApproval`, open `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` with the copy "Turn on Family Shield".
- The scam checker accepts paste, plus dragging or picking an image file.
- Fix cards use the §6.2 links and always show the written path.
- Persistence findings are **never** shown to the relative (Ben-only, P1).

### 10.3 Ben
1. **Start a family** (small link on Welcome: "I'm setting this up for my family"). It creates `z_admin` and `z_self`.
2. **Family tab.** Rows by person, then device:
   - Worst-status chip, "Last reported 2 days ago".
   - Grey "Not reporting" past the staleness limits.
   - Hollow icon for self-reported items.
3. **Add person.** Type a label → **[Send invite]** (share sheet to iMessage).
4. **Device detail.**
   - Each check: status, measured/self, date.
   - Ben-only items: `os_update_stuck`, `beta_catalog`, `app_build_fresh`, `persistence_new_item` (P1), creator mismatch.
   - **[Text them]** opens Messages with a draft that Ben sends himself, from compiled templates.
5. **Feed & release health.**
   - Feed age, last SOFA change.
   - TestFlight build age with a day-60 and day-75 warning.
   - Scam-corpus pass rate baked in at build time.
6. **This Mac's details** (Ben's own Mac only, local): login-item names, the Gatekeeper-rejection list, and a manual **[Run sfltool dumpbtm]** button (Ben's own Mac; may prompt).

---

## 11. Accessibility requirements (acceptance criteria)

- Dynamic Type through **AX5** with no truncation. Cards reflow vertically, and buttons grow.
- Every status card is **one VoiceOver element**, with a label like "Update your iPhone. Today. Measured." and hint "Double-tap to see how." (Mac: "Shows you how.", since a Mac control is clicked or pressed with VO-Space)
- Contrast ≥ 4.5:1 for text and ≥ 3:1 for icons in light and dark. Amber cards use dark text.
- Status is never conveyed by color alone.
- Respect Reduce Motion (no animated transitions beyond a cross-fade), Reduce Transparency, Bold Text, Increase Contrast, and Differentiate Without Color.
- Hit targets ≥ 60 pt for primary actions and ≥ 44 pt for everything else.
- No timeouts on any screen. Nothing auto-advances.
- Mac: full keyboard navigation; the menu-bar item is accessible; window minimum 600×500 pt.
- Localizable strings in `.xcstrings` (English only in v1); no text in images.

---

## 12. Security and privacy rules (enforced in code review and tests)

1. Sync payload = §8.2 fields only. `RecordsTests` asserts every field name and type.
2. Never leaves the device: message text, screenshots, OCR, verdicts, OS version, model, board ID, app names, paths, startup items, extension IDs, service names, carrier, the contact chosen for Ben, Apple ID, anything from MobileMeAccounts.plist other than one boolean.
3. No input field anywhere accepts free text that is stored or synced. The scam checker's text box is in-memory only.
4. Every displayed URL comes from compiled constants (`DeepLinks.swift`, `Services.swift`, `catalog.json`). CI lint: grep for `URL(string:` outside those files fails the build.
5. Child processes: an absolute path allowlist (`fdesetup`, `spctl`, `csrutil`, `sysadminctl`, `socketfilterfw`, `profiles`, `tmutil`, `defaults`), fixed arguments, no shell, 10 s timeout.
6. Mac app: Hardened Runtime with no exceptions; no sandbox; never requests admin, Full Disk Access, Accessibility or Automation.
7. No analytics, crash SDKs or remote logging. `os.Logger` private only.
8. The Mac update notice: the P1 signed `mac-latest.json` carries **only** `{version, build, minSupported}` and an Ed25519 signature verified against two pinned public keys (active + offline backup). There is **no URL**. The card says "A new Family Shield is ready. Ben will help you install it." On Ben's dashboard: `app_outdated` (local only).
9. Ben's account hygiene: Ben is the only team member; no App Store Connect API keys; no signing secrets in CI; releases go from Xcode on Ben's Mac. The feed repo is public and contains only scripts.
10. Supply chain: zero packages; Actions pinned by SHA; `permissions: contents: read` except the Pages deploy job.
11. Before the first commit: create the `.gitignore` (§3).
12. Agents never enter passwords, app-specific passwords or 2FA codes. Any step that needs one is Ben's.

---

## 13. Testing plan

### 13.1 Unit tests (ShieldCore, `swift test` + Xcode)

| Suite | Cases (minimum) |
|---|---|
| `VersionEvaluatorTests` | iOS 27.0.1 pass; iOS 26.7.1 pass; iOS 26.5.1 fail-exploited (red); iOS 18.7.10 on `iPhone11,2` pass; 18.7.8 on `iPhone11,2` fail; 18.7.8 on `iPhone12,1` pass; `iPhone10,3` → device unsupported; macOS 26.5.1 on Ben's board ID → fail-exploited; macOS 15.8.1 pass; macOS 14.8.9 pass; macOS 13.x → unsupported; rollback feed rejected (cache kept); feed raising a minimum is accepted; stale 8 days → "last checked"; stale 31 days and device above min → unknown; stale 31 days and below bundled min → fail; no feed ever → bundled table only; `CVEs` as int/map/array; `Build` null |
| `FeedDecodeTests` | Captured SOFA v2 iOS and macOS fixtures from 2026-10-22 decode; unknown keys ignored; truncated JSON → nil |
| `ScamCorpusTests` | ≥ 80 scam cases (toll, USPS, IRS, Medi-Cal, Ahold refund, fake Apple Support, "Hi Mom", romance, investment, tech-support pop-up with phone, ClickFix Terminal, gift card, Zelle "safe account", punycode `xn--`, brand/link mismatch, zero-width obfuscation, bidi obfuscation, ≥ 8 AI-injection attempts) → `danger` or `beCareful`, with ≥ 90% `danger` on the clear ones. ≥ 40 benign cases (real bank 2FA texts, appointment reminders, family chat) → not `danger` in ≥ 95%. Call quiz truth table. |
| `StatusEngineTests` | Pacing unlocks; 90-day re-ask; "Not sure" → unknown; reminder count (1 + 1); account rollups (all done → pass, none picked → unknown, "Not now" 14 days → fail) |
| `RecordsTests` | Record name regex; allowlist rejects an unknown checkID; payload contains exactly the allowed keys; `checkedOn` truncated to the day |
| `CatalogLintTests` | `CheckID.allCases` == catalog keys; every key has title/pass/fail strings; every URL constant is https or `x-apple.systempreferences:`; no string contains a digit sequence that looks like a phone number |
| `MacCheckParserTests` | Captured outputs for each tool (on/off/error/garbage) → pass/fail/unknown; `sysadminctl` stderr parsing |

### 13.2 UI screenshot matrix (XCUITest, `XCUIScreen.main.screenshot()` attached to the result bundle)
- **Screens:** Welcome, Join, Who to call, Reminders, Accounts picker, Home (protected), Home (1 red), Fix step, Guided step, Scam entry, Result × 3 verdicts, Call quiz, Family Rules, About, Family tab (Ben), Device detail (Ben).
- **Variants:** light and dark × default text and **AX5** (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`) × iPhone SE (3rd gen) and iPhone 17 Pro simulators.
- **Mac:** main window and menu-bar popover, light and dark, at default and largest text.
- Launch arguments `-FSDemoState <name>` inject fixed states. No network or CloudKit in UI tests (an in-memory `ResultSink`).
- Accessibility audit: `XCUIApplication().performAccessibilityAudit()` on each screen (iOS 17+ / macOS 14+), with zero failures allowed except documented ones.

### 13.3 Device and integration tests
- **Mac smoke test** (`-FSNoCloud -FSRunChecksAndPrint`): every check returns pass, fail or unknown in under a second, and no prompts appear.
- `tools/deeplink-test.sh` on macOS 26.x: each Settings URL lands on the expected window title.
- **CloudKit two-Apple-ID test** (Spike S1).
- Manual VoiceOver pass on device for Home, Result and a Fix step.

---

## 14. Distribution

### 14.1 Ben's Day-0 steps (Ben does these himself; agents never do them)
1. **Patch the release Mac** (off beta updates, on the latest security release).
2. Optional: turn on the Mac firewall; set up a Time Machine disk.
3. **Xcode → Settings → Accounts:** refresh the team (the cache shows "Personal Team"), then Manage Certificates → **+ Apple Distribution** and **+ Developer ID Application** [U: may require the Account Holder role, which Ben has].
4. Put your bundle prefix and team ID in `Config/Identity.local.xcconfig` (git-ignored).

### 14.2 iPhone (C2)
1. Xcode automatic signing creates the App IDs `org.example.aegis.ios` (+ `.share` P1) and the iCloud container.
2. Run a Debug build on Ben's device (Development environment), tap **"I'm setting this up for my family"** and let Home finish its first check. That creates every record type: `Device` and `CheckResult` from the `z_self` report, `PersonLabel` and `DeviceLabel` from a save-then-delete seed that Debug builds run at "Start a family". Check all four in CloudKit Console → Schema, add the §8.2 indexes, then **Deploy Schema Changes to Production**. Production never creates a type on save, so a type missing there makes every save of it fail.
3. App Store Connect: create the iOS app record "Family Shield" (Ben confirms each submit; App Store Connect is already signed in).
4. Archive → Organizer → Distribute → App Store Connect → upload.
5. TestFlight: an internal group with only Ben's devices (immediate). Then an **external group invited by email** (≤ 10 relatives; no public link).
6. Beta App Review notes: "Read-only family safety checklist and on-device scam-text checker. No account, no login, no data collection; results sync to the family organizer's own iCloud via CloudKit sharing. The app never changes settings." No "virus" or "antivirus" wording (2.3.1a), no Apple-UI imitation (5.2.5), no `App-prefs:` URLs.
7. Upload a new build every 60–75 days (Ben's calendar reminder; the app banner appears at day 60). P2: unlisted App Store distribution removes the expiry.

### 14.3 Mac (C3)
1. Archive (Hardened Runtime, Developer ID signing, Developer ID provisioning profile with iCloud).
2. Organizer → Distribute App → **Direct Distribution** → notarize → export the stapled `.app` [U, Spike S2]. **If Xcode asks for an app-specific password**, Ben creates it at account.apple.com and types it himself, or runs `xcrun notarytool store-credentials` himself so it lives only in his Keychain. Agents never touch it.
3. Verify: `spctl -a -vv -t execute "Family Shield.app"` → "source=Notarized Developer ID"; `stapler validate`.
4. Ben installs it **in person or by AirDrop** onto each family Mac, drags it to Applications himself, launches it, registers the login item and taps the share link. The family never downloads anything.
5. Updates: Ben repeats step 4 on his next visit. The P1 signed manifest only tells the relative "Ben will help you install it."

### 14.4 Feed (P1, C6)
Public repo `family-shield-feed` (GitHub Pages needs a public repo on a free account; it holds only `feed/` and the workflow).
- Cron `0 */6 * * *` runs `curl` SOFA v2 (with a User-Agent and ETag), validates it with `jq` against `schema.json`, reduces it to `{platform, major → [{version, supportedDevices, exploited: bool}]}` plus Mac `Models` and the XProtect version, and refuses rollbacks.
- The reduced feed is published **unsigned as a draft**. Ben signs it on his Mac with `tools/feedsign` when the numbers change; the apps accept only signed feeds from Pages and otherwise use SOFA direct.

---

## 15. Plan, spikes and go/no-go gates (2–3 weeks, not 1–2 days)

| Spike | What | Gate |
|---|---|---|
| S1 | CloudKit per-person zone share accepted by a **second real Apple ID**, on an iOS build **and** a Developer ID Mac build, against the **Production** schema. Check that the zone isn't deleted on acceptance (the forum report). | **Day 2 noon.** Fail → switch `ResultSink` to Supabase (§9), about half a day. No other sync code until S1 passes. |
| S2 | Developer ID cert creation + Direct Distribution notarization with no secret entered | Fail → Ben uses `notarytool store-credentials` himself |
| S3 | Mac checks from a GUI app raise no prompts (`spctl`, localhost sockets, `profiles`, `sysadminctl`) | Any prompt → that check becomes manual or Ben-only |
| S4 | Exact iOS 26/27 Settings paths for every §6.3 step on a real iPhone | Fix the copy |
| S5 | First TestFlight Beta App Review | Over 48 h → internal TestFlight for Ben only; the family waits |
| S6 (P1) | FoundationModels guardrails on the scam corpus; model availability in the Share Extension | Rules stay authoritative regardless |

**Schedule:**
- Week 1: Ben's Day-0 steps, S1–S4, ShieldCore (catalog, VersionEvaluator + fixtures, ScamRules + corpus).
- Week 2: iPhone P0 screens and checks, CloudKit sync, Family tab; Mac P0 checks, menu bar, login item.
- Week 3: accessibility and screenshot pass, Mac smoke test, notarize, TestFlight external review, in-person family setup.
- Then P1.

**Builder agent split:**
- A: ShieldCore Version + Catalog.
- B: ShieldCore Scam + corpus.
- C: iPhone app.
- D: Mac app + checks.
- E: Sync + Family tab (owns S1).
- Ben: Day-0, signing, uploads, installs.

### P0 / P1 / P2 summary
- **P0:**
  - Scam checker (paste, screenshot, call quiz), Call Ben, Send to Ben.
  - `os_patched`, `device_supported`, passcode and biometrics.
  - All P0 Mac posture checks.
  - Self-checks in pace groups 1–2, plus the online-accounts checklist (pace group 3) with category rollups.
  - Family Rules, trust line.
  - CloudKit per-person sync, Family tab.
  - Local reminders, build-age banner.
  - Bundled minimums + direct SOFA.
- **P1:**
  - Share Extension; FoundationModels booster (`max` rule).
  - Mac persistence watch (Ben-only), `time_machine`.
  - Ben push via `CKDatabaseSubscription` (P0 Family tab refreshes on open and pull-to-refresh).
  - Signed Pages feed + `feedsign`; signed Mac version manifest.
  - Scam bulletins by ID; Lock Screen widget "Unsure? Check it".
  - `passwords_alerts_clear`, `fraud_website_warning`, `safety_check_quarterly`.
  - Mac scam-checker polish.
- **P2:**
  - Safari blocker (tiny curated list); SMS filter (guideline 2.5.12 copy).
  - Call Directory labels Ben confirms; Chrome forced-extension check.
  - Unlisted App Store listing; optional ADP card; Supabase web dashboard.

---

## 16. Explicitly out of scope

- Changing any setting; remote commands; MDM; configuration profiles; CA certificates or trust-store edits (including eMudhra); VPN/DNS filtering; `NEURLFilter`; Live Caller ID Lookup.
- Antivirus, malware scanning, "cleaners", jailbreak detection, Endpoint Security, system extensions, real-time blocking, root helpers, Full Disk Access, automatic `sfltool`, QuarantineEventsV2, browsing/download/message/call history. No Objective-See (GPL) code.
- Any password, code, PIN, account number, SSN, IP PIN or code-word entry; Pwned Passwords; HIBP lookups; password counts; signing in to any service for anyone; auditing Gmail or iCloud accounts directly.
- Cloud LLMs (OpenAI, Anthropic, Gemini, LiteLLM or any AI gateway); Private Cloud Compute in v1.
- Third-party Swift packages, Sparkle, supabase-swift, analytics, crash SDKs.
- Server-delivered text, URLs or phone numbers, including a remote "scam news" feed and download URLs in update manifests.
- A family download step, DMG links, GitHub Releases for the family, Terminal steps, Gatekeeper bypass.
- A public TestFlight link; a public App Store listing; a sandboxed or Mac App Store build; Android; Windows; a web dashboard in v1; Fly.io or any paid hosting.
- Recommending Lockdown Mode, SIM PIN, ADP or Contact Key Verification by default.
- Showing OS version numbers, CVE IDs or counts, or SOFA `ExpirationDate` on the family UI.
- The completion email to Ben is the orchestrator's job, not part of this spec.
