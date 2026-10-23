// romance_investment (weight 3, SPEC §5.3): guaranteed returns, crypto platform, "my uncle at the
// exchange". Also the romance and "wrong number" openers that lead into pig-butchering, and the
// 2025–26 "task job" scams (paid to rate products, then asked to deposit).

import Foundation

struct RomanceInvestmentRule: ScamRule {
    let id = RuleID.romanceInvestment

    static let matcher = PhraseMatcher([
        // Investment.
        #"guarantee(d|s)? ([\w-]+ ){0,2}(returns?|profits?|income|daily|weekly|monthly|payouts?|earnings|gains|roi)"#,
        #"\d+(\.\d+)? ?% (daily|weekly|monthly|guaranteed|returns?|profits?|roi|per day|per week|a day|a week|each day|every day|in a week)"#,
        #"(daily|weekly) (returns?|profits?|earnings|gains) of"#,
        #"(risk[- ]free|no[- ]risk|zero[- ]risk) (investment|returns?|profits?|trading|income|opportunity|guaranteed)"#,
        #"(crypto|bitcoin|forex|trading|investment|mining|arbitrage|ai trading|quant|quantitative) (platform|opportunity|mentor|coach|group|signals|pool|bot)"#,
        #"(crypto|bitcoin|forex|ai trading|mining|arbitrage) app"#,
        #"(our|my|this|the|their) (trading|investment|investing|crypto) (app|account|platform)"#,
        #"(create|open|register|set up|fund) (a |your |an )?(trading|investment|crypto) (account|wallet)"#,
        #"(uncle|aunt|cousin|friend|mentor|teacher|brother|sister|father|dad|boss)( who)? (works |working |is |is a [\w ]{0,20} )?(at|with|for|in) (the |an |a )?(exchange|bank|hedge fund|trading firm|investment firm|investment bank|goldman|wall street|nasdaq|stock exchange|crypto exchange)"#,
        #"insider (tip|tips|info|information|knowledge|trading|signal|signals)"#,
        #"(double|triple|10x|multiply) (your|my|the) (money|investment|deposit|bitcoin|crypto|savings)"#,
        "passive income", #"liquidity (mining|pool)"#, "investment opportunity", #"make money (fast|from home|online)"#,
        #"(withdraw|withdrawal|release (your|the) funds|unlock (your|the) (funds|account|profits))[^.!?\n]{0,50}(fee|tax|taxes|deposit|pay|verification payment|unlock fee)"#,
        #"(earn|make) (up to )?\$?\d[\d,]* (a|per|each|every|/) ?(day|week|hour)"#,
        // Task-job scams.
        #"(rate|like|review|optimi[sz]e|boost|complete) ([\w-]+ ){0,3}(products|videos|apps|hotels|orders|tasks)[^.!?\n]{0,80}(earn|commission|\$|paid|salary)"#,
        #"(remote|part[- ]time|online|home) (job|position|work|opportunity)[^.!?\n]{0,80}\$\d+ ?(per|a|/) ?(day|hour|week)"#,
        // Job offers with pay "per day" and a recruiter on a chat app.
        #"(daily pay|pays daily|paid daily|\$[\d,]+(-\$?[\d,]+)?k? ?(/|per|a) ?(day|week|hour))[^\n]{0,120}(whatsapp|telegram|signal|wechat)"#,
        #"(whatsapp|telegram|signal|wechat)[^\n]{0,120}(daily pay|pays daily|paid daily|\$[\d,]+(-\$?[\d,]+)?k? ?(/|per|a) ?(day|week|hour))"#,
        #"(recruiter|hr|hiring manager|recruiting|talent)[^.!?\n]{0,60}(on|via) (whatsapp|telegram|signal|wechat)"#,
        #"(online|remote|part[- ]time|work from home|work-from-home|home-based) (job|position|work|opportunity)[^.!?\n]{0,80}(daily pay|\$\d[\d,]* ?(per|a|/) ?(day|week|hour)|no experience)"#,
        #"\$\d[\d,]*k? ?(/|per|a) ?(day|week)[^.!?\n]{0,60}(from home|no experience|remote|flexible)"#,
        #"(make|earn) \$\d[\d,]*k? ?(/|per|a) ?(day|week)"#,
        #"mystery shoppers?"#,
        #"(boost|optimi[sz]e|rate|like) ([\w'-]+ ){0,3}(app )?(rankings|ratings|reviews)[^.!?\n]{0,80}(earn|commission|\$|paid)"#,
        #"(crypto|trading|forex) strategy"#,
        // Romance.
        #"(i|i've|i have) (fell|fallen|am falling|'m falling) (in love )?(for|with) you"#,
        #"(oil rig|offshore rig|deployed (overseas|in)|peacekeeping mission|un mission|military doctor|army doctor|ship engineer|working overseas|stationed overseas)"#,
        #"(can't|cannot|unable to|can not) (access|reach|get to|touch) my (bank|money|funds|account|inheritance)"#,
        #"(plane|flight|airline) tickets?[^.!?\n]{0,50}(money|pay|send|help|afford|cost)"#,
        #"customs (fee|clearance|charge|duty)[^.!?\n]{0,50}(gift|package|parcel|box|gold|inheritance)"#,
        #"wrong number[^\n]{0,160}(nice to meet|be friends|make friends|keep (in touch|chatting)|where are you from|lovely|fate|destiny|meant to be)"#,
        #"(we )?(met|matched) (on|at|through) (facebook|instagram|tinder|bumble|match|hinge|whatsapp|the dating|a dating|linkedin|words with friends|telegram)"#,
    ], negatable: true)

    func fires(in context: RuleContext) -> Bool {
        Self.matcher.matches(in: context)
    }
}
