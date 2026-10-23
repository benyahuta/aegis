// urgency_secrecy (weight 2, SPEC §5.3): "within 24 hours", "final notice", "don't tell anyone",
// "suspended". Also coaching to lie to the bank ("if the teller asks, say it's for repairs").
//
// Urgency phrases are negatable ("not urgent"); secrecy phrases are not, since they are
// themselves written as negations ("don't tell anyone").

import Foundation

struct UrgencySecrecyRule: ScamRule {
    let id = RuleID.urgencySecrecy

    static let urgency = PhraseMatcher([
        #"within (\d+|one|two|three|twelve|twenty-four|twenty four|forty-eight|48|24|72) ?(hours?|hrs?|h|days?|minutes?|mins?|business days?)"#,
        #"in the next (\d+|one|two|24|48) ?(hours?|hrs?|minutes?|mins?)"#,
        #"(final|last|urgent|second and final|third and final) (notice|warning|reminder|attempt|chance|request|demand)"#,
        #"(act|respond|reply|pay|call|click|update|verify|confirm) (now|immediately|today|asap|right away|at once|urgently|promptly)"#,
        #"(call|contact|pay|reply|respond|act)[^.!?\n]{0,50} (now|immediately|today|right away|asap)[.!?]"#,
        "immediately", #"urgent(ly)?"#, "time.?sensitive", #"expires? (today|tonight)"#, #"(expire|expires|ends) at midnight"#,
        #"(account|card|service|license|licence|benefits?|apple ?id|icloud|access|membership|subscription|number|registration|coverage|profile|wallet|computer|mac|pc|iphone|device|browser|ssn|social security number) (has been |was |is |will be |may be |are )?(temporarily |permanently )?(suspended|deactivated|locked|frozen|restricted|limited|disabled|blocked|terminated|closed|cancelled|canceled|deleted|on hold)"#,
        #"(suspend|suspension|deactivat|lock|freeze|restrict|terminat|clos|cancel)(e|ed|ion|ing)? (of )?your (account|card|service|license|benefits?|apple ?id|icloud|access|membership|number|registration|coverage)"#,
        #"(avoid|to avoid|or (face|incur|risk)|risk of|subject to) (a |an |additional |further )?(late fees?|penalt(y|ies)|legal action|suspension|arrest|fines?|prosecution|charges|collections?|interest|termination|deactivation|surcharges?|disconnection|disconnect|shut ?off|service interruption|cancellation|repossession|being arrested)"#,
        #"(legal action|arrest warrant|warrant (for|out for) your arrest|warrant[^.!?\n]{0,30}(for your arrest|issued|in your name)|lawsuit (has been|was) filed|(you will|you'll) be arrested|criminal charges|court summons)"#,
        #"(today|tonight) only"#,
        // Renewals and charges landing today: "will auto-renew today for $139", "renews automatically tomorrow".
        #"(auto-?renew|auto-?renews|renew|renews|renewed|be charged|be deducted|be billed)( automatically)? (today|tonight|tomorrow)"#,
        // Shut-off threats over a bill.
        #"(disconnect|disconnected|disconnection|shut ?off|cut off|interruption|interrupted)[^.!?\n]{0,60}(overdue|unpaid|past due|missed payment|outstanding balance)"#,
        #"(do not|don't|please do not|please don't) ignore( this| it)?"#,
        // No-link account lures: "We noticed unusual activity on your account", "restore access".
        #"(unusual|suspicious|irregular|strange) (activity|sign-?in|sign-?ins|login|log-?in|logins|access|transactions?|charges?)"#,
        #"(restore|regain|recover) (access|your account|full access)"#,
        #"unlock (your|the) (account|apple ?id|card|icloud|access)"#,
        #"keep your (account|card|apple ?id|funds|money|information|info) (safe|secure|protected|active|open)"#,
    ], negatable: true)

    static let secrecy = PhraseMatcher([
        #"(don't|do not|dont|never|must not|mustn't|can't|cannot|please don't) (tell|inform|mention|say anything to|talk to|discuss (this|it) with|contact|call) (anyone|anybody|your (family|kids|children|son|daughter|husband|wife|bank|spouse|grandchildren)|mom|dad|the bank|the police|family|the teller|bank staff|bank employees|others|any(one|body) else)"#,
        #"keep (this|it|our conversation|everything) (a )?(secret|confidential|private|between us|quiet|to yourself)"#,
        #"(between you and me|just between us|our little secret|strictly confidential)"#,
        #"(gag order|under a gag)"#,
        // Keeping the victim on the line, and threats against calling for help.
        #"(stay|remain|keep me|keep us) on the (phone|line)( with (me|us))?( the whole time| until| while| at all times)"#,
        #"(do not|don't|dont) hang up"#,
        #"(disclosure|discussion|discussing|sharing) (of )?this (matter|case|investigation|call) (is )?(strictly )?(prohibited|forbidden|not allowed|illegal)"#,
        #"if you (call|tell|contact|go to) (the police|the cops|anyone|anybody|the bank|your family)"#,
        #"(if|when) (the |a )?(bank|teller|cashier|bank employee|bank staff|clerk|store employee)[^.!?\n]{0,20}asks?"#,
        #"tell (them|the bank|the teller|the cashier|the clerk) (it's|it is|that it's|that it is|you are|you're) (for|buying|a gift|paying)"#,
    ])

    func fires(in context: RuleContext) -> Bool {
        return Self.secrecy.matches(in: context) || Self.urgency.matches(in: context)
    }
}
