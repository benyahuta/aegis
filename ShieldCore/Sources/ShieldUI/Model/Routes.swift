// Navigation for the shared screens (SPEC §10.1, §10.3).

import Foundation
import ShieldCore

/// The first-run screens, in order (§10.1 1–5). `startFamily` is Ben's branch from Welcome.
/// `keepChecking` is the Mac's login-item screen (§10.2), shown only on the Mac.
public enum OnboardingStep: String, CaseIterable, Codable, Sendable, Hashable {
    case welcome
    case join
    case keepChecking
    case whoToCall
    case reminders
    case accounts
    case startFamily
    case done
}

/// Screens pushed on the Home stack.
public enum Route: Hashable, Sendable {
    /// §10.1 7: a measured fix, one step per screen.
    case fix(CheckID)
    /// §10.1 8: a guided self-check.
    case guided(CheckID)
    /// §6.2 / §6.3 optional extras (Advanced Data Protection, Lockdown Mode): why, where, and the
    /// "talk to Ben first" warning before the Settings button. Never answered, never synced.
    case optional(CheckID)
    /// §6.4: one online-account service's steps.
    case service(ServiceKey)
    /// §10.1 9.
    case scamEntry
    case pasteMessage
    case callQuiz
    /// §10.1 10.
    case scamResult
    /// §10.1 11.
    case familyRules
    /// §10.1 12.
    case about
    /// §10.1 5 again ("Change my accounts list").
    case accountsPicker
    /// §10.1 3 again ("Change who to call").
    case whoToCall
    /// §10.1 4 again (About → Reminders): turn reminders on or off later.
    case reminders
}

/// Screens pushed on Ben's Family tab.
public enum FamilyRoute: Hashable, Sendable {
    case device(zoneName: String, deviceID: UUID)
    case addPerson
    case feedHealth
}

public enum MainTab: String, Hashable, Sendable {
    case home
    case family
}
