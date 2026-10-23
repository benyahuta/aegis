# Building Family Shield

Toolchain: **Xcode 26.6** (Swift 6.3, language mode 6, strict concurrency complete). No third-party
packages (H4). Run every command from the repo root  unless noted.

## 1. ShieldCore package (macOS host)

```sh
cd ShieldCore
swift build
swift test
```

`swift build --build-tests` compiles the tests without running them.
The package must keep building for **iOS 18 and macOS 14**. The iOS side is compiled by the
`ShieldiOS` build below; run both before you finish.

## 2. iPhone app (Simulator, unsigned)

```sh
xcodebuild build \
  -project FamilyShield.xcodeproj -scheme ShieldiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## 3. Mac app (unsigned)

```sh
xcodebuild build \
  -project FamilyShield.xcodeproj -scheme ShieldMac \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## 4. Compile the UI tests (and package tests through the schemes)

```sh
xcodebuild build-for-testing \
  -project FamilyShield.xcodeproj -scheme ShieldiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO

xcodebuild build-for-testing \
  -project FamilyShield.xcodeproj -scheme ShieldMac \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

Each shared scheme's Test action runs its UI-test bundle plus the package's `ShieldCoreTests` and
`ShieldUITests` (so ShieldCore tests also run on the iOS Simulator).

### Running the Xcode tests (only when Ben is at the Mac)

If Developer Mode is off on your Mac, `xcodebuild test` attaches to processes and can show an
admin or "Developer Tools Access" prompt, and macOS UI tests can ask for Accessibility or
Automation access. Agents must not run these unattended. Agents use `swift test` (section 1) and
`build-for-testing` (section 4). With Ben present:

```sh
xcodebuild test -project FamilyShield.xcodeproj -scheme ShieldiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
xcodebuild test -project FamilyShield.xcodeproj -scheme ShieldMac \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData
```

## Launch arguments (SPEC §13.2)

| Argument | Effect |
|---|---|
| `-FSNoCloud` | Uses `InMemoryResultSink`. CloudKit and the network are never touched. |
| `-FSDemoState <name>` | Injects a fixed demo state for screenshots and UI tests. Implies `-FSNoCloud`. |
| `-FSRunChecksAndPrint` | **Mac only, hidden.** Runs the §6.2 checks once with no window, menu bar, CloudKit, Keychain or login item, prints `check_id -> status (tier) [note]` and the menu-bar word, and exits 0 (exit 2 + `TIMEOUT` after 60 s: a hang is a bug). Use with `-FSNoCloud` so the feed is not fetched. |
| `-FSTextSize <name>` | **Mac.** Fixes the text size for one launch: `default`, `xLarge` … `ax5` (`largest`). |
| `-FSAppearance light\|dark` | **Mac.** Fixes the appearance for one launch (UI tests). |
| `-FSSnapshot <dir>` | **Mac, DEBUG builds only.** Draws the Mac screenshot matrix to PNGs and exits (see below). `-FSSnapshotScreens a,b` limits it; `-FSSnapshotTall` adds whole-page renders. |

Both are parsed by `ShieldCore.LaunchOptions.current`. UI tests must always pass one of them. The
shared schemes include both arguments in the Run action, turned off. Tick them in Edit Scheme to use them.

### Demo states (`-FSDemoState <name>`, ShieldUI `DemoScreen`)

Each name opens one screen with fixed data run through the real StatusEngine and scam rules:
`welcome`, `join`, `joinWaiting`, `keepChecking` (Mac), `keepCheckingApproval` (Mac), `whoToCall`, `reminders`, `accountsPicker`, `homeProtected`,
`homeOneRed`, `homeOneToDo`, `homeFirstRun`, `homeBuildBanner`, `homeAccounts`, `fixStep`, `guidedStep`,
`guidedCarrier`, `guidedCodeWord`, `optionalStep` (Mac), `serviceSteps`, `scamEntry`, `pasteMessage`, `resultDanger`,
`resultCareful`, `resultNoSigns`, `callQuiz`, `familyRules`, `about`, `aboutStopSharing`,
`startFamily`, `familyTab`, `addPerson`, `deviceDetail`, `feedHealth`. The ShieldCore names
`firstRun`, `protected`, `oneRed`, `accounts` open Home. Demo models never measure, never touch
CloudKit, the Keychain or the network, and never ask for notification permission.

### Screenshot matrix (§13.2)

- With Ben present: `xcodebuild test -scheme ShieldiOS` on `iPhone 17 Pro` and on `iPhone 17e` runs
  `ShieldiOSUITests` (light/dark × default/AX5, screenshots attached, `performAccessibilityAudit`
  per screen). Export: `xcrun xcresulttool export attachments --path <result.xcresult> --output-path docs/screenshots/ios`.
  Each failing audit issue is also printed as `AUDIT <state> (<variant>): …` with the element's label and
  frame. Prefix the command with `TEST_RUNNER_FS_MATRIX_STATES=familyTab,feedHealth` to run only those states.
- Unattended (no Developer Tools prompt): `tools/ios-screenshots.sh <udid> iPhone17Pro <dir>` drives
  the Simulator with `simctl` using the same launch arguments. `docs/screenshots/ios/` holds that
  output, downscaled 50% and palette-compressed.

- Mac, with Ben present: `xcodebuild test -scheme ShieldMac` runs `ShieldMacUITests` (main window × 22
  screens and the menu-bar panel × 3 words, light/dark × default/largest text, screenshots attached,
  `performAccessibilityAudit` per screen, keyboard-navigation and call-quiz flows). macOS UI tests
  need the test runner to be allowed under Privacy & Security → Accessibility; Ben grants that.
- Mac, unattended: `tools/mac-screenshots.sh` runs the DEBUG app with `-FSNoCloud -FSSnapshot`. The
  app draws its own windows into PNGs (no Screen Recording, Accessibility or Developer Tools
  prompt) at 1×, palette-compressed if Pillow is installed. `docs/screenshots/mac/` holds that output:
  `mac-<light|dark>-<default|ax5>-<screen>.png` and `menubar-…-<homeProtected|homeOneToDo|homeOneRed>.png`.
  These are SwiftUI renders of the real views; the menu-bar strip above each panel is drawn by the
  snapshot tool (the real status item lives in the system menu bar).

### Mac smoke test (§13.3), headless

```sh
"build/DerivedData/Build/Products/Debug/Family Shield.app/Contents/MacOS/Family Shield" -FSNoCloud -FSRunChecksAndPrint
```

### Mac keyboard (§11)

Go menu: Home ⌘1, Family ⌘2 (Ben), Back ⌘[ (or Escape), Is this a scam? ⌘K, Family Rules, Call
Ben ⇧⌘B (opens Who to call when no number is picked yet), Check Again ⌘R (on Ben's Family tab the same item is **Refresh** and fetches the dashboard; the tab also
has a visible Refresh button, and opening or selecting the Family tab refreshes it on both
platforms). About & Privacy ⌘, (Family Shield's settings screen). View: Bigger Text ⌘+, Smaller Text
⌘−, Actual Size ⌘0 (macOS has no Dynamic Type for SwiftUI text, so this is the app's own size; the
default is the iPhone "Large" size, body 17 pt). Inside a screen, with macOS defaults: Return presses the
screen's one main button (Get started, Continue, Done, Open System Settings, Call Ben on a scam
result, Next…), ⌘Return is **Check it** on Paste a message (Return types a new line there) and
**Next** / **Done** on a fix step whose Return is already Open System Settings or Call Ben, and the number keys 1–9 pick an
answer in the call quiz and in the I did it / Not sure / Not now answers. Tab moves between controls
when macOS Keyboard Navigation is on; Family Shield buttons draw a 3 pt focus ring.

### Mac login item (§10.2)

`SMAppService.mainApp.register()` is called only from the **Keep checking in the background** button
(first launch, after Join, and again in About → Background checks). Nothing registers at launch, in
demo states, in tests or in `-FSRunChecksAndPrint`. Reading the status never shows UI. A copy that macOS
can't use as a login item (`.notFound`, for example unsigned or outside Applications) shows "Ben will
turn on background checks for you"; this has not been tried on a signed build yet.

## Build date (`FSBuildDate`, §6.1 `app_build_fresh`)

Both app targets end with a **Stamp FSBuildDate** run-script phase. On every build it writes today's
UTC date (`YYYY-MM-DD`, from the local clock, no network) into the built product's Info.plist with
`PlistBuddy`. `BuildInfo` reads it before the executable's modification date, so About, Feed &
release health and the day-60 banner use the real build day. To check a build:
`/usr/libexec/PlistBuddy -c "Print :FSBuildDate" "<Family Shield.app>/Info.plist"` (iOS) or
`".../Family Shield.app/Contents/Info.plist"` (Mac). `BuildDateStampTests` guards the phase.

## Link and URL tools (§12.4)

| Script | Who runs it | What it does |
|---|---|---|
| `tools/url-lint.sh` | anyone, CI | Fails if `URL(string:` appears in app or ShieldCore Swift outside `DeepLinks.swift` / `Services.swift` (comment lines ignored). Same rule as `CatalogLintTests`. |
| `tools/link-check.sh [-v] [--strict]` | anyone, CI (network) | `curl -sI` on every https constant in `DeepLinks.swift`, `Services.swift` and `catalog.json`, following redirects (GET when HEAD is refused). Prints every non-2xx/3xx answer: **FAIL** (the page is gone, or a 200 "Page Not Found" soft 404 like the ones support.apple.com sends) exits 1. **BLOCKED** (the site's home page refuses curl too, so it's bot protection) and **SIGNIN** (a 401, or a redirect to the site's own sign-in page) are warnings to check in a browser. `--strict` fails on those too. |
| `tools/deeplink-test.sh --ben` | **Ben only, at the Mac** | Opens each `x-apple.systempreferences:` link in turn and asks whether the right pane opened. **Agents must never run it**: it opens System Settings. It refuses to start without `--ben`, `FS_BEN_AT_MAC=1` and an interactive terminal, and it refuses inside Claude Code. |

Last link-check (2026-10-23): 40 URLs, 0 failed, 4 warnings. Each warning page was opened in a
browser the same day and is the right page: `consumer.ftc.gov` (answers curl with 404, even for
its home page), `www.ssa.gov/myaccount/` and `www.transunion.com/credit-freeze` (403 to curl), and
`www.paypal.com/myaccount/security/` (redirects to PayPal's sign-in, as an account page should).

## Project layout rules for builders

- `FamilyShield.xcodeproj` uses **folder-synchronized groups** (`PBXFileSystemSynchronizedRootGroup`)
  for `ShieldiOS/`, `ShieldMac/`, `UITests/ShieldiOSUITests/` and `UITests/ShieldMacUITests/`.
  To add a file, create it in the right folder. **Do not edit `project.pbxproj` to add files.**
- In a synchronized folder, every non-source file becomes a bundle resource. Do not put `.gitkeep`,
  README or notes files in app or UI-test folders: two `.gitkeep` files break the build with
  "Multiple commands produce". `Info.plist` and `*.entitlements` are kept out by the folder's
  exception set.
- The app targets link both package products, `ShieldCore` and `ShieldUI`, from the local package
  `ShieldCore/`.
- Package resources (catalog.json, `Version/snapshot/*.json`, `Catalog/Strings/*.xcstrings`) must be
  declared in `ShieldCore/Package.swift` under the `ShieldCore` target's `resources:` when you add
  them. Test fixtures go in `ShieldCore/Tests/Fixtures/`, which is already copied into the test
  bundle: `Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures")`.
- Empty ShieldCore source folders hold a `.gitkeep`. SwiftPM ignores hidden files. Delete the
  `.gitkeep` once the folder has real files.

## Signing (for Ben, not for agents)

- Team and bundle prefix come from `Config/Identity.local.xcconfig`; automatic signing on all targets. Dev builds and agent builds use
  `CODE_SIGNING_ALLOWED=NO`.
- iOS entitlements set `aps-environment = production`, as SPEC §4 says. If a signed **Development**
  run fails with an aps-environment profile mismatch, that comes from this value. Check it during
  Spike S1.
- Mac: Hardened Runtime on with no exceptions, App Sandbox off (`ENABLE_APP_SANDBOX = NO`, and no
  sandbox key in the entitlements). Release distribution uses Developer ID and Direct Distribution
  (SPEC §14.3).
- Neither app has an asset catalog or app icon yet. Add one before the first archive.
