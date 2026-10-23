// The shared app model for the iPhone and Mac screens (SPEC §10). Owns the StatusEngine snapshot,
// the person's answers, sync state, Ben's owner features and the in-memory scam session.
//
// Rules it keeps:
// - Local evaluation is the only truth (§8.4); results go to the ResultSink, nothing is read back.
// - H7: anything unknown stays grey. H2: no field here holds a password, code or PIN.
// - The scam text, screenshot and verdict live only in memory while the scam screens are open. A
//   screenshot check still running when the person leaves is discarded, never shown later.
// - Notification permission is asked ONLY from the Reminders [Yes] tap (onboarding, or the same
//   screen opened again from About).

import CloudKit
import Foundation
import Observation
import ShieldCore

@MainActor
@Observable
public final class AppModel {
    // MARK: Dependencies

    public let platform: Platform
    public let options: LaunchOptions
    public let catalog: CheckCatalog
    public let build: BuildInfo
    /// Set when running a `-FSDemoState` screen.
    public let demo: DemoScreen?
    @ObservationIgnored public let clock: Clock
    @ObservationIgnored public let sync: SyncServices
    @ObservationIgnored let engine: StatusEngine
    @ObservationIgnored let selfReports: SelfReportStore
    @ObservationIgnored let notifier: LocalNotifier
    @ObservationIgnored let callBenStore: any CallBenNumberStore
    @ObservationIgnored let uiState: UIStateStore
    @ObservationIgnored let services: PlatformServices

    // MARK: State

    public private(set) var snapshot: StatusSnapshot
    public private(set) var lastCheckedAt: Date?
    public private(set) var isRefreshing = false
    public var onboarding: OnboardingStep {
        didSet { uiState.onboarding = onboarding }
    }
    public var onboardingPath: [OnboardingStep] = []
    public var homePath: [Route] = [] {
        didSet { endScamSessionIfLeft() }
    }
    public var familyPath: [FamilyRoute] = []
    /// Opening or selecting the Family tab fetches the latest reports (§10.3, §8.4 dashboard read).
    public var selectedTab: MainTab = .home {
        didSet {
            if selectedTab == .family, oldValue != .family { familyTabOpened() }
        }
    }
    public private(set) var connection: SyncConnectionState
    public private(set) var isOwner: Bool
    public private(set) var dashboard: FamilyDashboard?
    /// The Family tab shows sample data (no iCloud in this copy).
    public private(set) var dashboardIsSample = false
    public private(set) var dashboardMessage: String?
    /// A Family tab fetch is in flight (the Mac's Refresh button and ⌘R show it).
    public private(set) var isRefreshingDashboard = false
    public private(set) var benNumber: String?
    public private(set) var feedInfo: FeedInfo?
    /// The person said [Yes] to reminders (whatever the system answered).
    public private(set) var remindersWanted: Bool
    /// The system allows this app's notifications (re-read at the start of every check, so turning
    /// them on in Settings later takes effect). nil until it has been read this launch: the
    /// screens then say neither "on" nor "turned off in Settings".
    public private(set) var remindersAllowed: Bool?
    /// Reminders are actually on: wanted and allowed.
    public var remindersOptIn: Bool { remindersWanted && remindersAllowed == true }
    /// The person said [Yes] but the system said no (now or earlier): show how to turn them on.
    public var remindersBlocked: Bool { remindersWanted && remindersAllowed == false }
    /// About's Reminders row: what the person chose, unless the system is known to block it.
    public var remindersShownOn: Bool { remindersWanted && remindersAllowed != false }
    /// The Mac login item (§10.2); nil on iPhone.
    public private(set) var loginItemState: LoginItemState?
    /// Ben's own Mac: "this Mac's device management is expected" (§6.2, local only).
    public private(set) var mdmExpected: Bool
    public private(set) var accountsPromptDismissed: Bool
    /// A one-off message shown on About (stop sharing) or Ben's screens.
    public var notice: String?
    public var showStopSharingConfirm = false

    // Scam session (memory only).
    public var scamDraft: String = ""
    public private(set) var scamOutcome: ScamOutcome?
    public private(set) var isCheckingScam = false
    /// A pasted message is being checked (off the main actor); the Check button waits for it.
    public private(set) var isCheckingMessage = false
    /// Bumped whenever the scam session ends, so a screenshot check still running is discarded.
    @ObservationIgnored private var scamSession = 0

    /// nil until the first measurement of this launch finishes (Home says "Checking now", never
    /// "protected", until then; H7).
    @ObservationIgnored private var measured: [MeasuredResult]?
    /// `register()` threw this launch while the login item stayed off.
    @ObservationIgnored private var loginItemRegisterFailed = false
    /// The fetch started by opening the Family tab (tests await it).
    @ObservationIgnored var familyTabRefresh: Task<Void, Never>?
    @ObservationIgnored private var started = false

    // MARK: Init

    public init(
        platform: Platform,
        options: LaunchOptions,
        clock: Clock,
        catalog: CheckCatalog = .shared,
        osMajor: Int = Platform.currentOSMajor,
        biometry: Biometry? = nil,
        selfReports: SelfReportStore,
        notifier: LocalNotifier,
        sync: SyncServices,
        callBenStore: any CallBenNumberStore,
        uiState: UIStateStore,
        services: PlatformServices,
        build: BuildInfo = .current,
        demo: DemoScreen? = nil
    ) {
        self.platform = platform
        self.options = options
        self.clock = clock
        self.catalog = catalog
        // Face ID or Touch ID wording on iPhone. Demo states and the Mac keep the copy that names both.
        let biometry = biometry ?? Self.deviceBiometry(platform: platform, demo: demo)
        self.engine = StatusEngine(catalog: catalog, platform: platform, osMajor: osMajor, biometry: biometry, clock: clock)
        self.selfReports = selfReports
        self.notifier = notifier
        self.sync = sync
        self.callBenStore = callBenStore
        self.uiState = uiState
        self.services = services
        self.build = build
        self.demo = demo
        self.onboarding = uiState.onboarding
        self.connection = sync.settings.connection
        self.isOwner = sync.settings.isOwner
        self.remindersWanted = uiState.remindersOptIn
        self.accountsPromptDismissed = uiState.accountsPromptDismissed
        self.benNumber = callBenStore.load()
        self.loginItemState = services.loginItem?.status()
        self.mdmExpected = services.mdmExpected?.get() ?? false
        self.snapshot = StatusEngine(catalog: catalog, platform: platform, osMajor: osMajor, biometry: biometry, clock: clock)
            .evaluate(measured: nil, selfReports: selfReports.current)
        demo?.apply(to: self)
    }

    /// The iPhone's sensor, read without any prompt. `.unknown` on the Mac, in demo states
    /// (fixed screenshots) and in host tests.
    static func deviceBiometry(platform: Platform, demo: DemoScreen?) -> Biometry {
        #if os(iOS)
        guard platform == .ios, demo == nil else { return .unknown }
        return Biometry.read()
        #else
        return .unknown
        #endif
    }

    /// The model for this launch: a `-FSDemoState` screen, or the real app.
    public static func make(platform: Platform, options: LaunchOptions, sync: SyncServices,
                            services: PlatformServices, clock: Clock = .system) -> AppModel {
        if let name = options.demoState {
            return demo(DemoScreen(name: name) ?? .homeProtected, platform: platform, options: options)
        }
        let catalog = CheckCatalog.shared
        let pacing = Pacing(catalog: catalog, platform: platform)
        return AppModel(
            platform: platform, options: options, clock: clock, catalog: catalog,
            selfReports: .standard(pacing: pacing, clock: clock),
            notifier: .standard(clock: clock),
            sync: sync,
            callBenStore: options.noCloud ? InMemoryCallBenStore() : KeychainCallBenStore(),
            uiState: UIStateStore(store: UserDefaultsStore()),
            services: services
        )
    }

    // MARK: Lifecycle

    /// Launch work: the first check, and (at the same time) owner mode. The check never waits
    /// for CloudKit, so Home leaves "Checking now" as soon as the measured checks are done.
    /// Safe to call more than once.
    public func start() async {
        guard !started else { return }
        started = true
        async let ownerMode = checkOwnerMode()
        await refresh()
        if let isOwner = await ownerMode {
            self.isOwner = isOwner
            // A reinstalled owner device: enroll into z_self, then send the report that
            // `refresh()` could not deliver yet.
            if isOwner, await enrollOwnerDevice() { await report() }
        }
        if isOwner { await refreshDashboard() }
    }

    private func checkOwnerMode() async -> Bool? {
        guard let owner = sync.owner else { return nil }
        return try? await owner.refreshOwnerMode()
    }

    /// Re-runs the measured checks (app foreground, after a fix, background refresh).
    public func refresh() async {
        guard !isRefreshing else { return }
        // Demo screens keep their fixed measured results (no checks, no network).
        if demo != nil {
            recompute()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        // Read first: it takes milliseconds, while measuring can wait on the feed (15 s timeout).
        if remindersWanted { remindersAllowed = await notifier.isAuthorized() }
        measured = await services.measure()
        feedInfo = await services.feedInfo()
        lastCheckedAt = clock.now()
        recompute()
        await report()
        services.didRefresh()
    }

    /// Re-evaluates with the latest answers (no new measurement).
    public func recompute() {
        let state = selfReports.refresh()
        snapshot = engine.evaluate(measured: measured, selfReports: state)
    }

    /// Sends this device's results (§8.4 report) and plans reminders (§5.4). Nothing is sent or
    /// planned before the first measurement: that snapshot has no measured checks, and planning
    /// from it would cancel (then re-send) every reminder for a check that is still failing.
    func report() async {
        guard !snapshot.measurementPending else {
            await refreshConnection()
            return
        }
        if let device = currentDeviceInfo() {
            do {
                try await sync.sink.upsert(device: device, results: snapshot.results(deviceID: device.deviceID))
            } catch {
                Log.ui.info("report.notDelivered")
            }
        }
        await refreshConnection()
        if remindersOptIn {
            await notifier.update(with: snapshot)
        }
    }

    private func refreshConnection() async {
        if demo != nil { return }
        if let cloud = sync.cloudSink {
            connection = await cloud.connectionState
        } else {
            connection = sync.settings.connection
        }
    }

    func currentDeviceInfo() -> DeviceInfo? {
        guard let id = try? sync.deviceIdentity.deviceID() else { return nil }
        let today = clock.today()
        let enrolled = uiState.enrolledOn ?? today
        if uiState.enrolledOn == nil { uiState.enrolledOn = today }
        return DeviceInfo(deviceID: id, platform: platform, enrolledOn: enrolled, catalogVersion: catalog.version,
                          appBuild: build.build, lastReport: today)
    }

    // MARK: Items

    /// The family-visible item for `id` (or a Ben-only one), from the current snapshot.
    public func item(_ id: CheckID) -> StatusItem? {
        snapshot.familyItems.first { $0.id == .check(id) } ?? snapshot.benOnly.first { $0.id == .check(id) }
            ?? snapshot.optionalLinks.first { $0.id == .check(id) }
    }

    public func serviceProgress(_ key: ServiceKey) -> ServiceProgress? {
        snapshot.accounts.lazy.flatMap(\.services).first { $0.service.key == key }
    }

    public func route(for item: StatusItem) -> Route {
        switch item.id {
        case .service(let key): .service(key)
        case .check(let id):
            switch item.kind {
            case .measured: .fix(id)
            case .optional: .optional(id)
            default: .guided(id)
            }
        }
    }

    /// The big status mark on Home and in the menu-bar panel: the Next step's color, green only
    /// when protected, grey while the first check is still running (H7).
    public var homeAppearance: StatusAppearance {
        let home = snapshot.home
        if let next = home.nextStep { return appearance(next) }
        return home.isChecking ? .cantCheck : .done
    }

    /// The appearance a card should use (Not sure shows amber, §6.3).
    public func appearance(_ item: StatusItem) -> StatusAppearance {
        StatusAppearance(status: item.appearanceStatus, tier: item.tier)
    }

    public func open(_ route: Route) {
        homePath.append(route)
    }

    public func popToHome() {
        homePath.removeAll()
    }

    public func pop() {
        if !homePath.isEmpty { homePath.removeLast() }
    }

    /// Show the "Which accounts do you use?" card on Home: group 3 is open and nothing is picked.
    public var showAccountsPrompt: Bool {
        snapshot.unlockedGroups.contains(3) && snapshot.selfReports.selectedServices.isEmpty && !accountsPromptDismissed
    }

    // MARK: Answers (local only)

    public func answer(_ answer: SelfAnswer, for key: SelfReportKey) {
        selfReports.record(answer, for: key)
        recompute()
        Task { await report() }
    }

    public func currentAnswer(_ key: SelfReportKey) -> SelfAnswer? {
        snapshot.selfReports.currentAnswer(for: key, on: snapshot.today)
    }

    public var selectedServices: Set<ServiceKey> { snapshot.selfReports.selectedServices }

    public func setSelectedServices(_ services: Set<ServiceKey>) {
        selfReports.setSelectedServices(services)
        recompute()
        Task { await report() }
    }

    public func skipAccountsPicker() {
        selfReports.markAccountsPickerDone()
        uiState.accountsPromptDismissed = true
        accountsPromptDismissed = true
        recompute()
    }

    public var carrier: Carrier? { snapshot.selfReports.carrier }

    public func setCarrier(_ carrier: Carrier?) {
        selfReports.setCarrier(carrier)
        recompute()
    }

    public var doItAllNow: Bool { snapshot.selfReports.doItAllNow }

    public func setDoItAllNow(_ on: Bool) {
        selfReports.setDoItAllNow(on)
        recompute()
        Task { await report() }
    }

    // MARK: Onboarding (§10.1 1–5)

    public func next(after step: OnboardingStep) {
        let following: OnboardingStep = switch step {
        case .welcome: .join
        case .join: hasLoginItem ? .keepChecking : .whoToCall
        case .keepChecking: .whoToCall
        case .whoToCall: .reminders
        case .reminders: .accounts
        case .accounts, .startFamily, .done: .done
        }
        if following == .done {
            finishOnboarding()
        } else {
            onboardingPath.append(following)
        }
    }

    public func beginStartFamily() {
        onboardingPath.append(.startFamily)
    }

    public func finishOnboarding() {
        onboarding = .done
        onboardingPath.removeAll()
        // Nothing pushed while setup was showing (for example from the Mac menu bar) survives it.
        homePath.removeAll()
        selectedTab = .home
    }

    /// The Mac menu-bar shortcuts ("Is this a scam?", the next step). Before setup is finished
    /// they only bring the window forward, which shows setup.
    public func openFromMenuBar(_ route: Route) {
        guard onboarding == .done else { return }
        selectedTab = .home
        if route == .scamEntry { clearScam() }
        homePath = [route]
    }

    // MARK: Mac login item (§10.2)

    /// True on the Mac, where Family Shield can keep checking as a login item.
    public var hasLoginItem: Bool { services.loginItem != nil }

    /// Re-reads the login-item state (About, after System Settings). Never registers. After a
    /// failed register, "off" stays "Ben will turn this on" so the same dead button isn't offered.
    public func refreshLoginItemState() {
        guard let state = services.loginItem?.status() else { return }
        loginItemState = loginItemRegisterFailed && state == .off ? .unavailable : state
    }

    /// **[Keep checking in the background]**: the only caller of `SMAppService.mainApp.register()`.
    /// If macOS wants the person to allow it, opens System Settings → Login Items. If macOS
    /// refused (`register` reports `.unavailable`), the screen says Ben will set it up instead of
    /// showing the same button again.
    @discardableResult
    public func keepCheckingInBackground() -> LoginItemState? {
        guard let control = services.loginItem else { return nil }
        let state = control.register()
        if state == .unavailable { loginItemRegisterFailed = true }
        loginItemState = state
        if state == .needsApproval { control.openSettings() }
        return state
    }

    /// "Open System Settings" on the "Turn on Family Shield" card.
    public func openLoginItemsSettings() {
        services.loginItem?.openSettings()
    }

    // MARK: Ben's own Mac (§6.2, §10.3)

    /// Show "This Mac" (Ben only) on the Family tab: Ben's copy on a Mac.
    public var showsOwnerMacSection: Bool { isOwner && platform == .mac }

    /// The "MDM is expected" switch exists (Ben's own Mac only).
    public var canMarkMDMExpected: Bool { showsOwnerMacSection && services.mdmExpected != nil }

    /// Ben marks his own Mac's device management as expected; the checks run again.
    public func setMDMExpected(_ expected: Bool) {
        guard canMarkMDMExpected else { return }
        services.mdmExpected?.set(expected)
        mdmExpected = expected
        Task { await refresh() }
    }

    // MARK: Call Ben

    /// `tel:` for the saved number, or nil when no one was picked yet.
    public var callBenURL: URL? { benNumber.flatMap(OfficialLinks.telURL) }

    public var canPickContact: Bool { services.canPickContact }

    public enum ChooseBenResult: Sendable, Equatable {
        case saved
        /// The picker was closed without choosing anyone.
        case cancelled
        /// A number was picked but couldn't be used (too short or long) or saved (Keychain).
        case notSaved
    }

    /// "Choose Ben from my contacts": the system picker; the number goes to the Keychain only.
    @discardableResult
    public func chooseBen() async -> ChooseBenResult {
        guard let picked = await services.pickContactNumber() else { return .cancelled }
        guard callBenStore.save(picked), let saved = callBenStore.load() else {
            Log.ui.notice("callben.notSaved")
            return .notSaved
        }
        benNumber = saved
        return .saved
    }

    // MARK: Reminders (§10.1 4)

    /// [Yes]: the system prompt (the only place it is ever asked; iOS shows it once, later taps
    /// just return the current answer). [No thanks] / [Turn off reminders]: nothing is asked.
    /// Returns true when reminders are on.
    @discardableResult
    public func answerReminders(_ yes: Bool) async -> Bool {
        uiState.remindersOptIn = yes
        remindersWanted = yes
        guard yes else {
            // Off means off: the "+3 days" reminder already queued must not fire later.
            await notifier.reset()
            return false
        }
        let granted = await notifier.requestPermission()
        remindersAllowed = granted ? true : await notifier.isAuthorized()
        if remindersOptIn { await notifier.update(with: snapshot) }
        return remindersOptIn
    }

    // MARK: Sharing (§8.4)

    /// The share link was tapped (scene / app delegate). Enrolls this device in the person zone.
    /// A failure is said on Join and About (`notice`), never silently dropped.
    public func acceptShare(_ metadata: CKShare.Metadata) async {
        guard let cloud = sync.cloudSink else {
            Log.ui.notice("share.accept.noCloud")
            return
        }
        guard let device = currentDeviceInfo() else {
            Log.ui.error("share.accept.noDeviceID")
            notice = Self.shareFailureNotice(nil, platform: platform)
            return
        }
        do {
            try await cloud.acceptShare(metadata, device: device)
            notice = nil
        } catch {
            let sinkError = error as? ResultSinkError
            Log.ui.error("share.accept.failed reason=\(String(describing: sinkError), privacy: .public)")
            notice = Self.shareFailureNotice(sinkError, platform: platform)
        }
        await refreshConnection()
        await report()
    }

    /// What the person sees when tapping (iPhone) or clicking (Mac) Ben's link did not connect.
    /// Every case says the link was tried and what to do next.
    static func shareFailureNotice(_ error: ResultSinkError?, platform: Platform) -> String {
        switch error {
        case .alreadyConnected?: L.t(L.platformKey("share.failed.alreadyConnected", platform))
        case .invalidShare?: L.t("share.failed.invalid")
        case .notConnected?: L.t("share.failed.notConnected")
        case .rejected?: L.t("share.failed.rejected")
        case .unavailable?, .deviceMismatch?, .invalidRecordName?, nil: L.t(L.platformKey("share.failed.offline", platform))
        }
    }

    /// About shows [Stop sharing with Ben]: a family device that reports to Ben. Ben's own
    /// devices report to his own Family tab; there is no one to stop sharing with.
    public var canStopSharing: Bool {
        !isOwnerDevice && (connection == .connected || connection == .notDelivering)
    }

    /// One of Ben's own devices (owner mode, or reporting into `z_self`).
    private var isOwnerDevice: Bool {
        isOwner || sync.settings.isOwner || sync.settings.target?.kind == .ownerSelf
    }

    /// "Stop sharing with Ben" (§8.4 leave). Keeps working locally either way. Never on Ben's own
    /// devices: leaving would delete their own `z_self` records.
    public func stopSharing() async {
        guard !isOwnerDevice else { return }
        do {
            try await sync.sink.leave()
            notice = L.t("about.stopSharing.done")
            if demo != nil || sync.cloudSink == nil { connection = .notJoined }
        } catch {
            notice = L.t("about.stopSharing.failed")
        }
        await refreshConnection()
    }

    // MARK: Ben (§10.3)

    public var hasCloud: Bool { sync.owner != nil }

    /// "Start a family": `z_admin` + `z_self`, then this device reports into `z_self`.
    @discardableResult
    public func startFamily() async -> Bool {
        guard let owner = sync.owner else {
            // No iCloud in this copy: show the Family tab with sample data so Ben can look around.
            isOwner = true
            dashboard = DemoFamily.dashboard(today: clock.today(), catalog: catalog)
            dashboardIsSample = true
            dashboardMessage = L.t("startFamily.offline")
            finishOnboarding()
            selectedTab = .family
            return true
        }
        do {
            try await owner.startFamily()
        } catch {
            dashboardMessage = L.t("startFamily.failed")
            return false
        }
        isOwner = true
        await enrollOwnerDevice()
        finishOnboarding()
        selectedTab = .family
        await refreshDashboard()
        return true
    }

    /// Enrolls Ben's device into `z_self` when it has never reported. True when it enrolled.
    @discardableResult
    private func enrollOwnerDevice() async -> Bool {
        guard let cloud = sync.cloudSink, sync.settings.lastSent == nil, let device = currentDeviceInfo() else { return false }
        do {
            try await cloud.enrollAsOwnerDevice(device: device)
            return true
        } catch {
            return false
        }
    }

    public enum InviteResult: Sendable, Equatable {
        case shown
        case offline
        case failed
    }

    /// "Add person" → "Send invite": a person zone + share, shown in the system sharing UI.
    public func invite(label: String) async -> InviteResult {
        guard let owner = sync.owner else { return .offline }
        do {
            let invite = try await owner.createPerson(label: label)
            let shown = await services.presentInvite(invite)
            await refreshDashboard()
            return shown ? .shown : .failed
        } catch {
            return .failed
        }
    }

    /// Family tab: cached first, then CloudKit (pull-to-refresh, ⌘R and the Mac's Refresh button,
    /// and whenever the tab is opened). A second call while one is in flight does nothing.
    public func refreshDashboard() async {
        guard let owner = sync.owner, !isRefreshingDashboard else { return }
        isRefreshingDashboard = true
        defer { isRefreshingDashboard = false }
        if dashboard == nil { dashboard = await owner.cachedDashboard() }
        do {
            let fresh = try await owner.refreshDashboard()
            dashboard = fresh
            // Some zones couldn't be fetched (each keeps its last copy): say so.
            dashboardMessage = fresh.incomplete ? L.t("family.refreshFailed") : nil
        } catch {
            dashboardMessage = L.t("family.refreshFailed")
        }
    }

    /// The Family tab was opened or selected (iPhone tab bar, the Mac's tab buttons, ⌘2).
    /// Demo screens keep their fixed sample dashboard.
    func familyTabOpened() {
        guard isOwner, demo == nil, sync.owner != nil, !dashboardIsSample else { return }
        familyTabRefresh = Task { [weak self] in await self?.refreshDashboard() }
    }

    /// ⌘R (Mac): on Ben's Family tab it refreshes the dashboard; everywhere else it checks again.
    public var refreshesDashboard: Bool { isOwner && selectedTab == .family && onboarding == .done }

    /// The ⌘R action. See `refreshesDashboard`.
    public func refreshCurrentTab() async {
        if refreshesDashboard {
            await refreshDashboard()
        } else {
            await refresh()
        }
    }

    /// ⌘R is busy.
    public var isRefreshingCurrentTab: Bool { refreshesDashboard ? isRefreshingDashboard : isRefreshing }

    public func person(_ zoneName: String) -> DashboardPerson? {
        dashboard?.people.first { $0.zoneName == zoneName }
    }

    public func device(zoneName: String, deviceID: UUID) -> DashboardDevice? {
        person(zoneName)?.devices.first { $0.deviceID == deviceID }
    }

    // MARK: Notifications

    /// The person tapped or clicked a reminder: Home, with the failing item open when it still
    /// needs doing (otherwise just Home, which shows what is current). Before setup is finished
    /// it does nothing more than bring the app forward.
    public func openFromNotification(checkID: CheckID?) {
        guard onboarding == .done else { return }
        selectedTab = .home
        if let checkID, let item = item(checkID), item.needsAction {
            homePath = [route(for: item)]
        } else {
            homePath = []
        }
    }

    // MARK: Scam checker (§5.3, memory only)

    /// Checks the pasted message. The rules run off the main actor, so a long paste (up to the
    /// 8,000-character cap) never freezes the screen. Like a screenshot check, a result that
    /// arrives after the person left the scam screens is dropped.
    public func checkMessage() async {
        guard !isCheckingMessage else { return }
        let text = scamDraft
        let session = scamSession
        isCheckingMessage = true
        let assessment = await Task.detached(priority: .userInitiated) { ScamChecker.assess(text: text) }.value
        guard session == scamSession else { return }
        isCheckingMessage = false
        guard homePath.contains(where: Self.scamRoutes.contains) else { return }
        scamOutcome = ScamOutcome(assessment: assessment, origin: .message, originalText: text)
        homePath.append(.scamResult)
    }

    public func checkScreenshot(_ data: Data) async {
        let session = scamSession
        isCheckingScam = true
        let assessment = await ScamChecker.assess(imageData: data)
        // The person left the scam screens while the text was being read: forget it (§5.3).
        guard session == scamSession else { return }
        isCheckingScam = false
        guard homePath.contains(where: Self.scamRoutes.contains) else { return }
        scamOutcome = ScamOutcome(assessment: assessment, origin: .screenshot, originalText: nil, screenshot: data)
        homePath.append(.scamResult)
    }

    public func finishCallQuiz(_ answers: CallQuiz.Answers) {
        scamOutcome = ScamOutcome(call: CallQuiz.evaluate(answers))
        homePath.append(.scamResult)
    }

    /// "Check something else": back to the scam entry, forgetting the last check.
    public func checkAnother() {
        clearScam()
        if let index = homePath.firstIndex(of: .scamEntry) {
            homePath = Array(homePath.prefix(through: index))
        } else {
            homePath = [.scamEntry]
        }
    }

    /// Forgets the scam session, including a screenshot check still running.
    public func clearScam() {
        scamDraft = ""
        scamOutcome = nil
        scamSession &+= 1
        isCheckingScam = false
        isCheckingMessage = false
    }

    static let scamRoutes: Set<Route> = [.scamEntry, .pasteMessage, .callQuiz, .scamResult]

    private func endScamSessionIfLeft() {
        if !homePath.contains(where: Self.scamRoutes.contains), !scamDraft.isEmpty || scamOutcome != nil || isCheckingScam {
            clearScam()
        }
    }

    // MARK: Demo support

    func applyDemo(onboarding: OnboardingStep, onboardingPath: [OnboardingStep], homePath: [Route],
                   familyPath: [FamilyRoute], tab: MainTab, owner: Bool, connection: SyncConnectionState,
                   measured: [MeasuredResult], feed: FeedInfo?, lastChecked: Date) {
        self.onboarding = onboarding
        self.onboardingPath = onboardingPath
        self.homePath = homePath
        self.familyPath = familyPath
        self.selectedTab = tab
        self.isOwner = owner
        self.connection = connection
        self.measured = measured
        self.feedInfo = feed
        self.lastCheckedAt = lastChecked
        self.started = true
        if owner {
            dashboard = DemoFamily.dashboard(today: clock.today(), catalog: catalog)
            dashboardIsSample = false
        }
        recompute()
    }

    func applyDemoScam(draft: String, outcome: ScamOutcome?) {
        scamDraft = draft
        scamOutcome = outcome
    }
}
