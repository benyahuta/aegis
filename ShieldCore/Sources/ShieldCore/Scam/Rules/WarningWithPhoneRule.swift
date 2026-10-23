// warning_with_phone (weight 4, SPEC §5.3): a security or virus "warning" that includes a phone
// number. Family Rule 4: "Real warnings never come with a phone number to call."
//
// Also covers the callback-invoice scam: "Your Norton renewal of $399.99 was charged. If you did
// not authorize this, call 1-8xx…" — a scare about money plus a number to call — and the
// callback-vishing openers: "Your iCloud was accessed from Russia", "A $1,249 MacBook was ordered
// on your account. Not you?", "This is Apple Support", "your bank's fraud team".

import Foundation

struct WarningWithPhoneRule: ScamRule {
    let id = RuleID.warningWithPhone

    static let warning = PhraseMatcher([
        #"(virus|viruses|malware|spyware|trojan|ransomware|keylogger|adware|worm)"#,
        #"(infected|hacked|compromised|breached)"#,
        #"security (alert|warning|breach|threat|issue|notice|risk|violation)"#,
        #"(fraud|fraudulent) (alert|activity|charge|charges|transaction|transactions|purchase|attempt)"#,
        #"suspicious (activity|login|log-in|sign-?in|transaction|transactions|charge|charges|purchase|access|attempt)"#,
        // The polite version: "We noticed unusual activity on your Apple ID. Please call Apple at …"
        // On an account or device, not "unusual activity on the security camera".
        #"(unusual|irregular|strange|unexpected|abnormal|unrecognized|unrecognised) (activity|behaviou?r|sign-?ins?|log-?ins?|logins?|access|transactions?|charges?|purchases?|attempts?)( (was|were|has been|have been) (detected|noticed|flagged|found|seen))?( (on|in|with|from|involving|for|to) (your|this|the) (account|accounts|card|debit card|credit card|apple ?id|apple account|icloud|bank account|online banking|banking|profile|device|computer|iphone|mac|pc|phone|wallet|paypal|amazon account|email|e-mail))"#,
        #"(unusual|irregular|strange|unexpected|abnormal|unrecognized|unrecognised) (activity|behaviou?r|sign-?ins?|log-?ins?|logins?|access|transactions?|charges?|purchases?|attempts?) (was|were|has been|have been) (detected|noticed|flagged|found)"#,
        #"unauthori[sz]ed (access|login|log-in|sign-?in|purchase|transaction|charge|activity|use|attempt|payment)"#,
        #"(computer|mac|device|iphone|phone|pc|system|account|ip address|ip|browser|network|apple id|icloud) (is |has been |was |will be |may be )?(locked|blocked|infected|compromised|hacked|disabled|suspended|at risk|frozen)"#,
        #"(do not|don't) (close|restart|shut down|shutdown|turn off|ignore|reboot) (this|your)"#,
        #"error (code|#|number)"#,
        #"(firewall|defender|windows security|apple security|mac security) (alert|warning|notice)"#,
        #"pornograph"#, "identity theft",
        // Legal threats with a number to call ("a warrant will be issued … call 1-8xx").
        #"(warrant|arrest|arrested|lawsuit|legal action|criminal (charges|case|investigation)|court (date|summons)|seized|frozen assets|wage garnishment|garnish|garnished|tax lien|tax levy|bank levy)"#,
        // Shut-off threats over a bill: "gas service gets shut off today over the past due amount".
        #"(disconnect|disconnected|disconnection|shut ?off|cut off|interruption|interrupted|suspended)[^.!?\n]{0,60}(overdue|unpaid|past due|missed payment|outstanding|balance)"#,
        #"(overdue|unpaid|past due|missed payment|outstanding balance)[^.!?\n]{0,60}(disconnect|disconnected|disconnection|shut ?off|cut off|interruption|interrupted)"#,
        #"(call|contact|phone|dial) (apple|microsoft|windows|amazon|geek squad|norton|mcafee|paypal|the|our|a)? ?(tech support|technical support|help ?desk|technician|security team|security department|fraud (department|team|line)|billing department|certified technician|apple support|microsoft support|support (team|line) immediately)"#,
        // Callback invoices.
        #"(renew(ed|al)?|auto-?renew(ed|al)?|subscription|invoice|charged|charge of|deducted|debited|purchase of)[^.!?\n]{0,40}\$\s?\d[\d,.]*"#,
        #"\$\s?\d[\d,.]*[^.!?\n]{0,40}(renewed|renewal|auto-?renew|charged|deducted|debited|billed)"#,
        #"(amount due|order total|total amount|amount charged|total charged|grand total|amount)[ .:]*\$\s?\d"#,
        #"(if you did not|if you didn't|if this wasn't you|if this was not you|didn't authorize|did not authorize|you did not make|you didn't make|to dispute|to stop (this|the) (charge|payment|transaction|renewal))"#,
        // Callback vishing: a sign-in from somewhere, an order placed on your account, "not you?".
        #"(accessed|signed in|logged in|sign-?in|log-?in|login|used|opened) (from|in) (a |an )?(new |unknown |unrecognized |foreign |different )?(device|location|country|ip|computer|browser|russia|china|nigeria|india|ukraine|romania|brazil|vietnam|iran|north korea|another (state|country))"#,
        #"(was|were|has been|have been) (ordered|purchased|placed|bought|charged|shipped|requested|made) (on|using|from|with|through|to) your (account|card|apple id|amazon account|paypal|bank account)"#,
        #"(not you|wasn't you|was this you|was it you|didn't order this|did not order this|didn't place this|did not place this)\?"#,
        #"this is (the |your )?([\w&'-]+ ){0,2}(support|security|billing|fraud|tech support|technical support|help ?desk|customer care)( team| department| desk| center| line| services?)?"#,
        #"(your |the )?(bank|bank's|card's|account|amazon|apple|paypal|microsoft|visa|mastercard)( security| fraud)? (fraud|security) (team|department|unit|division|line|specialist|office|prevention)"#,
        #"(go over|review|discuss|verify|confirm|dispute|cancel) (a |the |some |several |two |this )?(recent |unusual |large |pending |suspicious )(charges?|transactions?|purchases?|withdrawals?|transfers?|orders?)"#,
    ])

    /// "This is Mark from the Apple Advisory Team", "Sarah from the Medicare Benefits Center":
    /// a named person at a company's desk. Counts only when the message names a company or
    /// agency (a clinic's "billing office" calling back is not a brand).
    static let brandDesk = PhraseMatcher([
        #"(this is|my name is|i'm|i am|it's) [\w'-]+( [\w'-]+)? (from|with|at) (the |your )?([\w&'-]+ ){0,3}(advisory|support|security|benefits?|billing|fraud|protection|verification|claims|enrollment|account|accounts|customer care|customer service|services|compliance|investigations?|resolution) (team|center|centre|department|desk|office|unit|division|line|services|group)"#,
    ])

    func fires(in context: RuleContext) -> Bool {
        guard context.extraction.hasPhoneNumber else { return false }
        if Self.warning.matches(in: context) { return true }
        return !context.namedBrands.isEmpty && Self.brandDesk.matches(in: context)
    }
}
