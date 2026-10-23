// pay_unusual (weight 5, SPEC §5.3): gift card, crypto, Bitcoin ATM, wire, Zelle/Venmo/Cash App
// "to protect your money", "safe account". Also a courier picking up cash or gold, which is how
// the same scams collect in 2025–26.
//
// "Thanks for the gift card, Grandma!" does not fire: gift cards count only when someone asks for
// them as payment, in bulk, or for the numbers on the back. "Never pay with gift cards" is negated.
//
// Three signals families also use count only with more context:
//   - "I accidentally sent you …" (the overpayment refund scam): $100 or more, or a request to
//     send it back with no amount. "I accidentally sent you $20 on Venmo" is a family mix-up.
//   - "Scratch off the silver strip": with a card, or a request to send or read what is under it
//     (not a lottery ticket).

import Foundation

struct PayUnusualRule: ScamRule {
    let id = RuleID.payUnusual

    // Zelle, Venmo and Cash App are left out here on purpose: families pay each other back with
    // them every day. They count only with "to yourself", "reverse the payment" and the like.
    static let rails = #"(gift[ -]?cards?|itunes cards?|google play (cards?|codes?)|apple (store |gift )cards?|app store cards?|steam (wallet )?(cards?|codes?)|razer gold( pins?| cards?| codes?)?|xbox (gift )?cards?|(psn|playstation) (cards?|codes?)|roblox (cards?|codes?)|ebay cards?|prepaid (cards?|debit cards?|visa)|vanilla (cards?|visa)|bitcoin|btc|crypto|cryptocurrency|usdt|tether|usdc|stablecoins?|ethereum|eth|ether|litecoin|ltc|dogecoin|xrp|solana|wire transfer|wire|western union|moneygram|money ?gram)"#
    static let cryptoWord = #"(bitcoin|btc|crypto|cryptocurrency|usdt|tether|usdc|stablecoins?|ethereum|eth|ether|litecoin|ltc|dogecoin|xrp|solana|digital currency|virtual currency)"#

    static let matcher = PhraseMatcher([
        // Paying a fee, fine, bill or tax with an unusual rail.
        #"(pay|paid|payment|settle|fee|fine|fines|bail|tax|taxes|bill|balance|penalty|deposit|charges?) ([\w$,.'-]+ ){0,5}(with|in|using|via|by|through) (a |an |the )?([\w-]+ ){0,4}"# + rails,
        // Buying gift cards in bulk or for an amount.
        // The cards scammers ask for by name (Apple, Google Play, Steam, Razer, Vanilla), or large
        // amounts. "Grab a few gift cards for the teachers" does not fire.
        #"(buy|purchase|get|pick up|grab) ([\w$,.'-]+ ){0,6}(apple( store)?|app store|google play|itunes|steam( wallet)?|razer gold|vanilla|ebay|xbox|playstation|psn|roblox) (gift |wallet |store |prepaid )?(cards|gift card|codes|pins)"#,
        #"(\$\d{3,}|\$\d,\d{3}|\d{3,} dollars) (worth )?(in |of )?([\w-]+ ){0,2}gift[ -]?cards"#,
        #"gift[ -]?cards?[^.!?\n]{0,40}(codes|numbers|pins|claim code|redemption code|scratch|back of)"#,
        #"(codes|numbers|pins|card numbers|claim codes) (on|from|off) (the )?(back of )?(the |each |those |all the )?(gift[ -]?cards?|cards)"#,
        #"(photo|picture|pic|pics|photos|pictures) of (the )?((back|front) of (the |each |every )?(gift )?cards?|cards|gift cards?|codes|card numbers)"#,
        // Any store's cards ("two Target gift cards, $250 each"): a large amount per card, cards
        // to cover a fee or a fine, or a photo of them asked for.
        #"gift[ -]?cards?[^.!?\n]{0,30}(\$([2-9]\d{2}|\d,\d{3}|\d{4,})|([2-9]\d{2}|\d,\d{3}) (dollars|each|apiece|bucks)|worth \$?([2-9]\d{2}|\d,\d{3}|\d{4,}))"#,
        #"gift[ -]?cards?[^.!?\n]{0,60}(to cover|to pay( for| off)?|to settle|to clear|for) (the |your |a |his |her |my |this |that )?([\w$,.-]+ ){0,2}(fee|fees|fine|fines|bail|tax|taxes|warrant|bond|penalty|ticket|charges)"#,
        #"gift[ -]?cards?[^\n]{0,80}(send|text|email|take|snap|shoot)( me| us)? (a |the |some )?(photo|picture|pic|pics|photos|pictures|snapshot|image|images|scan)s? of (them|both|each( one)?|all of them|the back|the backs|the front and back|the codes?|the numbers|the pins?)"#,
        // "get $900 over to them by wire", "they take Bitcoin at that kiosk"
        #"(send|pay|transfer|get|bring|deposit|lend|loan|give)[^.!?\n]{0,30}\$?\d[\d,]*[^.!?\n]{0,20}(by|via|through|with|using|as a|in|of) (a )?(wire|wire transfer|western union|moneygram|"# + cryptoWord + ")",
        cryptoWord + #"[^.!?\n]{0,30}(atm|atms|kiosk|kiosks)"#,
        // Being walked to a kiosk or ATM while on the phone.
        #"(direct|walk|guide) you (to|through) (the |a )?(nearest )?([\w-]+ )?(kiosk|atm|bitcoin machine|crypto machine)"#,
        // Wallet drainers: "link and connect your wallet first".
        #"connect (your |a )?(crypto |digital |web3 |metamask |coinbase |trust |phantom )?wallet"#,
        // Fake-check jobs and overpayments: "hold on to $75, return the remainder in gift cards",
        // a check sent so you can "purchase supplies through our vendor".
        #"keep (\$\d[\d,]*|the first \$\d[\d,]*|\d+ ?%)[^.!?\n]{0,40}(send|wire|return|transfer|mail) (back )?(the rest|the remainder|the balance|the difference|the excess)"#,
        #"(send|wire|transfer|return|mail) (back )?(the rest|the remainder|the balance|the difference|the excess)[^.!?\n]{0,30}(via|by|with|using|in|as|through) (a |an |the )?([\w-]+ ){0,2}"# + rails,
        #"(send|mail|deposit|cash|overnight) (you )?(a |the )?check[^.!?\n]{0,80}(buy|purchase|pay)[^.!?\n]{0,60}(vendor|supplier|equipment|gift cards?)"#,
        // "send $650 to this account": money to an account a message just made up.
        #"(send|transfer|wire|zelle|deposit|pay)[^.!?\n]{0,20}\$?\d[\d,]* (to|into) (this|that|the following|a different|another|my friend'?s|the nurse'?s|the lawyer'?s) (account|bank account|account number)"#,
        // "Venmo them $2,400 tonight"
        #"(zelle|venmo|cash ?app) (me |them |him |her |us )?\$\d{1,3},?\d{3}"#,
        // "approve a reversal": a "reversal" that is really a payment out.
        #"(approve|authorize|accept|confirm|complete) (a |the |this )?(reversal|reversal transfer|refund transfer|secure reversal)"#,
        // Crypto ATMs and wallets.
        #"(bitcoin|btc|crypto|cryptocurrency|coin|digital currency|virtual currency|digital coin) (atm|atms|kiosk|kiosks|machine|machines|terminal|terminals)"#,
        "bitcoin depot", "coinflip atm", "athena bitcoin", "coinme", "byte federal", "rockitcoin", "budget coinz", "coinhub",
        #"(buy|purchase) "# + cryptoWord + #"[^.!?\n]{0,60}(atm|kiosk|machine|terminal|coinstar|send|wallet|address|qr code)"#,
        cryptoWord + #"[^.!?\n]{0,60}(to|into) (this|the|my|our) (wallet|address|qr code|wallet address)"#,
        #"(send|deposit|put|transfer|convert|pay|move|feed) ([\w$,.'-]+ ){0,6}(in|into|as|via|to|using|at) (a |the |your |an )?"# + cryptoWord + #"( wallet| account| address| atm)?"#,
        // "Send 0.05 BTC here", "pay 0.1 ETH to settle the fine"
        #"(send|pay|transfer|deposit|wire|move) \d*[.,]?\d+ ?"# + cryptoWord,
        #"(wallet address|crypto wallet address|bitcoin address|qr code to (deposit|pay|send))"#,
        // Wires.
        #"(wire|send a wire|make a wire|do a wire|initiate a wire)( transfer)? (the |your |\$?\d[\d,.]*|money|funds|it|them|payment)"#,
        #"(send|wire|transfer)[^.!?\n]{0,30}(western union|moneygram|money gram|ria money)"#,
        // "Safe account" and "protect your money".
        #"safe(ty)? (account|wallet|vault)"#,
        #"(secure|protected|safe|new|temporary|holding) account (to protect|for your protection|for safekeeping|for safe keeping)"#,
        #"(send|transfer|move|zelle|venmo|wire|deposit|withdraw|put|keep)[^.!?\n]{0,60}(protect|secure|safeguard) (your|the|all your) (money|funds|savings|account balance|life savings)"#,
        #"(protect|secure|safeguard) (your|the|all your) (money|funds|savings|account balance|life savings)[^.!?\n]{0,12}(send|transfer|move|zelle|venmo|wire|withdraw)"#,
        #"(send|transfer|zelle|move|venmo)( the| your| all your| all of your)?( money| funds| savings| balance| account balance| it| payment)? to yourself"#,
        #"(zelle|venmo|cash ?app)[^.!?\n]{0,60}(reverse|refund|undo|cancel|block|stop) (the |this |a |that )?(payment|charge|transaction|transfer)"#,
        #"(move|transfer) (your|all your|the|all the|all of your) (money|funds|savings|balance) (to|into)"#,
        // A business bill, fine or fee paid by Zelle, Venmo or Cash App. ("I'll Venmo you for
        // pizza" has none of these words.)
        #"(balance|fine|fines|fee|fees|invoice|tax|taxes|penalty|disconnection|ticket|bail|deposit|past due|overdue)[^.!?\n]{0,60}(via|with|using|through|by|on) (zelle|cash ?app|venmo|apple cash)"#,
        #"(pay|send)[^.!?\n]{0,30}(via|with|using|through|on) (zelle|cash ?app|venmo|apple cash)[^.!?\n]{0,60}(avoid|disconnect|interruption|shut ?off|suspension|penalt|late fee|arrest|warrant|release)"#,
        // Large person-to-person transfers ($1,000 or more) asked for by text.
        #"(send|transfer|zelle|venmo|wire|pay)[^.!?\n]{0,20}\$\d{1,3},?\d{3}[^.!?\n]{0,30}(via|with|on|through|using|by) (zelle|venmo|cash ?app|apple cash)"#,
        // Paying first to release money ("to withdraw your funds you must first pay a 15% tax").
        #"(withdraw|withdrawal|release|unlock|receive)[^.!?\n]{0,40}(must|need to|have to|required to|first|until (i|you|we))[^.!?\n]{0,20}(pay|deposit|send)"#,
        // "A fraud specialist will call you to reverse the payment."
        #"(specialist|agent|representative|officer|someone|team|department) (will|is going to|can|may) (call|contact|text)[^.!?\n]{0,30}(reverse|cancel|stop|refund|undo|recall) (the|this|that|a|your) (payment|transfer|transaction|charge|zelle)"#,
        // Depositing money into a crypto "platform" at a stranger's direction.
        #"(deposit|invest|start with|put in|transfer)[^.!?\n]{0,15}\$\d[\d,]*[^.!?\n]{0,40}(crypto|bitcoin|btc|usdt|trading (platform|account|app)|platform|exchange)"#,
        // Couriers collecting cash or gold.
        #"(courier|agent|officer|messenger|someone|a man|a woman|a guy|a driver|our representative)( named [\w-]+)? (will |is going to |to |can )?(come|stop by|pick up|collect|meet you)[^.!?\n]{0,40}(cash|money|gold|envelope|funds)"#,
        #"(cash|money) in (an|a sealed|a) (envelope|box|shoebox)"#,
        #"(mail|ship|fedex|overnight) (the |your )?(cash|money)"#,
        #"(buy|purchase) gold (bars|coins)"#, "gold bars",
    ], negatable: true)

    /// "I accidentally sent you …"
    static let overpayment = PhraseMatcher([
        #"(accidentally|mistakenly|by mistake|wrongly|by accident) (sent|paid|transferred|deposited|zelled|venmoed) (you|to you|to your|into your)[^.!?\n]{0,40}\$(\d{3,}|\d{1,3},\d{3})"#,
        #"(accidentally|mistakenly|by mistake|wrongly|by accident) (sent|paid|transferred|deposited|zelled|venmoed) (you|to you|to your|into your) (money|funds|a payment|payment|cash|the money)[^$]{0,80}(send it back|send (the money|it) back|refund|return (it|the money|the funds)|reverse)"#,
        #"(sent|paid|transferred|deposited) (you|to you|into your account)[^.!?\n]{0,40}(by mistake|by accident|accidentally|mistakenly)[^.!?\n]{0,40}\$(\d{3,}|\d{1,3},\d{3})"#,
    ], negatable: true)

    /// "Scratch off the silver strip …"
    static let scratch = PhraseMatcher([
        #"scratch (off )?(the )?(silver|gray|grey) ?(strip|panel|coating|area|part|label)"#,
        #"scratch off the (back|pin|code|strip)"#,
    ], negatable: true)
    static let scratchContext = PhraseMatcher([
        #"(cards?|gift|pin|pins|codes?)"#,
        #"(send|text|read|tell|give|photo|picture|pic|pics) "#,
    ])
    static let lottery = PhraseMatcher([#"(lottery|lotto|scratcher|scratch-?off ticket|powerball|mega millions|instant ticket)"#])

    /// A courier or "agent" coming to the door, anywhere in the message ("Please get $2,000 ready
    /// in cash, a courier will stop by"): counts with cash mentioned anywhere in it.
    static let courier = PhraseMatcher([
        #"(courier|messenger|agent|officer|our representative|a representative|bail bondsman|bondsman|someone|a man|a woman|a guy|a driver|the lawyer'?s? (assistant|associate|clerk|courier)|a (friend|associate|colleague) of the lawyer'?s?)( named [\w-]+)? (will |is going to |to |can |should |would )?(come|come by|stop by|swing by|be there|pick (it |them |the [\w-]+ )?up|collect|meet you|get it|get the)"#,
    ], negatable: true)
    static let cash = PhraseMatcher([#"(cash|gold bars|gold coins|envelope|sealed envelope)"#])

    /// A crypto wallet address (Bitcoin, Ethereum, Tron), read from the text as written.
    // swiftlint:disable:next force_try
    static let walletAddress = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])((?i:bc1)[ac-hj-np-z02-9]{25,62}|[13][a-km-zA-HJ-NP-Z1-9]{25,34}|0x[0-9a-fA-F]{40}|T[1-9A-HJ-NP-Za-km-z]{33})(?![A-Za-z0-9])"#
    )
    static let sendMoney = PhraseMatcher([#"(send|pay|transfer|deposit|wire|move|scan)"#])

    static func hasWalletAddress(_ text: String) -> Bool {
        let ns = text as NSString
        for match in walletAddress.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if token.lowercased().hasPrefix("bc1") || token.hasPrefix("0x") { return true }
            // Base58 (legacy Bitcoin, Tron): a random mix of capitals, small letters and digits,
            // never an ordinary word or a tracking number.
            if token.contains(where: \.isUppercase), token.contains(where: \.isLowercase), token.contains(where: \.isNumber) { return true }
        }
        return false
    }

    func fires(in context: RuleContext) -> Bool {
        if Self.matcher.matches(in: context) { return true }
        if Self.courier.matches(in: context), Self.cash.matches(in: context) { return true }
        if Self.sendMoney.matches(in: context), Self.hasWalletAddress(context.normalized.text) { return true }
        if Self.overpayment.matches(in: context) { return true }
        if Self.scratch.matches(in: context), Self.scratchContext.matches(in: context), !Self.lottery.matches(in: context) {
            return true
        }
        return false
    }
}
