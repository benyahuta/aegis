// asks_for_code (weight 5, SPEC §5.3): asks for a code, PIN, password or verification number
// ("read me the code", "verify your account").
//
// Two things keep this from firing on ordinary family texts:
//   - Real one-time-code texts say "Never share this code" and "We will never ask for it". Those
//     phrases are negated (see PhraseMatcher) and do not count.
//   - "What's the wifi password?" and "Send me the gate code" are everyday questions. A plain
//     "code" or "password" counts only when it is a sign-in secret: qualified ("verification
//     code", "6-digit code", "Apple ID password"), the person's own ("your password", "your PIN"),
//     or the code that was just sent ("the code you just got").
//   - Clinics and pharmacies ask for a date of birth and check ID at the desk every day. A date of
//     birth counts only next to a money or sign-in secret ("SSN", "card number", "password"), and
//     "verify your identity" does not count for an in-person check ("at check-in", "at the
//     kiosk", "bring your photo ID").

import Foundation

struct AsksForCodeRule: ScamRule {
    let id = RuleID.asksForCode

    static let giveVerb = #"(read|tell|give|send|text|forward|fwd|share|say|provide|repeat|confirm|reply with|send back|read out|read off|verify|shoot|drop|pass|pass along)"#
    static let toWhom = #"(me|us|them|him|her|it to me|it to us|that to me|those to me)"#
    static let determiner = #"(the |that |your |this |those |these )"#
    static let filler = #"([\w-]+ ){0,3}"#

    static let qualifier = #"(verification|security|one-time|one time|onetime|confirmation|login|log-in|sign-?in|authentication|authorization|auth|access|2fa|two-factor|otp|text|sms|\d-digit|\d digit|six-digit|six digit|four-digit|four digit|eight-digit|apple ?id|apple account|icloud|bank|banking|account|zelle|venmo|paypal|google|gmail|whatsapp|facebook|instagram|card|debit card|credit card|reset|recovery|pairing|transfer|activation)"#
    static let qualifiedSecret = qualifier + #" (code|codes|pin|number|numbers|password|passcode)"#
    static let personalSecret = #"your (password|passcode|pin|pin number|code|codes|login|credentials|apple ?id password|card pin|atm pin)"#
    static let sentCode = #"(the |that |this |those )?(\d |\d-digit |six |six-digit |four |4-digit )?(code|codes|pin|number|numbers|digits)( that| which)? (we|i|you|u|they|apple|the bank|your bank|google|amazon|paypal|microsoft|whatsapp|facebook|our system|the system|it) (just )?(sent|send|will send|are sending|texted|emailed|got|received|get|receive|see|are seeing|will receive|should receive)"#
    /// A one-time sign-in code by its usual names (narrower than `qualifier`: no "confirmation
    /// number", which hotels and airlines send too).
    static let otpSecret = #"(verification|security|one-time|one time|onetime|login|log-in|sign-?in|authentication|auth|2fa|two-factor|otp|\d-digit|\d digit|six-digit|six digit|four-digit|four digit|apple ?id|google|gmail|whatsapp|facebook|instagram|bank|banking|zelle|venmo|paypal|reset|recovery|pairing|activation) (code|codes|pin|passcode)"#
    /// Physical codes people share every day ("the code to the garage").
    static let physicalCode = #"(?! (to|for|of|at) (the |your |my |our )?(gate|garage|door|front door|back door|wifi|wi-fi|lock|lockbox|lock box|alarm|building|house|locker|safe|keypad|bike|car|apartment|elevator|pool|gym|shed|mailbox|storage|unit|office|room|suite))"#
    static let sentCodePassive = #"(the |that |this )?(code|codes|pin|number|digits) (that was |that were |which was |which were |that just |which just )?(sent|texted|came|appeared|popped up|showed up|is showing)( to| on| in)? (you|your)"#

    static let moneySecret = #"(ssn|social security( number)?|(medicare|medicaid|medi-?cal) (number|id|card number|id number)|card number|account number|routing number|password|passcode|pin|cvv|mother's maiden name|bank (login|details|account)|online banking)"#
    /// In-person identity checks at a clinic, pharmacy or bank counter.
    static let notInPerson = #"(?![^.!?\n]{0,60}(at (the )?(check-?in|pick-?up|kiosk|front desk|desk|counter|window|pharmacy|clinic|office|branch|appointment|visit|reception|registration)|in person|when you (arrive|come in|pick up|check in)|upon arrival|on arrival))"#
    /// `phrase`, not after "bring", "show" or "have" ("bring your ID to verify your identity").
    /// The look-behind sits after the phrase so it only runs where the phrase matched.
    static func inPersonGuard(_ phrase: String) -> String { phrase + "(?<!(bring|show|present|have)[^.!?\n]{0,60}" + phrase + ")" }

    static let matcher = PhraseMatcher([
        // "read me the 6-digit verification code", "send us your PIN", "tell me the code you got"
        giveVerb + " " + toWhom + " (back )?" + determiner + "?" + filler + qualifiedSecret,
        giveVerb + " " + toWhom + " (back )?" + personalSecret,
        giveVerb + " " + toWhom + " (back )?" + sentCode,
        giveVerb + " " + toWhom + " (back )?" + sentCodePassive,
        // The spec's own example, "read me the code": a plain "the code" right after read/tell/say.
        #"(read|tell|say|repeat|read out|read off|give) (me|us|them|him|her) (back )?(the|that|this) (code|codes|pin|digits|numbers)"#,
        // "give the verification code to the agent", "share your PIN with us"
        giveVerb + " " + determiner + filler + "(" + qualifiedSecret + #"|code|codes|pin|passcode|password) (to|with) (me|us|our ([\w-]+ )?(agent|representative|rep|specialist|officer|technician|team|department)|the (agent|representative|rep|specialist|officer|technician|caller|person on the phone|support team|fraud department))"#,
        // "give the agent the code we send you"
        giveVerb + #" (the |our |a |your )?(agent|representative|rep|specialist|officer|technician|caller|person on the phone) (the |that |your |this |those )"# + filler + #"(code|codes|pin|passcode|password)"#,
        giveVerb + " " + sentCode,
        giveVerb + " " + sentCodePassive,
        // "say the code back to us", "repeat the six digits back to me"
        giveVerb + " " + #"(the |that |this |those |your )([\w-]+ ){0,2}(code|codes|pin|digits|numbers) (back )?to (me|us)"#,
        // "say back the PIN that we text you"
        #"(read|repeat|say|tell|give) (back|out|off) (the |that |this |those |your )"# + filler + #"(code|codes|pin|digits)"# + physicalCode,
        // Coaching past the warning: "ignore the 'never share' line, it's safe to tell it to us",
        // "when an agent phones asking for the code, tell it to him".
        // Anchored on the coaching, so the warning it talks past ("do not share this code") does
        // not negate it.
        #"(fine|ok|okay|safe|alright|all right) (for you )?to (give|read|share|tell|send) (it|that|them|the code)(?<=(code|codes|pin|passcode)[^\n]{0,200})"#,
        #"(rep|representative|agent|caller|specialist|officer|technician|someone) [^.!?\n]{0,30}(asks?|asking) (you )?for (it|the code|that code)[^.!?\n]{0,30}(read|give|tell|share|send) (it|that|the code)"#,
        // "we will need your expiry date and the card PIN"
        #"(i|we) (just |will |'ll |also )?(need|require|want) (you to (give|tell|read|confirm) (me|us) )?your [^.!?\n]{0,60}(?<![\p{L}])(card number|pin|password|passcode|cvv|security code|online banking)"# + notInPerson,
        // "tell me your user ID and then the password"
        #"(confirm|verify|tell me|give me|read me) your [^.!?\n]{0,40}(username|user name|user id)[^.!?\n]{0,30}(?<![\p{L}])(password|passcode|pin)"#,
        // "call us with your card number"
        #"(call|text|reply|contact|phone)[^.!?\n]{0,40} with your ([\w-]+ ){0,3}(card number|account number|routing number|ssn|social security number|pin|password|cvv|banking details|bank details)"#,
        // "Tap to keep the same password": a password phishing page.
        #"keep (your |my |the )?(current|existing|same) password"#,
        // "log in to your banking app so we can push the refund through"
        #"(have|keep|log ?in ?to|open) your (online banking|bank(ing)? (app|account|website))( open| ready| up)?[^.!?\n]{0,60}(agent|technician|representative|so (we|i|they|the agent) can|refund)"#,
        // Crypto wallet secrets: no company ever asks for them.
        #"(verify|enter|share|send|provide|confirm|type|give|read|submit|import|validate|sync) (me |us )?(your |the |my )?([\w-]+ ){0,2}(seed phrase|recovery phrase|secret phrase|seed words|recovery words|private key|wallet phrase|12-word phrase|24-word phrase)"#,
        // "reply with the code"
        #"reply (back )?with (the |your |this |that )"# + #"(code|pin|passcode|password|"# + qualifiedSecret + ")",
        // "what's the verification code", "what is the code you just got"
        #"what('s| is| was) (the |your |that )"# + filler + qualifiedSecret,
        #"what('s| is| was) "# + sentCode,
        #"what('s| is| was) "# + sentCodePassive,
        #"what('s| is| was) your (password|passcode|pin|apple ?id password)"#,
        // "our agent will ask for the code", "the representative needs your PIN"
        #"(agent|representative|rep|specialist|officer|technician|caller|advisor|team member|investigator) (will |is going to |may )?(need|needs|ask|asks|request|requests|require|requires)( you)? (for |to (read|give|tell|provide|confirm|share) )?(the|that|your|this) "# + filler + #"(code|pin|passcode|password)"#,
        // "verify your identity" online, not at the front desk
        inPersonGuard("verify your identity") + notInPerson,
        // "verify your account"
        #"verify your (account|apple ?id|apple account|icloud|bank account|card|debit card|credit card|billing|payment (info|information|details|method)|personal (info|information|details)|login|information|details|account information|banking)"#,
        inPersonGuard("confirm your identity") + notInPerson,
        #"confirm your (account (details|information|info)|password|pin|card|card on file|card (number|details|information)|social security|ssn|login|credentials|banking|billing (info|information|details)|payment (info|information|details)|personal (info|information|details))"#,
        // "enter your password", "provide your card number"
        #"(enter|provide|submit|re-?enter|type in|input|send us|send me) your (current |existing |old |full )?(password|passcode|pin|social security( number)?|ssn|card (number|details|information|info)|full card|bank(ing)? (details|login|information|info|account number|password)|login (details|credentials|information|info)|credentials|account number|routing number|billing (details|information|info)|payment (details|information|info)|cvv|security code|apple ?id password|online banking)"#,
        // "we need your SSN and date of birth"
        #"(need|require|send|provide|give|tell|confirm|verify|enter|update) [^.!?\n]{0,30}(social security number|ssn|mother's maiden name|bank login|online banking password|apple ?id password)"#,
        // "confirm your Medicare number", "verify your Social Security number": a benefits ID asked
        // for over the phone or by text (not at the front desk).
        #"(confirm|verify|provide|update|validate|give (me|us)|tell (me|us)|read (me|us)|send (me|us)|reply with|text (me|us)) (your |the )?(medicare|medicaid|medi-?cal|social security|ss) (number|id|id number|card number|card|beneficiary (id|number))"# + notInPerson,
        // A date of birth together with a money or sign-in secret, in either order.
        #"(date of birth|birth ?date|dob)[^.!?\n]{0,60}"# + moneySecret,
        moneySecret + #"[^.!?\n]{0,60}(date of birth|birth ?date|dob)"#,
        // "reply with your name and card number", "text us your account number"
        #"(reply|respond|text back|send|text|email) (back )?(with |us |me )?your ([\w-]+ (and |or |, )?){0,4}(card number|account number|routing number|ssn|social security number|pin|password|passcode|bank details|banking details|login details|cvv)"#,
        // "sign in to restore access"
        #"(sign|log) ?in (now )?to (verify|confirm|unlock|restore|reactivate|secure|validate|avoid)"#,
        // "let me know the code", "shoot me the code", "pls fwd the code", "drop us the 6 digits"
        #"(let (me|us) know|shoot (me|us)|drop (me|us)|fwd( me| us)?|forward( me| us)?|pass (me|us)|send (me |us )?over|text (me |us )?over) (the |that |your |this )?(code|codes|pin|digits|numbers)"# + physicalCode,
        #"(let (me|us) know|shoot (me|us)|fwd( me| us)?) "# + determiner + "?" + filler + qualifiedSecret,
        // "please send the verification code" (no "me"), "give the 6-digit code"
        giveVerb + " " + #"(the |that |your )"# + filler + otpSecret,
        // "what code did you receive?", "what digits did you get"
        #"what (code|codes|number|numbers|digits|pin) did (you|u) (just )?(get|receive|see|got)"#,
        // "I need the 6 digits Apple just sent you", "we need your verification code"
        #"(i|we|they|he|she) (just |really |urgently )?(need|needs|want|wants|require|requires|have to have|must have) "# + sentCode,
        #"(i|we|they|he|she) (just |really |urgently )?(need|needs|want|wants|require|requires|have to have|must have) "# + determiner + filler + otpSecret,
        // "Type the verification code here:", "enter the 6-digit code we texted you on this page"
        #"(enter|type|input|paste|put|key) (in )?(the |that |your )"# + filler + #"("# + otpSecret + #"|code|codes|pin)[^.!?\n]{0,40}(here|on this (page|site|website|form|link)|in this (box|field|form|page)|at this (link|site|page)|in the box below|into this (box|field|form))"#,
        // "Did you get a code? Send it over", "Google sent you a code, can you send it to me?"
        #"(did|have) (you|u) (get|got|receive|received|just get) (a|the|my|our|any) ([\w-]+ )?(code|text|pin|message)[^\n]{0,40}(send|text|forward|fwd|read|tell|give|share|shoot)( me| us)? (it|that|them|those|the code|the numbers|the digits)( over| back| to me| to us)?"#,
        #"(sent|texted|emailed|sending|texting) (you|u) (a|the|an) ([\w-]+ ){0,2}(code|pin|text)[^\n]{0,60}(send|text|forward|fwd|read|tell|give|share|shoot)( me| us)? (it|that|them|those|the code|the numbers|the digits)( over| back| to me| to us)"#,
    ], negatable: true)

    func fires(in context: RuleContext) -> Bool {
        Self.matcher.matches(in: context)
    }
}
