import XCTest
@testable import ShieldCore

/// SPEC §13.1 "Call quiz truth table" for §5.3.
final class CallQuizTests: XCTestCase {
    /// Independent restatement of §5.3:
    /// Any "Code", "Money moved", "Gift card or crypto" or "Remote access" answer → danger.
    /// A Government, Police or Apple claim with "No" to Q4 → danger. Anything else → beCareful.
    static func oracle(_ a: CallQuiz.Answers) -> Verdict {
        switch a.want {
        case .code, .moneyMoved, .giftCardOrCrypto, .remoteAccess: return .danger
        case .personalInfo, .nothingYet: break
        }
        switch a.caller {
        case .government, .policeOrCourt, .appleOrMicrosoft: return a.youCalledThem ? .beCareful : .danger
        case .bank, .familyMember, .other: return .beCareful
        }
    }

    func testFullTruthTable() {
        var count = 0
        for caller in CallQuiz.Caller.allCases {
            for want in CallQuiz.Want.allCases {
                for secret in [true, false] {
                    for called in [true, false] {
                        let answers = CallQuiz.Answers(caller: caller, want: want, secretOrRushed: secret, youCalledThem: called)
                        let expected = Self.oracle(answers)
                        XCTAssertEqual(CallQuiz.verdict(for: answers), expected, "\(answers)")
                        XCTAssertEqual(CallQuiz.evaluate(answers).verdict, expected, "\(answers)")
                        count += 1
                    }
                }
            }
        }
        XCTAssertEqual(count, 6 * 6 * 2 * 2)
    }

    func testNeverGreyForCalls() {
        for caller in CallQuiz.Caller.allCases {
            for want in CallQuiz.Want.allCases {
                for secret in [true, false] {
                    for called in [true, false] {
                        let answers = CallQuiz.Answers(caller: caller, want: want, secretOrRushed: secret, youCalledThem: called)
                        XCTAssertNotEqual(CallQuiz.verdict(for: answers), .noCommonSignsFound)
                    }
                }
            }
        }
    }

    func testSpecExamples() {
        XCTAssertEqual(CallQuiz.verdict(for: .init(caller: .bank, want: .code, secretOrRushed: false, youCalledThem: true)), .danger)
        XCTAssertEqual(CallQuiz.verdict(for: .init(caller: .other, want: .giftCardOrCrypto, secretOrRushed: false, youCalledThem: true)), .danger)
        XCTAssertEqual(CallQuiz.verdict(for: .init(caller: .appleOrMicrosoft, want: .nothingYet, secretOrRushed: false, youCalledThem: false)), .danger)
        XCTAssertEqual(CallQuiz.verdict(for: .init(caller: .appleOrMicrosoft, want: .nothingYet, secretOrRushed: false, youCalledThem: true)), .beCareful)
        XCTAssertEqual(CallQuiz.verdict(for: .init(caller: .bank, want: .personalInfo, secretOrRushed: true, youCalledThem: false)), .beCareful)
        XCTAssertEqual(CallQuiz.verdict(for: .init(caller: .familyMember, want: .nothingYet, secretOrRushed: false, youCalledThem: false)), .beCareful)
    }

    func testReasons() {
        let r = CallQuiz.evaluate(.init(caller: .policeOrCourt, want: .giftCardOrCrypto, secretOrRushed: true, youCalledThem: false))
        XCTAssertEqual(r.reasons, [.wantedGiftCardOrCrypto, .authorityCalledYou, .secretOrRushed])
        XCTAssertEqual(r.familyRuleNumber, 3)

        let family = CallQuiz.evaluate(.init(caller: .familyMember, want: .nothingYet, secretOrRushed: false, youCalledThem: false))
        XCTAssertEqual(family.reasons, [.familyVoice])
        XCTAssertEqual(family.familyRuleNumber, 6)

        let plain = CallQuiz.evaluate(.init(caller: .other, want: .nothingYet, secretOrRushed: false, youCalledThem: false))
        XCTAssertEqual(plain.reasons, [.unexpectedCall])
        XCTAssertEqual(plain.familyRuleNumber, 1)

        // They placed the call at a number they looked up: no "hang up and call back".
        let placed = CallQuiz.evaluate(.init(caller: .other, want: .nothingYet, secretOrRushed: false, youCalledThem: true))
        XCTAssertEqual(placed.reasons, [.youCalledThem])
        XCTAssertEqual(placed.familyRuleNumber, 2)

        for reason in CallQuiz.Reason.allCases {
            XCTAssertFalse(reason.text.isEmpty)
            XCTAssertEqual(reason.reasonKey, "scam.call.\(reason.rawValue)")
        }
        for caller in CallQuiz.Caller.allCases { XCTAssertFalse(caller.label.isEmpty) }
        for want in CallQuiz.Want.allCases { XCTAssertFalse(want.label.isEmpty) }
    }

    /// No reason or Family Rule contradicts the answers given: someone who called the company at a
    /// number they looked up (Q4 yes) is never told to hang up and call back, or to call their
    /// family member back on the number they already have.
    func testReasonsNeverContradictYouCalledThem() {
        for caller in CallQuiz.Caller.allCases {
            for want in CallQuiz.Want.allCases {
                for rushed in [false, true] {
                    let placed = CallQuiz.evaluate(.init(caller: caller, want: want, secretOrRushed: rushed, youCalledThem: true))
                    let label = "\(caller) \(want) rushed=\(rushed)"
                    XCTAssertFalse(placed.reasons.isEmpty, label)
                    for reason in placed.reasons {
                        XCTAssertFalse([.unexpectedCall, .familyVoice, .bankCalledYou, .authorityCalledYou].contains(reason), "\(label): \(reason)")
                        let text = reason.text.lowercased()
                        XCTAssertFalse(text.contains("call back") || text.contains("hang up") || text.contains("they called you"), "\(label): \(reason.text)")
                    }
                    XCTAssertNotEqual(placed.familyRuleNumber, 1, "\(label): rule 1 says hang up and call back")

                    let received = CallQuiz.evaluate(.init(caller: caller, want: want, secretOrRushed: rushed, youCalledThem: false))
                    XCTAssertFalse(received.reasons.contains(.youCalledThem), label)
                    if caller == .familyMember { XCTAssertTrue(received.reasons.contains(.familyVoice) || received.reasons.count == 3, label) }
                }
            }
        }
    }

    /// "Get into my computer" shows a rule about calls, not about phone numbers in warnings, when
    /// they called you; when you called them, the number most likely came from a pop-up warning.
    func testRemoteAccessRule() {
        let received = CallQuiz.evaluate(.init(caller: .appleOrMicrosoft, want: .remoteAccess, secretOrRushed: false, youCalledThem: false))
        XCTAssertEqual(received.reasons.first, .wantedRemoteAccess)
        XCTAssertEqual(received.familyRuleNumber, 1)
        let placed = CallQuiz.evaluate(.init(caller: .appleOrMicrosoft, want: .remoteAccess, secretOrRushed: false, youCalledThem: true))
        XCTAssertEqual(placed.familyRuleNumber, 4)
        XCTAssertEqual(RuleID.remoteAccess.familyRuleNumber, 1, "a text asking to get into your computer: check who it is yourself")
        XCTAssertEqual(RuleID.warningWithPhone.familyRuleNumber, 4)
    }

    /// The reason echoes what the person tapped: every choice named on an authority button
    /// ("Apple or Microsoft", "Police or court") is named in the reason they get.
    func testAuthorityReasonNamesEveryChoiceOnTheButton() {
        for caller in CallQuiz.Caller.allCases {
            let result = CallQuiz.evaluate(.init(caller: caller, want: .nothingYet, secretOrRushed: false, youCalledThem: false))
            guard result.reasons.contains(.authorityCalledYou) else { continue }
            let text = CallQuiz.Reason.authorityCalledYou.text.lowercased()
            for part in caller.label.lowercased().components(separatedBy: " or ") {
                XCTAssertTrue(text.contains(part), "\(caller.label): reason doesn't name \(part)")
            }
        }
    }
}
