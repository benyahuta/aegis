import XCTest
import SwiftUI
import os
import ShieldCore
@testable import ShieldUI

/// The Mac pieces of the shared screens (SPEC §10.2, §10.3, §11, §13.2).
@MainActor
final class MacUITests: XCTestCase {
    private let day = DateDay(year: 2026, month: 10, day: 22)!

    /// Counts calls so tests can prove the login item is registered only from the button.
    final class LoginItemSpy: Sendable {
        let calls = OSAllocatedUnfairLock(initialState: (status: 0, register: 0, settings: 0))
        let registerResult: LoginItemState
        init(registerResult: LoginItemState) { self.registerResult = registerResult }

        var control: LoginItemControl {
            LoginItemControl(
                status: { self.calls.withLock { $0.status += 1 }; return .off },
                register: { self.calls.withLock { $0.register += 1 }; return self.registerResult },
                openSettings: { self.calls.withLock { $0.settings += 1 } }
            )
        }
    }

    private func makeModel(platform: Platform = .mac, loginItem: LoginItemControl? = nil,
                           mdm: OwnerMacSetting? = nil, sync: SyncServices = .inMemory()) -> AppModel {
        let clock = Clock.fixed(day.date.addingTimeInterval(9 * 3_600))
        let catalog = CheckCatalog.shared
        let today = clock.today()
        let measured = MacDemoState.protected.outcomes.map { $0.measuredResult(today: today) }
        let services = PlatformServices(measure: { measured }, loginItem: loginItem, mdmExpected: mdm)
        return AppModel(
            platform: platform, options: LaunchOptions(noCloud: true), clock: clock, catalog: catalog, osMajor: 26,
            selfReports: SelfReportStore(persistence: InMemoryPersistence(), pacing: Pacing(catalog: catalog, platform: platform), clock: clock),
            notifier: LocalNotifier(scheduler: DisabledNotificationScheduler(), persistence: InMemoryPersistence(), clock: clock),
            sync: sync, callBenStore: InMemoryCallBenStore(nil), uiState: .inMemory(), services: services,
            build: BuildInfo(version: "1.0", build: 7, buildDay: today.adding(days: -5))
        )
    }

    // MARK: Login item (§10.2)

    func testLoginItemIsNeverRegisteredWithoutTheButton() async {
        let spy = LoginItemSpy(registerResult: .on)
        let model = makeModel(loginItem: spy.control)
        await model.start()
        await model.refresh()
        model.refreshLoginItemState()
        XCTAssertEqual(spy.calls.withLock { $0.register }, 0, "launch, checks and state reads never register")
        XCTAssertEqual(model.loginItemState, .off)

        XCTAssertEqual(model.keepCheckingInBackground(), .on)
        XCTAssertEqual(spy.calls.withLock { $0.register }, 1)
        XCTAssertEqual(spy.calls.withLock { $0.settings }, 0, "System Settings opens only when approval is needed")
        XCTAssertEqual(model.loginItemState, .on)
    }

    func testNeedsApprovalOpensLoginItemsSettings() {
        let spy = LoginItemSpy(registerResult: .needsApproval)
        let model = makeModel(loginItem: spy.control)
        XCTAssertEqual(model.keepCheckingInBackground(), .needsApproval)
        XCTAssertEqual(spy.calls.withLock { $0.settings }, 1)
        XCTAssertEqual(model.loginItemState, .needsApproval)
    }

    func testMacOnboardingShowsKeepCheckingAfterJoin() {
        let model = makeModel(loginItem: LoginItemControl.fixed(.off))
        model.next(after: .welcome)
        model.next(after: .join)
        XCTAssertEqual(model.onboardingPath, [.join, .keepChecking])
        model.next(after: .keepChecking)
        XCTAssertEqual(model.onboardingPath.last, .whoToCall)
    }

    func testIPhoneOnboardingSkipsKeepChecking() {
        let model = makeModel(platform: .ios)
        XCTAssertFalse(model.hasLoginItem)
        model.next(after: .join)
        XCTAssertEqual(model.onboardingPath, [.whoToCall])
    }

    func testLoginItemDeepLinkIsTheVerifiedSettingsURL() {
        XCTAssertEqual(DeepLink.macLoginItems.urlString, "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    // MARK: Ben's own Mac (§6.2, §10.3)

    func testMDMExpectedSwitchIsOwnerMacOnly() async {
        let box = OSAllocatedUnfairLock(initialState: false)
        let setting = OwnerMacSetting(get: { box.withLock { $0 } }, set: { value in box.withLock { $0 = value } })
        let family = makeModel(mdm: setting)
        XCTAssertFalse(family.showsOwnerMacSection)
        XCTAssertFalse(family.canMarkMDMExpected)
        family.setMDMExpected(true)
        XCTAssertFalse(box.withLock { $0 }, "a relative's copy can never mark MDM expected")

        let ben = makeModel(mdm: setting)
        _ = await ben.startFamily() // no iCloud here: sample Family tab, owner mode on
        XCTAssertTrue(ben.showsOwnerMacSection)
        XCTAssertTrue(ben.canMarkMDMExpected)
        ben.setMDMExpected(true)
        XCTAssertTrue(box.withLock { $0 })
        XCTAssertTrue(ben.mdmExpected)
    }

    func testOwnerMacSectionListsBenOnlyItems() async {
        let model = makeModel()
        await model.refresh()
        let ids = model.snapshot.benOnly.map(\.checkID)
        XCTAssertTrue(ids.contains(.betaCatalog))
        XCTAssertFalse(model.snapshot.familyItems.contains { $0.checkID == .betaCatalog }, "never shown to the relative")
    }

    // MARK: Menu bar (§10.2)

    func testMenuBarWordsAndSymbols() {
        let protected = AppModel.demo(.homeProtected, platform: .mac)
        XCTAssertEqual(protected.snapshot.home.menuBarWord, "Protected")
        XCTAssertEqual(MenuBarLabelContent.symbol(protected.snapshot.home), "checkmark.shield")

        let oneToDo = AppModel.demo(.homeOneToDo, platform: .mac)
        XCTAssertEqual(oneToDo.snapshot.home.menuBarWord, "1 to do")
        XCTAssertEqual(MenuBarLabelContent.symbol(oneToDo.snapshot.home), "exclamationmark.shield")

        let today = AppModel.demo(.homeOneRed, platform: .mac)
        XCTAssertEqual(today.snapshot.home.menuBarWord, "Today")
        XCTAssertEqual(MenuBarLabelContent.symbol(today.snapshot.home), "exclamationmark.shield.fill")
    }

    // MARK: Demo screens (§13.2 Mac matrix)

    func testEveryMacMatrixScreenBuildsInMemory() {
        for screen in DemoScreen.macScreenshotMatrix {
            let model = AppModel.demo(screen, platform: .mac)
            XCTAssertNotNil(model.demo, screen.rawValue)
            XCTAssertFalse(model.sync.usesCloud, screen.rawValue)
            XCTAssertNotNil(model.loginItemState, "\(screen.rawValue): fixed login-item state, never the real one")
            // A fix or guided screen must show a check that exists on the Mac (not "couldn't check").
            for route in model.homePath {
                switch route {
                case .fix(let id), .guided(let id), .optional(let id):
                    XCTAssertNotNil(model.item(id), "\(screen.rawValue): \(id.rawValue) is not a Mac item")
                default:
                    break
                }
            }
        }
        XCTAssertEqual(AppModel.demo(.keepChecking, platform: .mac).onboardingPath.last, .keepChecking)
        XCTAssertEqual(AppModel.demo(.keepCheckingApproval, platform: .mac).loginItemState, .needsApproval)
        XCTAssertNil(AppModel.demo(.homeProtected, platform: .ios).loginItemState, "no login item on iPhone")
    }

    // MARK: Text size (§11)

    func testMacTextSizeParsingAndSteps() {
        XCTAssertEqual(ShieldTypeScale.size(named: "default"), .large)
        XCTAssertEqual(ShieldTypeScale.size(named: "largest"), .accessibility5)
        XCTAssertEqual(ShieldTypeScale.size(named: "ax5"), .accessibility5)
        XCTAssertEqual(ShieldTypeScale.size(named: "accessibility3"), .accessibility3)
        XCTAssertEqual(ShieldTypeScale.size(named: "UICTContentSizeCategoryAccessibilityXXXL"), .accessibility5)
        XCTAssertEqual(ShieldTypeScale.size(named: "xxLarge"), .xxLarge)
        XCTAssertNil(ShieldTypeScale.size(named: "huge"))
        for size in ShieldTypeScale.sizes {
            XCTAssertEqual(ShieldTypeScale.size(named: ShieldTypeScale.name(size)), size, "round trip \(size)")
        }
        XCTAssertEqual(ShieldTypeScale.step(.large, by: -1), .large, "Actual Size is the smallest Mac step")
        XCTAssertEqual(ShieldTypeScale.step(.accessibility5, by: 1), .accessibility5)
        XCTAssertEqual(ShieldTypeScale.step(.xxxLarge, by: 1), .accessibility1)
        XCTAssertEqual(ShieldTypeScale.launchSize(["app", "-FSTextSize", "ax5"]), .accessibility5)
        XCTAssertNil(ShieldTypeScale.launchSize(["app", "-FSTextSize"]))
    }

    func testTypeScaleGrowsAndMatchesTheIPhoneTable() {
        XCTAssertEqual(ShieldTypeScale.points(.body, .large), 17)
        XCTAssertEqual(ShieldTypeScale.points(.body, .accessibility5), 53)
        XCTAssertEqual(ShieldTypeScale.points(.largeTitle, .large), 34)
        for style in [Font.TextStyle.largeTitle, .title, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote] {
            let points = ShieldTypeScale.sizes.map { ShieldTypeScale.points(style, $0) }
            XCTAssertEqual(points.count, 12)
            XCTAssertEqual(points, points.sorted(), "\(style) never shrinks as the size grows")
        }
    }

    // MARK: Copy

    func testMacPlatformKeysExist() {
        for base in ["scam.paste.hint", "join.waiting", "join.waiting.detail", "welcome.body"] {
            for platform in Platform.allCases {
                XCTAssertTrue(ShieldStrings.contains(L.platformKey(base, platform)), L.platformKey(base, platform))
            }
        }
        // macOS 13+ shows its own "Background Items Added" notice naming the app; quote that, not a
        // sentence macOS never shows.
        XCTAssertTrue(L.t("loginItem.expected").contains("'Background Items Added'"), "§10.2 copy")
        XCTAssertFalse(L.t("loginItem.expected").contains("added to Login Items"), "§10.2 copy")
        XCTAssertEqual(L.t("loginItem.action"), "Keep checking in the background")
        XCTAssertEqual(L.t("loginItem.approval.title"), "Turn on Family Shield")
        XCTAssertEqual(L.fill("menubar.a11y", ["word": "Today"]), "Family Shield: Today")
    }

    /// The Mac app shell (ShieldMac/) reads copy through `L` too; every literal key must exist.
    func testEveryShieldMacKeyExistsInTheCatalog() throws {
        let root = UICopyTests.shieldUIRoot
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ShieldMac")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw XCTSkip("ShieldMac sources not readable")
        }
        let regex = try NSRegularExpression(pattern: #"L\.(?:t|a|plain|fill|plural)\("([A-Za-z0-9_.]+)""#)
        var keys: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { keys.insert(String(text[range])) }
            }
        }
        if keys.isEmpty { throw XCTSkip("no ShieldMac sources found at \(root.path)") }
        let missing = keys.filter { !ShieldStrings.contains($0) }.sorted()
        XCTAssertTrue(missing.isEmpty, "missing from Localizable.xcstrings: \(missing)")
    }

    // MARK: Picture files (§10.2 drag and drop / file picker)

    func testDroppedImageRefusesEmptyAndHugeData() {
        XCTAssertThrowsError(try DroppedImage(data: Data()))
        XCTAssertThrowsError(try DroppedImage(data: Data(count: DroppedImage.maxBytes + 1)))
        XCTAssertNoThrow(try DroppedImage(data: Data([0x89, 0x50, 0x4E, 0x47])))
    }

    func testDroppedImageRefusesNonImageFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fs-not-an-image-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try DroppedImage(fileURL: url))
    }
}
