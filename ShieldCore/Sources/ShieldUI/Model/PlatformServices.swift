// What the shared AppModel needs from each app (iPhone / Mac). The apps build one of these with
// their own checks and UIKit/AppKit bridges; tests and `-FSDemoState` use fixed versions.

import Foundation
import ShieldCore

/// Feed facts for About ("Last checked …", §6.5) and Ben's Feed & release health (§10.3).
public struct FeedInfo: Sendable, Hashable {
    public var fetchedAt: Date?
    public var origin: FeedState.Origin?
    /// SOFA's own `LastCheck` / update time.
    public var lastSOFAChange: Date?
    public var freshness: FeedFreshness

    public init(fetchedAt: Date?, origin: FeedState.Origin?, lastSOFAChange: Date?, freshness: FeedFreshness) {
        self.fetchedAt = fetchedAt
        self.origin = origin
        self.lastSOFAChange = lastSOFAChange
        self.freshness = freshness
    }

    public init(state: FeedState?, now: Date) {
        self.init(fetchedAt: state?.fetchedAt, origin: state?.origin, lastSOFAChange: state?.feed.lastCheck,
                  freshness: FeedFreshness.of(state, now: now))
    }
}

public struct PlatformServices: Sendable {
    /// Runs this device's measured checks (§6.1 / §6.2). Never throws; unknown on any error (H7).
    public var measure: @Sendable () async -> [MeasuredResult]
    /// The version feed's state, if this platform has one.
    public var feedInfo: @Sendable () async -> FeedInfo?
    /// True when "Choose Ben from my contacts" can show the system contact picker.
    public var canPickContact: Bool
    /// Shows the system contact picker (no Contacts permission) and returns the picked number.
    public var pickContactNumber: @MainActor @Sendable () async -> String?
    /// Presents the system sharing UI for a new person's invite (§8.4 "Ben: create a person").
    /// Returns false when it could not be shown.
    public var presentInvite: @MainActor @Sendable (PersonInvite) async -> Bool
    /// Called after each refresh (the iPhone schedules its next BGAppRefreshTask here).
    public var didRefresh: @MainActor @Sendable () -> Void
    /// The Mac login item (§10.2). nil on iPhone.
    public var loginItem: LoginItemControl?
    /// Ben's own Mac only: "this Mac's device management is expected" (§6.2). nil elsewhere.
    public var mdmExpected: OwnerMacSetting?

    public init(
        measure: @escaping @Sendable () async -> [MeasuredResult],
        feedInfo: @escaping @Sendable () async -> FeedInfo? = { nil },
        canPickContact: Bool = false,
        pickContactNumber: @escaping @MainActor @Sendable () async -> String? = { nil },
        presentInvite: @escaping @MainActor @Sendable (PersonInvite) async -> Bool = { _ in false },
        didRefresh: @escaping @MainActor @Sendable () -> Void = {},
        loginItem: LoginItemControl? = nil,
        mdmExpected: OwnerMacSetting? = nil
    ) {
        self.measure = measure
        self.feedInfo = feedInfo
        self.canPickContact = canPickContact
        self.pickContactNumber = pickContactNumber
        self.presentInvite = presentInvite
        self.didRefresh = didRefresh
        self.loginItem = loginItem
        self.mdmExpected = mdmExpected
    }

    /// Nothing measured (every measured check stays off Home; nothing is ever a fake pass).
    public static let none = PlatformServices(measure: { [] })
}

/// Whether the Mac app runs in the background as a login item (`SMAppService.mainApp`, §10.2).
public enum LoginItemState: String, Sendable, Hashable, CaseIterable {
    /// Registered and allowed: checks run every day.
    case on
    /// Registered, but the person must allow it in System Settings → Login Items.
    case needsApproval
    /// Not registered yet (first launch), or turned off.
    case off
    /// This copy can't be a login item (for example, not in Applications), or macOS refused to
    /// register it. Ben sets it up.
    case unavailable

    /// The state to show after `SMAppService.register()`: a throw that left the item off means
    /// macOS refused, so the button would only fail again. Anything else is what macOS reports.
    public static func afterRegister(status: LoginItemState, threw: Bool) -> LoginItemState {
        threw && status == .off ? .unavailable : status
    }
}

/// The Mac's login-item bridge. `register` is called ONLY from the
/// **[Keep checking in the background]** button (§10.2); nothing registers automatically.
public struct LoginItemControl: Sendable {
    /// Reads the state. Never registers and never shows UI.
    public var status: @MainActor @Sendable () -> LoginItemState
    /// `SMAppService.mainApp.register()`, then the new state.
    public var register: @MainActor @Sendable () -> LoginItemState
    /// Opens System Settings → General → Login Items (`DeepLink.macLoginItems`).
    public var openSettings: @MainActor @Sendable () -> Void

    public init(status: @escaping @MainActor @Sendable () -> LoginItemState,
                register: @escaping @MainActor @Sendable () -> LoginItemState,
                openSettings: @escaping @MainActor @Sendable () -> Void) {
        self.status = status
        self.register = register
        self.openSettings = openSettings
    }

    /// A fixed state that never touches the system (demo screens, tests).
    public static func fixed(_ state: LoginItemState) -> LoginItemControl {
        LoginItemControl(status: { state }, register: { state }, openSettings: {})
    }
}

/// A local, never-synced switch on Ben's own Mac.
public struct OwnerMacSetting: Sendable {
    public var get: @Sendable () -> Bool
    public var set: @Sendable (Bool) -> Void

    public init(get: @escaping @Sendable () -> Bool, set: @escaping @Sendable (Bool) -> Void) {
        self.get = get
        self.set = set
    }
}

/// Small local UI flags (onboarding progress, reminders choice). Non-secret, never synced.
public struct UIStateStore: Sendable {
    public enum Key {
        public static let onboarding = "fs.ui.onboarding"
        public static let remindersOptIn = "fs.ui.remindersOptIn"
        public static let enrolledOn = "fs.ui.enrolledOn"
        public static let accountsPromptDismissed = "fs.ui.accountsPromptDismissed"
    }

    public let store: any KeyValueStore

    public init(store: any KeyValueStore) {
        self.store = store
    }

    public static func inMemory() -> UIStateStore { UIStateStore(store: InMemoryKeyValueStore()) }

    public var onboarding: OnboardingStep {
        get { value(OnboardingStep.self, Key.onboarding) ?? .welcome }
        nonmutating set { set(newValue, Key.onboarding) }
    }

    public var remindersOptIn: Bool {
        get { value(Bool.self, Key.remindersOptIn) ?? false }
        nonmutating set { set(newValue, Key.remindersOptIn) }
    }

    public var enrolledOn: DateDay? {
        get { value(DateDay.self, Key.enrolledOn) }
        nonmutating set { set(newValue, Key.enrolledOn) }
    }

    public var accountsPromptDismissed: Bool {
        get { value(Bool.self, Key.accountsPromptDismissed) ?? false }
        nonmutating set { set(newValue, Key.accountsPromptDismissed) }
    }

    private func value<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func set<T: Encodable>(_ value: T?, _ key: String) {
        store.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}
