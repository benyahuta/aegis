// `-FSDemoState <name>` screens (SPEC §13.2 screenshot matrix). Each name opens one screen with
// fixed data, fed through the real StatusEngine and scam rules, so screenshots show real copy.
// Demo models are fully in memory: no CloudKit, no network, no Keychain, no notification prompt,
// no contact picker. The ShieldCore `DemoState` names (firstRun, protected, oneRed, accounts) are
// accepted too and open Home with that data.

import Foundation
import os
import ShieldCore

public enum DemoScreen: String, CaseIterable, Sendable {
    // §10.1 family member
    case welcome
    case join
    case joinWaiting
    /// §10.2 Mac first launch: the login-item screen, before and after "needs approval".
    case keepChecking
    case keepCheckingApproval
    case whoToCall
    case reminders
    case accountsPicker
    case homeProtected
    case homeOneRed
    /// Exactly one amber item ("1 thing to do"; the Mac menu bar says "1 to do").
    case homeOneToDo
    case homeFirstRun
    case homeBuildBanner
    case homeAccounts
    case fixStep
    case guidedStep
    case guidedCarrier
    case guidedCodeWord
    /// Mac: About → Optional extras → Advanced Data Protection (the "talk to Ben first" warning).
    /// v1 ships P0 checks only, and the Mac's `adp` is the only P0 Advanced Data Protection item.
    case optionalStep
    case serviceSteps
    case scamEntry
    case pasteMessage
    case resultDanger
    case resultCareful
    case resultNoSigns
    case callQuiz
    case familyRules
    case about
    case aboutStopSharing
    // §10.3 Ben
    case startFamily
    case familyTab
    case addPerson
    case deviceDetail
    case feedHealth

    /// Accepts the raw value (any case) and the ShieldCore `DemoState` names.
    public init?(name: String) {
        if let exact = DemoScreen(rawValue: name) {
            self = exact
            return
        }
        let folded = name.lowercased().filter { $0.isLetter || $0.isNumber }
        if let match = DemoScreen.allCases.first(where: { $0.rawValue.lowercased() == folded }) {
            self = match
            return
        }
        switch folded {
        case "firstrun": self = .homeFirstRun
        case "protected": self = .homeProtected
        case "onered": self = .homeOneRed
        case "accounts": self = .homeAccounts
        default: return nil
        }
    }

    /// The screens in the §13.2 matrix (iPhone).
    public static let screenshotMatrix: [DemoScreen] = [
        .welcome, .join, .whoToCall, .reminders, .accountsPicker, .homeProtected, .homeOneRed,
        .fixStep, .guidedStep, .scamEntry, .resultDanger, .resultCareful, .resultNoSigns, .callQuiz,
        .familyRules, .about, .familyTab, .deviceDetail,
    ]

    /// The screens in the §13.2 Mac matrix (main window).
    public static let macScreenshotMatrix: [DemoScreen] = [
        .welcome, .join, .keepChecking, .keepCheckingApproval, .whoToCall, .reminders, .accountsPicker,
        .homeProtected, .homeOneRed, .fixStep, .guidedStep, .scamEntry, .pasteMessage, .resultDanger,
        .resultCareful, .resultNoSigns, .callQuiz, .familyRules, .about, .optionalStep, .familyTab, .deviceDetail, .feedHealth,
    ]

    /// The login-item state a Mac demo screen shows (never registers anything).
    var loginItemState: LoginItemState {
        switch self {
        case .keepChecking: .off
        case .keepCheckingApproval: .needsApproval
        default: .on
        }
    }

    /// The fixed "now" for demo screens: 2026-10-22 at 9:14 AM local time ("Checked today at 9:14 AM").
    public static var demoNow: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 22
        components.hour = 9
        components.minute = 14
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_792_660_440)
    }

    /// Sample texts for the result screens. Checked by ShieldUITests to give these verdicts.
    public static let dangerSample = "USPS: Your package is on hold because of an unpaid fee. Pay $1.99 within 24 hours at usps-redelivery.top/pay or it will be returned."
    public static let carefulSample = "Hi Mom, this is my new number. I lost my phone. Can you text me back here?"
    public static let noSignsSample = "Hi! Just a reminder that dinner is at 6 on Sunday. Bring the pie if you can."

    var dataState: DemoState {
        switch self {
        case .welcome, .join, .joinWaiting, .keepChecking, .keepCheckingApproval, .whoToCall, .reminders, .accountsPicker, .homeFirstRun, .guidedStep,
             .guidedCodeWord:
            .firstRun
        case .homeOneRed, .fixStep:
            .oneRed
        case .homeAccounts, .serviceSteps, .guidedCarrier:
            .accounts
        default:
            .protected
        }
    }

    var isOwner: Bool {
        switch self {
        case .familyTab, .addPerson, .deviceDetail, .feedHealth: true
        default: false
        }
    }

    var onboarding: (OnboardingStep, [OnboardingStep]) {
        switch self {
        case .welcome: (.welcome, [])
        case .join, .joinWaiting: (.welcome, [.join])
        case .keepChecking, .keepCheckingApproval: (.welcome, [.join, .keepChecking])
        case .whoToCall: (.welcome, [.join, .whoToCall])
        case .reminders: (.welcome, [.join, .whoToCall, .reminders])
        case .accountsPicker: (.welcome, [.join, .whoToCall, .reminders, .accounts])
        case .startFamily: (.welcome, [.startFamily])
        default: (.done, [])
        }
    }

    func homePath(platform: Platform) -> [Route] {
        switch self {
        case .fixStep: [.fix(.osPatched)]
        // Stolen Device Protection is iPhone-only; the Mac shows its own Group 1 guided step.
        case .guidedStep: [.guided(platform == .mac ? .recoveryContact : .stolenDeviceProtection)]
        case .guidedCarrier: [.guided(.carrierLock)]
        case .guidedCodeWord: [.guided(.familyCodeWord)]
        case .optionalStep: [.about, .optional(platform == .mac ? .adp : .advancedDataProtection)]
        case .serviceSteps: [.service(.bank)]
        case .scamEntry: [.scamEntry]
        case .pasteMessage: [.scamEntry, .pasteMessage]
        case .resultDanger, .resultCareful, .resultNoSigns: [.scamEntry, .pasteMessage, .scamResult]
        case .callQuiz: [.scamEntry, .callQuiz]
        case .familyRules: [.familyRules]
        case .about, .aboutStopSharing: [.about]
        default: []
        }
    }

    var familyPath: [FamilyRoute] {
        switch self {
        case .addPerson: [.addPerson]
        case .deviceDetail: [.device(zoneName: DemoFamily.momZone, deviceID: DemoFamily.momPhone)]
        case .feedHealth: [.feedHealth]
        default: []
        }
    }

    var connection: SyncConnectionState {
        switch self {
        case .joinWaiting, .welcome: .notJoined
        default: .connected
        }
    }

    var scamDraft: String {
        switch self {
        case .pasteMessage, .resultDanger: DemoScreen.dangerSample
        case .resultCareful: DemoScreen.carefulSample
        case .resultNoSigns: DemoScreen.noSignsSample
        default: ""
        }
    }

    /// Builds a fully in-memory model for this screen.
    @MainActor
    public func makeModel(platform: Platform, options: LaunchOptions = LaunchOptions(noCloud: true)) -> AppModel {
        let catalog = CheckCatalog.shared
        let clock = Clock.fixed(DemoScreen.demoNow)
        let today = clock.today()
        let state = dataState.selfReports(catalog: catalog, platform: platform, today: today)
        var stateWithExtras = state
        if self == .guidedCarrier { stateWithExtras.carrier = .verizon }
        if self == .accountsPicker { stateWithExtras.selectedServices = [.gmail, .bank, .facebook] }
        let persistence = InMemoryPersistence(try? JSONEncoder().encode(stateWithExtras))
        let pacing = Pacing(catalog: catalog, platform: platform)
        let ui = UIStateStore.inMemory()
        ui.enrolledOn = today.adding(days: -30)
        let build = BuildInfo(version: "1.0", build: 12,
                              buildDay: today.adding(days: self == .homeBuildBanner ? -61 : -12))
        return AppModel(
            platform: platform, options: options, clock: clock, catalog: catalog,
            selfReports: SelfReportStore(persistence: persistence, pacing: pacing, clock: clock),
            notifier: LocalNotifier(scheduler: DisabledNotificationScheduler(), persistence: InMemoryPersistence(), clock: clock),
            sync: .inMemory(deviceID: DemoFamily.thisDevice),
            callBenStore: InMemoryCallBenStore(self == .whoToCall ? nil : DemoFamily.benNumber),
            uiState: ui,
            services: PlatformServices(measure: { [] }, canPickContact: true,
                                       pickContactNumber: { DemoFamily.benNumber },
                                       loginItem: platform == .mac ? .fixed(loginItemState) : nil,
                                       mdmExpected: platform == .mac ? DemoScreen.inMemorySetting() : nil),
            build: build,
            demo: self
        )
    }

    /// A local switch that lives only in this process (demo screens never write defaults).
    static func inMemorySetting(_ initial: Bool = false) -> OwnerMacSetting {
        let box = OSAllocatedUnfairLock(initialState: initial)
        return OwnerMacSetting(get: { box.withLock { $0 } }, set: { value in box.withLock { $0 = value } })
    }

    /// Fills the model's state for this screen (called from AppModel.init).
    @MainActor
    func apply(to model: AppModel) {
        let today = model.clock.today()
        var measured = dataState.measured(catalog: model.catalog, platform: model.platform, today: today)
        if self == .homeOneToDo {
            let id: CheckID = model.platform == .mac ? .filevault : .biometricsEnrolled
            measured.removeAll { $0.checkID == id }
            measured.append(MeasuredResult(checkID: id, status: .fail, checkedOn: today))
        }
        if self == .homeBuildBanner {
            measured.removeAll { $0.checkID == .appBuildFresh }
            measured.append(MeasuredResult(checkID: .appBuildFresh, status: .fail, checkedOn: today))
        }
        let feedState = FeedStore.bundledSnapshot(for: model.platform).map {
            FeedState(feed: $0.feed, fetchedAt: DemoScreen.demoNow.addingTimeInterval(-2 * 3_600), origin: .cache)
        }
        let (step, path) = onboarding
        model.applyDemo(onboarding: step, onboardingPath: path, homePath: homePath(platform: model.platform), familyPath: familyPath,
                        tab: isOwner ? .family : .home, owner: isOwner, connection: connection,
                        measured: measured, feed: FeedInfo(state: feedState, now: DemoScreen.demoNow),
                        lastChecked: DemoScreen.demoNow)
        let draft = scamDraft
        let outcome: ScamOutcome? = switch self {
        case .resultDanger, .resultCareful, .resultNoSigns:
            ScamOutcome(assessment: ScamChecker.assess(text: draft), origin: .message, originalText: draft)
        default:
            nil
        }
        model.applyDemoScam(draft: draft, outcome: outcome)
        if self == .aboutStopSharing { model.showStopSharingConfirm = true }
    }
}

extension AppModel {
    /// A demo model for `screen`.
    public static func demo(_ screen: DemoScreen, platform: Platform,
                            options: LaunchOptions = LaunchOptions(noCloud: true)) -> AppModel {
        screen.makeModel(platform: platform, options: options)
    }
}
