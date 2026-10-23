// new_number_family (weight 3, SPEC §5.3): "Hi Mom/Dad", "new number", "lost my phone".
// Also the grandparent / AI-voice emergency script ("Grandma, it's me, I'm in jail").
//
// A plain "Hi Mom! Running late" does not fire: the greeting counts only together with a request
// for money or a favor, which is how the "Hi Mum" scam always turns.

import Foundation

struct NewNumberFamilyRule: ScamRule {
    let id = RuleID.newNumberFamily

    static let family = #"(mom|mum|mommy|mummy|mama|ma|dad|daddy|papa|pops|grandma|grandpa|granny|gran|nana|nan|grammy|gramps|grandmother|grandfather|auntie|aunt|uncle)"#

    static let strong = PhraseMatcher([
        #"(my |this is my |here's my |here is my |it's my )(new|different|temporary|temp|backup|borrowed|friend's|other|work) (phone |cell |mobile )?number"#,
        #"(new|different|temporary|temp|borrowed) (phone|cell|mobile) number"#,
        #"(texting|messaging|writing|calling) (you )?from (a |my )?(new|different|friend's|friend s|borrowed|temporary|temp|work) (phone|number|cell)"#,
        #"(lost|broke|broken|dropped|cracked|smashed|damaged|drowned) (my )?(phone|cell|iphone|mobile)"#,
        #"my (phone|cell|iphone|mobile) (is|got|was|has been) ([\w-]+ )?(broken|broke|lost|stolen|damaged|smashed|cracked|dead|in the shop|in for repair|in water|not working)"#,
        #"(save|delete|update) (this|my|the) (new )?(number|contact)"#,
        #"my (phone|cell|iphone|mobile) (broke|died|is dead|got stolen|was stolen|fell in)"#,
        #"(using|borrowing) (my |a )?(friend'?s|roommate'?s|buddy'?s|coworker'?s|nurse'?s|cellmate'?s|lawyer'?s|officer'?s)(?! (car|truck|van|house|place|couch|apartment|laptop|computer|account|wifi|wi-fi|bike|charger|netflix|login))"#,
        #"(on|calling (you )?from|texting (you )?from) (my |a )?(friend'?s|roommate'?s|buddy'?s|coworker'?s|nurse'?s|cellmate'?s|lawyer'?s|officer'?s) (phone|cell)"#,
        #"(delete|forget) (my|the) old (number|contact)"#,
        #"(text|message|reach|contact|msg) me (on|at|via|through) (this|my new|whatsapp|telegram|signal|this new)( number| one)?"#,
        // Emergency scripts (grandparent scam, AI voice clone).
        "(" + Self.family + #")[,!. ]+(it's|its|it is|this is) me"#,
        #"(this is|it's|its|it is) your (son|daughter|grandson|granddaughter|grandchild|nephew|niece|favorite|favourite)"#,
        #"(i'm|im|i am|i've been|i got|i was) (in jail|arrested|in an accident|in a car accident|in a crash|in the hospital|in trouble|kidnapped|detained|being held)"#,
        #"(need|needs) (bail|bail money|money for bail|a lawyer|money for a lawyer)"#,
    ])

    static let greeting = PhraseMatcher([
        #"(hi|hey|hello|hiya|dear|morning) "# + family,
        family + #"[,!. ]+(it's|its|it is|this is) [a-z]+"#,
    ])

    static let request = PhraseMatcher([
        #"(send|transfer|need|borrow|lend|pay|cover|loan)[^.!?\n]{0,30}(\$|money|cash|funds|bill|bills|rent|payment|invoice)"#,
        #"(do me|need) a (quick |small |big |huge )?favou?r"#,
        #"help me (pay|with (a|the|my|an) (bill|payment|rent|invoice|transfer))"#,
        #"(urgent|emergency|asap|right away|straight away)"#,
        #"in (a bit of |a little |some |big |serious |real |a lot of )?trouble"#,
        #"(have|get|withdraw|take out|pull out) \$\d[\d,]*[^.!?\n]{0,20}(ready|in cash|cash)"#,
    ])

    func fires(in context: RuleContext) -> Bool {
        if Self.strong.matches(in: context) { return true }
        return Self.greeting.matches(in: context) && Self.request.matches(in: context)
    }
}
