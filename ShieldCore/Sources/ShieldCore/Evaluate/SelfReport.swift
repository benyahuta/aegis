// Self-report types (SPEC §5.4, §6.3, §6.4). Local only: these never leave the device.
// Only the derived pass/fail/unknown per CheckID syncs (H5).

import Foundation

/// The person's answer to a guided self-check or an account step.
public enum SelfAnswer: String, CaseIterable, Codable, Sendable, Hashable {
    /// [I did it] (or [We have one] for the code word). Wire `pass`.
    case didIt
    /// [Not sure]. Kept locally as its own answer, written as `unknown` (§5.1), shown amber.
    case notSure
    /// [Not now] (or [Not yet]). §6.3 checks: wire `fail`. §6.4 steps: `fail` only after 14 days.
    case notNow
}

/// One stored answer.
public struct SelfReport: Codable, Sendable, Hashable {
    public var answer: SelfAnswer
    /// The UTC day it was answered.
    public var answeredOn: DateDay

    public init(answer: SelfAnswer, answeredOn: DateDay) {
        self.answer = answer
        self.answeredOn = answeredOn
    }

    /// Every self-report expires after this many days and becomes `unknown` with a re-ask (§5.4).
    public static let expiryDays = 90

    /// True when the answer is `expiryDays` or more days old on `today`.
    public func isExpired(on today: DateDay) -> Bool {
        today.days(since: answeredOn) >= SelfReport.expiryDays
    }
}

/// What a self-report is about.
public enum SelfReportKey: Hashable, Sendable, CustomStringConvertible {
    /// A §6.3 guided self-check.
    case check(CheckID)
    /// One §6.4 step for one service.
    case accountStep(ServiceKey, AccountStep)

    /// The storage key: `check.<checkID>` or `account.<service>.<step>`.
    public var rawValue: String {
        switch self {
        case .check(let id): "check.\(id.rawValue)"
        case .accountStep(let service, let step): "account.\(service.rawValue).\(step.rawValue)"
        }
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "check":
            guard parts.count == 2, let id = CheckID(rawValue: parts[1]) else { return nil }
            self = .check(id)
        case "account":
            guard parts.count == 3, let service = ServiceKey(rawValue: parts[1]),
                  let step = AccountStep(rawValue: parts[2]) else { return nil }
            self = .accountStep(service, step)
        default:
            return nil
        }
    }

    public var description: String { rawValue }
}

/// Everything the person has told Family Shield on this device, plus pacing milestones.
/// Persisted locally by `SelfReportStore` (UserDefaults or a file). Never synced.
public struct SelfReportState: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public var version: Int = SelfReportState.currentVersion
    /// Answers keyed by `SelfReportKey.rawValue`.
    public var answers: [String: SelfReport] = [:]
    /// Services picked in "Which of these do you use?" (§6.4). Local only.
    public var selectedServices: Set<ServiceKey> = []
    /// True once the accounts picker was shown and closed (Done or skipped).
    public var accountsPickerDone: Bool = false
    /// The phone company picked on the `carrier_lock` card. Local only (§12.2).
    public var carrier: Carrier?
    /// "Do it all now with Ben" (About; local): unlocks every pace group and every service.
    public var doItAllNow: Bool = false
    /// The first day the engine ran (Group 1 is shown at first run).
    public var firstRunOn: DateDay?
    /// The day each pace group was first fully answered (fixed once set, so a later re-ask
    /// never re-locks a group).
    public var groupCompletedOn: [Int: DateDay] = [:]
    /// The day each service was introduced in pace group 3 (at most one per day).
    public var serviceIntroducedOn: [ServiceKey: DateDay] = [:]

    public init() {}

    public func report(for key: SelfReportKey) -> SelfReport? {
        answers[key.rawValue]
    }

    /// The answer if it is still current on `today` (nil when missing or expired).
    public func currentAnswer(for key: SelfReportKey, on today: DateDay) -> SelfAnswer? {
        guard let report = report(for: key), !report.isExpired(on: today) else { return nil }
        return report.answer
    }

    public mutating func set(_ answer: SelfAnswer, for key: SelfReportKey, on day: DateDay) {
        answers[key.rawValue] = SelfReport(answer: answer, answeredOn: day)
    }

    public mutating func clear(_ key: SelfReportKey) {
        answers[key.rawValue] = nil
    }

    // MARK: Codable (lenient: unknown keys or values from another build are dropped, not fatal)

    private enum CodingKeys: String, CodingKey {
        case version, answers, selectedServices, accountsPickerDone, carrier, doItAllNow
        case firstRunOn, groupCompletedOn, serviceIntroducedOn
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? SelfReportState.currentVersion
        let rawAnswers = (try? container.decodeIfPresent([String: Failable<SelfReport>].self, forKey: .answers)) ?? [:]
        answers = rawAnswers.compactMapValues(\.value).filter { SelfReportKey(rawValue: $0.key) != nil }
        let rawServices = (try? container.decodeIfPresent([String].self, forKey: .selectedServices)) ?? []
        selectedServices = Set(rawServices.compactMap(ServiceKey.init(rawValue:)))
        accountsPickerDone = (try? container.decodeIfPresent(Bool.self, forKey: .accountsPickerDone)) ?? false
        carrier = (try? container.decodeIfPresent(String.self, forKey: .carrier)).flatMap(Carrier.init(rawValue:))
        doItAllNow = (try? container.decodeIfPresent(Bool.self, forKey: .doItAllNow)) ?? false
        firstRunOn = try? container.decodeIfPresent(DateDay.self, forKey: .firstRunOn)
        let rawGroups = (try? container.decodeIfPresent([String: DateDay].self, forKey: .groupCompletedOn)) ?? [:]
        groupCompletedOn = Dictionary(uniqueKeysWithValues: rawGroups.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        let rawIntro = (try? container.decodeIfPresent([String: DateDay].self, forKey: .serviceIntroducedOn)) ?? [:]
        serviceIntroducedOn = Dictionary(uniqueKeysWithValues: rawIntro.compactMap { key, value in
            ServiceKey(rawValue: key).map { ($0, value) }
        })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(answers, forKey: .answers)
        try container.encode(selectedServices.map(\.rawValue).sorted(), forKey: .selectedServices)
        try container.encode(accountsPickerDone, forKey: .accountsPickerDone)
        try container.encodeIfPresent(carrier?.rawValue, forKey: .carrier)
        try container.encode(doItAllNow, forKey: .doItAllNow)
        try container.encodeIfPresent(firstRunOn, forKey: .firstRunOn)
        try container.encode(
            Dictionary(uniqueKeysWithValues: groupCompletedOn.map { (String($0.key), $0.value) }),
            forKey: .groupCompletedOn)
        try container.encode(
            Dictionary(uniqueKeysWithValues: serviceIntroducedOn.map { ($0.key.rawValue, $0.value) }),
            forKey: .serviceIntroducedOn)
    }
}

/// Decodes a value or nil, so one bad element doesn't discard its siblings.
struct Failable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
