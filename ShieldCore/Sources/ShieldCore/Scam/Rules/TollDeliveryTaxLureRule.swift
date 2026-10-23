// toll_delivery_tax_lure (weight 3, SPEC §5.3): unpaid toll, package held, IRS/tax refund,
// Medi-Cal/benefit, Ahold/grocery refund. These match the §7 bulletins `tollText`, `packageHeld`,
// `irsRefund`, `mediCalBreachPhish` and `aholdRefundPhish`.
//
// A genuine "Your package was delivered" does not fire; "your package is on hold" does.

import Foundation

struct TollDeliveryTaxLureRule: ScamRule {
    let id = RuleID.tollDeliveryTaxLure

    static let tollName = #"(toll|tolls|e-? ?z ?pass|fas ?trak|sunpass|txtag|toll ?tag|ntta|peach pass|i-?pass|good to go pass|toll by plate|turnpike|toll road|toll roads|e-?zdrive)"#
    static let grocery = #"(ahold|delhaize|stop ?(&|and|n) ?shop|food lion|hannaford|giant food|the giant company|giant eagle|martin's food|peapod)"#
    static let benefit = #"(medi-?cal|medicare|medicaid|social security|ssa|snap|ebt|calfresh|wic|edd|covered california)"#

    static let matcher = PhraseMatcher([
        // Tolls.
        #"(unpaid|outstanding|overdue|pending|unsettled|past due|due) "# + tollName,
        tollName + #" (balance|charges?|fee|fees|invoice|payment|bill|notice|violation|amount|debt|account)[^.!?\n]{0,40}(due|outstanding|unpaid|overdue|owed|pending|immediately|today|penalt|late|suspend)"#,
        tollName + #"[^.!?\n]{0,60}(unpaid|overdue|outstanding|owe|owed|late fee|penalt|suspend|past due|balance due)"#,
        #"(you have|there is|there's) (an? )?(unpaid|outstanding|overdue) (toll|balance|invoice|fee|ticket|citation|violation)"#,
        // Traffic tickets and the DMV.
        #"(dmv|department of motor vehicles|motor vehicle)[^.!?\n]{0,60}(unpaid|ticket|violation|suspend|fine|penalt|license will|registration will|outstanding|owe)"#,
        #"(traffic|parking|speeding|red light|camera) (ticket|violation|citation|fine)[^.!?\n]{0,60}(unpaid|pay|due|outstanding|overdue)"#,
        // Packages.
        #"(package|parcel|shipment|delivery|item|mail|mailpiece) (is |has been |was |is being |will be |is currently )?(on hold|held|suspended|undeliverable|returned to sender|unable to be delivered|could not be delivered|cannot be delivered|can't be delivered|failed|stopped|detained|stuck at|awaiting (payment|confirmation|your))"#,
        #"(unable|failed|could not|couldn't|cannot|can't|were unable) (to )?(deliver|be delivered|complete (the |your )?delivery)"#,
        #"(redelivery|re-delivery|reschedule delivery|rescheduling|customs|storage|warehouse|unpaid shipping|additional shipping|postage due) (fee|fees|charge|charges|payment|cost)"#,
        #"(incomplete|invalid|wrong|incorrect|missing|unclear|insufficient) (shipping |delivery |house |street )?(address|address information|address details)"#,
        #"(update|confirm|verify|correct) (your )?(shipping|delivery|mailing) (address|details|information|info)"#,
        #"(pay|settle)[^.!?\n]{0,20}(customs|duty|duties|import tax)"#,
        #"customs[^.!?\n]{0,60}(fee|charge|duty|clearance|holding|held|seized)"#,
        // Tax refunds and the IRS.
        #"(tax|irs|federal|state|treasury) (refund|rebate|return|credit)[^.!?\n]{0,60}(pending|on hold|ready|approved|processing|claim|available|eligible|awaiting|issued|unclaimed|verify|owed)"#,
        #"(irs|internal revenue|treasury)[^.!?\n]{0,80}(refund|owe|back taxes|warrant|arrest|lawsuit|penalt|audit|unpaid|outstanding|claim|stimulus|levy|lien|garnish)"#,
        #"(stimulus|relief|rebate) (check|payment|deposit)"#,
        // State tax agencies.
        #"(state tax|tax (dept|department|office|board|agency|authority|bureau)|department of (taxation|revenue)|franchise tax board|revenue (agency|department))[^.!?\n]{0,80}(refund|owe|back taxes|warrant|arrest|lawsuit|penalt|audit|unpaid|outstanding|levy|lien|garnish|balance|final notice)"#,
        #"(unpaid|outstanding|overdue|past due) (state |federal |property |income )?tax(es)? (balance|bill|debt|amount)"#,
        #"back taxes"#, #"(owe|owed|owing) \$?\d[\d,.]* (in |of )?(federal |state |unpaid )?(taxes|tax)"#,
        #"(you are|you're|you have been|you've been) (eligible|approved|selected|owed|due|entitled) (for |to )?(a |an )?([\w$,.-]+ ){0,2}(refund|rebate|reimbursement|compensation|settlement|payout|grant)"#,
        #"claim (your|the) ([\w-]+ ){0,2}(refund|rebate|reimbursement|compensation|settlement|payout|reward|prize|grant)"#,
        // Prizes and gift-card giveaways ("You have been selected to receive a $100 gift card.
        // Claim yours today").
        #"(you (have|'ve) been|you've been|you are|you're|you were) (selected|chosen|picked|approved|pre-?approved|eligible)[^.!?\n]{0,40}(gift ?cards?|prize|reward|voucher|sweepstakes|giveaway|free (iphone|ipad|tv|gift)|\$\d)"#,
        #"you (have |'ve )?won (a |an |the |our )?([\w$,.-]+ ){0,3}(prize|gift ?cards?|reward|voucher|cash prize|sweepstakes|lottery|jackpot|iphone|ipad|\$\d)"#,
        #"(you are|you're) (a|the|our) (lucky |grand |big )?(winner|prize winner)"#,
        #"claim (yours|it now|now|your (gift|prize|reward|winnings|gift card)s?)"#,
        #"(unclaimed|pending|outstanding) (refund|rebate|reimbursement|compensation|settlement|payout)"#,
        // Medi-Cal and other benefits.
        benefit + #"[^.!?\n]{0,80}(breach|exposed|compromised|leaked|verify|suspend|suspended|renew|terminate|terminated|cancel|cancelled|canceled|update your|will end|will stop|ending|lose|locked|expire|expired|expiring|deactivat|reactivat|on hold)"#,
        #"(your )?(benefits?|coverage) (will be |has been |is |are )?(terminated|stopped|suspended|cancelled|canceled|ended|discontinued|locked|on hold)"#,
        #"(grocery|supermarket|store) (refund|compensation|reimbursement|reward|gift card)"#,
        #"(data|security|information) (breach|incident|exposure)[^.!?\n]{0,80}(refund|compensation|claim|verify|confirm|update|eligible|payment|gift card|credit monitoring)"#,
        // Grocery refunds (Ahold Delhaize: Stop & Shop, Food Lion, Hannaford, Giant).
        grocery + #"[^.!?\n]{0,80}(refund|compensation|reimburse|reimbursement|gift card|credit|breach|claim|reward|survey|affected|exposed|cyberattack|cyber attack|apology)"#,
    ])

    func fires(in context: RuleContext) -> Bool {
        Self.matcher.matches(in: context)
    }
}
