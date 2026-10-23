// Online-account service catalog (SPEC §6.4, REQUIREMENTS-ADDENDUM). Compiled in; nothing is
// downloaded (H6). This file is one of the three places URL constants may live (§12.4).
//
// Privacy (H5, §12.2): service keys, picked services and step answers stay on the device.
// Only the six `accounts_*` category rollups sync, as pass/fail/unknown.
//
// URLs and paths were checked against official help pages on 2026-10-22
// (docs/verified/accounts-*.md). Where that check corrected §6.4 (Yahoo, AOL, Facebook, PayPal,
// Cash App, Venmo, TikTok, Snapchat paths), the verified value is used. The 2026-10-23 audit
// (docs/verified/AUDITED.md) re-checked every URL here and found none to change; the copy fixes
// it called for (PayPal, WhatsApp passkeys, Instagram third-party apps) live in the strings.
// On 2026-10-23 every step got start-to-finish copy and a one-sentence "why"; paths not found
// on an official page stay hedged ("look for …", "Menu names may differ a little").
// `tools/link-check.sh` should re-check every URL before release; some sites refuse scripts and
// are on its hand-verified list.

import Foundation

/// A §6.4 category. Each one except `credit` has a synced rollup.
public enum AccountCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case email
    case money
    case social
    case shopping
    case government
    case health
    /// Credit bureaus: handled by the three `credit_freeze_*` checks, no rollup of its own.
    case credit

    /// The synced rollup for this category (nil for `credit`).
    public var rollup: CheckID? {
        switch self {
        case .email: .accountsEmail
        case .money: .accountsMoney
        case .social: .accountsSocial
        case .shopping: .accountsShopping
        case .government: .accountsGovernment
        case .health: .accountsHealth
        case .credit: nil
        }
    }

    public var nameKey: String { "accounts.category.\(rawValue)" }

    /// The category whose rollup is `id`, if any.
    public init?(rollup id: CheckID) {
        guard let match = AccountCategory.allCases.first(where: { $0.rollup == id }) else { return nil }
        self = match
    }
}

/// The standard per-service steps (§6.4), plus `trustedContact` for brokerage accounts.
public enum AccountStep: String, CaseIterable, Codable, Sendable, Hashable {
    case twoFactor = "2fa"
    case uniquePassword = "unique_pw"
    case recoveryInfo = "recovery_info"
    case sessions
    case thirdParty = "third_party"
    case alerts
    case checkup
    /// §6.4 brokerage: "Add a **trusted contact** to the account."
    case trustedContact = "trusted_contact"

    /// The generic copy (§6.4 "Plain copy").
    public var genericCopyKey: String { "accounts.step.\(rawValue)" }

    /// The generic one-sentence reason shown under the step (§6.4 "Why" line).
    public var genericWhyKey: String { "accounts.why.\(rawValue)" }
}

/// Every §6.4 service. The raw value is the local storage key (never synced).
public enum ServiceKey: String, CaseIterable, Codable, Sendable, Hashable {
    // email
    case gmail
    case icloudMail = "icloud_mail"
    case outlook
    case yahoo
    case aol
    // money
    case bank
    case creditCard = "credit_card"
    case paypal
    case venmo
    case zelle
    case cashApp = "cash_app"
    case brokerage
    // social
    case facebook
    case instagram
    case whatsapp
    case x
    case tiktok
    case linkedin
    case snapchat
    // shopping
    case amazon
    case carrierAccount = "carrier_account"
    // government
    case ssa
    case irsIPPin = "irs_ip_pin"
    // health
    case healthPortal = "health_portal"
    // credit
    case creditBureaus = "credit_bureaus"
}

/// One online-account service and its mini-checklist.
public struct OnlineService: Sendable, Hashable, Identifiable {
    public let key: ServiceKey
    public let category: AccountCategory
    /// SF Symbol only: no third-party brand art (App Review 5.2).
    public let symbolName: String
    /// The official page, opened in Safari. nil when the page lives only in the company's app.
    public let officialURLString: String?
    /// Applicable steps, in display order. Steps that don't apply are skipped (§6.4).
    public let steps: [AccountStep]
    /// Steps whose copy is filled in for this service (`service.<key>.step.<step>`).
    public let stepOverrides: Set<AccountStep>
    /// Steps whose reason differs for this service (`service.<key>.why.<step>`); the rest use
    /// the generic `accounts.why.<step>`.
    public let whyOverrides: Set<AccountStep>
    /// True when the service has a "where to find it" line (`service.<key>.where`).
    public let hasWhereCopy: Bool
    /// §6.3 checks this service also relies on (`carrier_account` → `carrier_lock`,
    /// `credit_bureaus` → the three freezes).
    public let linkedChecks: [CheckID]

    public var id: ServiceKey { key }

    public var nameKey: String { "service.\(key.rawValue).name" }

    public var whereKey: String? { hasWhereCopy ? "service.\(key.rawValue).where" : nil }

    public var officialURL: URL? { officialURLString.flatMap(OfficialLinks.httpsURL) }

    /// The copy key for one step: the service-specific text when there is one, else the generic.
    public func copyKey(for step: AccountStep) -> String {
        stepOverrides.contains(step) ? "service.\(key.rawValue).step.\(step.rawValue)" : step.genericCopyKey
    }

    /// The "why" key for one step: the service-specific reason when there is one, else the generic.
    public func whyKey(for step: AccountStep) -> String {
        whyOverrides.contains(step) ? "service.\(key.rawValue).why.\(step.rawValue)" : step.genericWhyKey
    }

    /// Every string key this service references (for lint tests).
    public var allStringKeys: [String] {
        [nameKey, category.nameKey] + (whereKey.map { [$0] } ?? []) + steps.map(copyKey(for:)) + steps.map(whyKey(for:))
    }
}

/// The compiled §6.4 service catalog.
public enum Services {
    /// Every service, in display order (category order, then §6.4 table order).
    public static let all: [OnlineService] = [
        // MARK: email
        OnlineService(
            key: .gmail, category: .email, symbolName: "envelope.fill",
            officialURLString: "https://myaccount.google.com/security-checkup",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            whyOverrides: [.recoveryInfo, .alerts],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .icloudMail, category: .email, symbolName: "icloud.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty],
            stepOverrides: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty],
            whyOverrides: [.twoFactor, .recoveryInfo, .sessions],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .outlook, category: .email, symbolName: "envelope.fill",
            officialURLString: "https://account.microsoft.com/security",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .checkup],
            whyOverrides: [.recoveryInfo],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .yahoo, category: .email, symbolName: "envelope.fill",
            officialURLString: "https://login.yahoo.com/myaccount/security",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .checkup],
            whyOverrides: [.recoveryInfo, .thirdParty],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .aol, category: .email, symbolName: "envelope.fill",
            officialURLString: "https://login.aol.com/myaccount/security",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .checkup],
            whyOverrides: [.recoveryInfo, .thirdParty],
            hasWhereCopy: false, linkedChecks: []),

        // MARK: money
        OnlineService(
            key: .bank, category: .money, symbolName: "building.columns.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .alerts],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .alerts],
            whyOverrides: [.alerts],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .creditCard, category: .money, symbolName: "creditcard.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .alerts],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .alerts],
            whyOverrides: [.alerts],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .paypal, category: .money, symbolName: "dollarsign.circle.fill",
            officialURLString: "https://www.paypal.com/myaccount/security/",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .thirdParty, .alerts, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .thirdParty, .alerts, .checkup],
            whyOverrides: [.thirdParty, .alerts],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .venmo, category: .money, symbolName: "dollarsign.circle.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .alerts],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .alerts],
            whyOverrides: [.twoFactor, .alerts],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .zelle, category: .money, symbolName: "dollarsign.circle.fill",
            officialURLString: nil,
            steps: [.alerts],
            stepOverrides: [.alerts],
            whyOverrides: [.alerts],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .cashApp, category: .money, symbolName: "dollarsign.circle.fill",
            officialURLString: nil,
            steps: [.twoFactor, .recoveryInfo, .alerts],
            stepOverrides: [.twoFactor, .recoveryInfo, .alerts],
            whyOverrides: [.twoFactor, .alerts],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .brokerage, category: .money, symbolName: "chart.line.uptrend.xyaxis",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .alerts, .trustedContact],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .alerts, .trustedContact],
            whyOverrides: [.alerts],
            hasWhereCopy: true, linkedChecks: []),

        // MARK: social
        OnlineService(
            key: .facebook, category: .social, symbolName: "person.2.fill",
            officialURLString: "https://accountscenter.facebook.com/password_and_security",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            whyOverrides: [],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .instagram, category: .social, symbolName: "camera.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            whyOverrides: [],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .whatsapp, category: .social, symbolName: "message.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions],
            stepOverrides: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions],
            whyOverrides: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .x, category: .social, symbolName: "text.bubble.fill",
            officialURLString: "https://x.com/settings/security_and_account_access",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .checkup],
            whyOverrides: [],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .tiktok, category: .social, symbolName: "play.rectangle.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .alerts, .checkup],
            whyOverrides: [.alerts],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .linkedin, category: .social, symbolName: "briefcase.fill",
            officialURLString: "https://www.linkedin.com/mypreferences/d/categories/sign-in-and-security",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty, .checkup],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty, .checkup],
            whyOverrides: [],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .snapchat, category: .social, symbolName: "message.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo, .sessions, .thirdParty],
            stepOverrides: [.twoFactor, .recoveryInfo, .sessions, .thirdParty],
            whyOverrides: [],
            hasWhereCopy: true, linkedChecks: []),

        // MARK: shopping
        OnlineService(
            key: .amazon, category: .shopping, symbolName: "cart.fill",
            officialURLString: "https://www.amazon.com/a/settings/approval",
            steps: [.twoFactor, .uniquePassword, .recoveryInfo],
            stepOverrides: [.twoFactor, .recoveryInfo],
            whyOverrides: [.twoFactor],
            hasWhereCopy: false, linkedChecks: []),
        OnlineService(
            key: .carrierAccount, category: .shopping, symbolName: "antenna.radiowaves.left.and.right",
            officialURLString: nil,
            steps: [.uniquePassword, .recoveryInfo],
            stepOverrides: [.uniquePassword, .recoveryInfo],
            whyOverrides: [.uniquePassword, .recoveryInfo],
            hasWhereCopy: true, linkedChecks: [.carrierLock]),

        // MARK: government
        OnlineService(
            key: .ssa, category: .government, symbolName: "building.2.fill",
            officialURLString: "https://www.ssa.gov/myaccount/",
            steps: [.checkup, .twoFactor, .uniquePassword, .recoveryInfo],
            stepOverrides: [.checkup, .twoFactor, .recoveryInfo],
            whyOverrides: [.checkup, .twoFactor],
            hasWhereCopy: true, linkedChecks: []),
        OnlineService(
            key: .irsIPPin, category: .government, symbolName: "doc.text.fill",
            officialURLString: "https://www.irs.gov/identity-theft-fraud-scams/get-an-identity-protection-pin",
            steps: [.checkup],
            stepOverrides: [.checkup],
            whyOverrides: [.checkup],
            hasWhereCopy: true, linkedChecks: []),

        // MARK: health
        OnlineService(
            key: .healthPortal, category: .health, symbolName: "cross.case.fill",
            officialURLString: nil,
            steps: [.twoFactor, .uniquePassword, .recoveryInfo],
            stepOverrides: [.twoFactor, .recoveryInfo],
            whyOverrides: [.twoFactor],
            hasWhereCopy: true, linkedChecks: []),

        // MARK: credit
        OnlineService(
            key: .creditBureaus, category: .credit, symbolName: "lock.shield.fill",
            officialURLString: nil,
            steps: [.uniquePassword],
            stepOverrides: [.uniquePassword],
            whyOverrides: [.uniquePassword],
            hasWhereCopy: true,
            linkedChecks: [.creditFreezeEquifax, .creditFreezeExperian, .creditFreezeTransunion]),
    ]

    private static let byKey: [ServiceKey: OnlineService] = {
        var map: [ServiceKey: OnlineService] = [:]
        for service in all where map[service.key] == nil { map[service.key] = service }
        return map
    }()

    public static func service(_ key: ServiceKey) -> OnlineService? { byKey[key] }

    /// Services in a category, in display order.
    public static func services(in category: AccountCategory) -> [OnlineService] {
        all.filter { $0.category == category }
    }

    /// Display order index (category order, then table order).
    public static func displayIndex(_ key: ServiceKey) -> Int {
        all.firstIndex(where: { $0.key == key }) ?? Int.max
    }
}
