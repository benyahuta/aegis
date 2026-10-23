// "Someone called me" (SPEC §5.3 Call quiz, P0): four big-button questions.
//
//   1. Who did they say they were?
//   2. What did they want?
//   3. Did they say to keep it secret or act fast?
//   4. Did *you* call *them* at a number you looked up yourself?
//
// Any "Code", "Money moved", "Gift card or crypto" or "Remote access" answer → danger.
// A Government, Police or Apple/Microsoft claim with "No" to Q4 → danger.
// Anything else → be careful. Never grey for calls.
//
// Answers live in memory only and are never stored or synced.

import Foundation

public enum CallQuiz {
    /// Q1: "Who did they say they were?"
    public enum Caller: String, CaseIterable, Sendable, Hashable {
        case bank
        case government
        case appleOrMicrosoft = "apple_or_microsoft"
        case familyMember = "family_member"
        case policeOrCourt = "police_or_court"
        case other

        /// Button label (§5.3).
        public var label: String {
            switch self {
            case .bank: "Bank"
            case .government: "Government"
            case .appleOrMicrosoft: "Apple or Microsoft"
            case .familyMember: "Family member"
            case .policeOrCourt: "Police or court"
            case .other: "Other"
            }
        }

        /// Claims that are always danger unless the person called the number themselves.
        var isAuthorityClaim: Bool {
            switch self {
            case .government, .policeOrCourt, .appleOrMicrosoft: true
            case .bank, .familyMember, .other: false
            }
        }
    }

    /// Q2: "What did they want?"
    public enum Want: String, CaseIterable, Sendable, Hashable {
        case code
        case moneyMoved = "money_moved"
        case giftCardOrCrypto = "gift_card_or_crypto"
        case remoteAccess = "remote_access"
        case personalInfo = "personal_info"
        case nothingYet = "nothing_yet"

        public var label: String {
            switch self {
            case .code: "A code"
            case .moneyMoved: "Move money"
            case .giftCardOrCrypto: "Gift card or crypto"
            case .remoteAccess: "Get into my computer"
            case .personalInfo: "Personal info"
            case .nothingYet: "Nothing yet"
            }
        }

        /// "Code", "Money moved", "Gift card or crypto" and "Remote access" are always danger.
        var isAlwaysDanger: Bool {
            switch self {
            case .code, .moneyMoved, .giftCardOrCrypto, .remoteAccess: true
            case .personalInfo, .nothingYet: false
            }
        }
    }

    /// The four answers.
    public struct Answers: Sendable, Hashable {
        public var caller: Caller
        public var want: Want
        /// Q3: they said to keep it secret or act fast.
        public var secretOrRushed: Bool
        /// Q4: the person called them, at a number they looked up themselves.
        public var youCalledThem: Bool

        public init(caller: Caller, want: Want, secretOrRushed: Bool, youCalledThem: Bool) {
            self.caller = caller
            self.want = want
            self.secretOrRushed = secretOrRushed
            self.youCalledThem = youCalledThem
        }
    }

    /// A plain-language reason for the call result. Compiled strings only.
    public enum Reason: String, CaseIterable, Sendable, Hashable {
        case wantedCode = "wanted_code"
        case wantedMoneyMoved = "wanted_money_moved"
        case wantedGiftCardOrCrypto = "wanted_gift_card_or_crypto"
        case wantedRemoteAccess = "wanted_remote_access"
        case wantedPersonalInfo = "wanted_personal_info"
        case authorityCalledYou = "authority_called_you"
        case bankCalledYou = "bank_called_you"
        case familyVoice = "family_voice"
        case secretOrRushed = "secret_or_rushed"
        case unexpectedCall = "unexpected_call"
        /// Nothing else fired and the person placed the call at a number they looked up: the
        /// "hang up and call back" advice would contradict their own answer (Q4).
        case youCalledThem = "you_called_them"

        public var reasonKey: String { "scam.call.\(rawValue)" }

        public var text: String {
            switch self {
            case .wantedCode:
                "They asked for a code. Never read a code to anyone."
            case .wantedMoneyMoved:
                "They asked you to move money. Real banks and agencies never do this."
            case .wantedGiftCardOrCrypto:
                "They asked for gift cards or crypto. Only scammers ask for these."
            case .wantedRemoteAccess:
                "They asked to get into your computer. Real support never calls you to do this."
            case .wantedPersonalInfo:
                "They asked for personal information."
            case .authorityCalledYou:
                "They called you and said they were the government, the police, a court, Apple or Microsoft. None of them call like this."
            case .bankCalledYou:
                "They called you and said they were your bank. Hang up and call the number on your card."
            case .familyVoice:
                "Voices can be faked. Call your family member back on the number you already have, or ask for the code word."
            case .secretOrRushed:
                "They told you to keep it secret or hurry."
            case .unexpectedCall:
                "Hang up and call back using a number you look up yourself."
            case .youCalledThem:
                "You called them at a number you looked up yourself. That's the right way to do it. Still, never read a code or move money because someone on the phone asked."
            }
        }
    }

    public struct Result: Sendable, Hashable {
        public let verdict: Verdict
        /// Most important first. At most 3 are shown.
        public let reasons: [Reason]
        /// Q4: the person placed the call, at a number they looked up.
        public var youCalledThem = false

        /// The Family Rule (§7, 1–6) to show with the result. Rule 1 ("Hang up and look it up.
        /// Call back using a number you find yourself.") is never shown to someone who just did
        /// that (Q4 yes).
        /// - Remote access: rule 1 when they called you; when you called them, the number most
        ///   likely came from a pop-up "virus" warning, which is rule 4.
        public var familyRuleNumber: Int {
            switch reasons.first {
            case .wantedCode: 2
            case .wantedMoneyMoved, .wantedGiftCardOrCrypto: 3
            case .wantedRemoteAccess: youCalledThem ? 4 : 1
            case .familyVoice: 6
            case .youCalledThem: 2
            default: youCalledThem ? 2 : 1
            }
        }
    }

    /// The §5.3 truth table.
    public static func verdict(for answers: Answers) -> Verdict {
        if answers.want.isAlwaysDanger { return .danger }
        if answers.caller.isAuthorityClaim && !answers.youCalledThem { return .danger }
        return .beCareful
    }

    public static func evaluate(_ answers: Answers) -> Result {
        var reasons: [Reason] = []
        switch answers.want {
        case .code: reasons.append(.wantedCode)
        case .moneyMoved: reasons.append(.wantedMoneyMoved)
        case .giftCardOrCrypto: reasons.append(.wantedGiftCardOrCrypto)
        case .remoteAccess: reasons.append(.wantedRemoteAccess)
        case .personalInfo: reasons.append(.wantedPersonalInfo)
        case .nothingYet: break
        }
        if !answers.youCalledThem {
            switch answers.caller {
            case .government, .policeOrCourt, .appleOrMicrosoft: reasons.append(.authorityCalledYou)
            case .bank: reasons.append(.bankCalledYou)
            case .familyMember, .other: break
            }
        }
        // "Call your family member back on the number you already have" only when they called you.
        if answers.caller == .familyMember && !answers.youCalledThem { reasons.append(.familyVoice) }
        if answers.secretOrRushed { reasons.append(.secretOrRushed) }
        // Every reason must agree with the answers given: "hang up and call back" is advice for a
        // call they received, never for one they placed at a number they looked up.
        if reasons.isEmpty { reasons.append(answers.youCalledThem ? .youCalledThem : .unexpectedCall) }
        let verdict = verdict(for: answers)
        Log.scam.info("scam.call verdict=\(verdict.rawValue, privacy: .public)")
        return Result(verdict: verdict, reasons: Array(reasons.prefix(3)), youCalledThem: answers.youCalledThem)
    }
}
