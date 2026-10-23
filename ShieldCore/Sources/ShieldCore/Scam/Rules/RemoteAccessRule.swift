// remote_access (weight 5, SPEC §5.3): AnyDesk, TeamViewer, "let me connect to your computer",
// "install this app". Also configuration/MDM profiles, which no stranger should ever send, screen
// sharing for a "fix", and the tech-support portals where a caller has you type a session code
// (fastsupport.com, support.me).
//
// "Download this app so we can video chat" is how a grandchild asks too, and nearly every app
// a relative recommends links to its own small site (cozi.com, teamsnap.com). A bare "install
// this app" counts only next to a fix-your-device story (support, security, a virus, a refund,
// an account), a link that looks built to deceive (an odd ending, lure words in the host, a
// shortener or IP address, a direct .apk/.dmg/.mobileconfig file), or money talk ("trading",
// "deposit") next to a link that is not a big brand's own or that anyone can publish to
// (TestFlight betas, file shares: how "trading apps" reach iPhones in pig-butchering scams).
// Screen sharing counts only next to a stranger's story (a virus, a hacker, a technician, a
// refund, a bank); "share your screen on FaceTime so I can see the printer" is family help.

import Foundation

struct RemoteAccessRule: ScamRule {
    let id = RuleID.remoteAccess

    static let device = #"(computer|mac|macbook|device|phone|iphone|pc|laptop|screen|system|desktop|ipad)"#

    static let matcher = PhraseMatcher([
        #"(anydesk|any desk|teamviewer|team viewer|ultraviewer|ultra viewer|logmein|log me in|gotoassist|goto assist|go to assist|goto resolve|rustdesk|supremo|zoho assist|connectwise|screenconnect|screen connect|splashtop|quick ?assist|quick ?support|remotepc|remote pc|ammyy|getscreen|aeroadmin|iperius|airdroid|hoptodesk|remote utilities|anyviewer|any viewer|vnc viewer|realvnc|tightvnc|ultravnc|dwservice|dw service|isl online|isl light|beyondtrust|bomgar|chrome remote desktop|fastsupport|join\.me|helpwire|zoho remote)"#,
        #"(let|allow|give|grant) (me|us|our (technician|tech|agent|specialist|team|engineer)|the (technician|tech|agent|specialist|engineer)) (to )?(connect|access|remote|log ?in|take control|control|remote in|jump on)( in| on)? (to |into |in |of )?(your )?"# + device,
        #"(give|grant|allow) (me|us|them|our (technician|tech|agent|team)) (remote )?(access|control) (to|of) your "# + device,
        // Not "remote control": that is the TV remote.
        #"remote (access|session|connection|support session|desktop|into your)"#,
        #"remotely (access|connect|control|log ?in|into|fix|repair)"#,
        #"(connect|log ?in|get|tap|dial) ?(in)?to your "# + device + #" (remotely|from here|for you)"#,
        #"(we|i|our technician|the technician) (can|will|need to|have to) (connect|remote|log ?in) (in)?to your "# + device,
        #"(install|download) ([\w-]+ ){0,2}(support|security|remote|protection|antivirus|anti-virus|helper|cleaner|repair|fix|cleanup|verification|recovery|refund) (app|application|software|program|tool|profile|certificate)"#,
        #"(configuration|mdm|management|device management|vpn|security) profile"#,
        #"(trust|allow) (this|the) (certificate|profile|developer)"#,
    ], negatable: true)

    /// "Install this app", "download the app from this link": only with a fix-it story or a link.
    static let installApp = PhraseMatcher([
        #"(install|download) (this|the attached|the following|this free|this new) (app|application|software|program|tool|profile|certificate|apk|helper|update)"#,
        #"(install|download|get) (the |this |an |a )?(app|application|software|program|tool|apk) (from|at|using|via|on|through) (this|the|my|our) (link|website|site|page)"#,
    ], negatable: true)

    /// "Download our trading app": a company's own "download our app" is everyday marketing, so
    /// this counts only with a deceptive link, or money talk next to a site that is not a big
    /// brand's own.
    static let installOurApp = PhraseMatcher([
        #"(install|download|get) (our|their) ([\w-]+ ){0,2}(app|application|software|program|platform)"#,
    ], negatable: true)

    /// "Download the app here: …": only with a deceptive link, or money talk next to a link
    /// anyone can publish to (a TestFlight beta, a file share).
    static let installAppHere = PhraseMatcher([
        #"(install|download|get) the ([\w-]+ )?(app|application) (here|at|from|via|using|through|with this|on this)"#,
    ], negatable: true)

    /// Investing and crypto words ("trading app", "deposit", "profits").
    static let moneyTalk = PhraseMatcher([
        #"(trading|trade|trades|invest|investing|investment|investments|crypto|cryptocurrency|bitcoin|btc|eth|ethereum|usdt|forex|deposit|deposits|profits?|returns|earnings|mining|stocks?|signals|arbitrage)"#,
    ])

    /// A direct installer or profile file ("app.apk", "setup.dmg", "profile.mobileconfig").
    static let installerFile = PhraseMatcher([#"(?<![\w-])[\w-]+\.(apk|ipa|dmg|pkg|exe|msi|mobileconfig|scr)"#])

    /// Screen sharing with a stranger.
    static let screenShare = PhraseMatcher([
        #"share (your|the|ur) (screen|desktop|display)"#,
        #"(turn on|enable|start|allow|accept|open) (the )?screen ?(sharing|share)"#,
        #"screen ?(sharing|share) (session|request|invite|invitation)"#,
    ], negatable: true)

    /// A stranger's story for screen sharing: a virus, a hacker, a technician, a refund, a bank.
    /// Not the generic "so I can see" or "fix it" a grandchild uses on FaceTime.
    static let screenShareStory = PhraseMatcher([
        #"(virus|viruses|malware|spyware|hack|hacker|hackers|hacked|infected|compromised|technician|tech support|technical support|support team|support agent|security team|refund|refunds|fraud|bank|banking|remote access)"#,
        #"(apple|microsoft|windows|amazon|google|geek squad|norton|mcafee|paypal|customer|it) (support|security|technician|agent|specialist)"#,
        #"(protect|secure|recover|unlock) (your|the) (account|money|funds|savings|computer|apple ?id|icloud)"#,
    ])

    /// A fix-your-device or protect-your-money story.
    static let fixItStory = PhraseMatcher([
        #"(virus|viruses|malware|spyware|hack|hacker|hackers|hacked|infected|compromised|technician|tech support|technical support|support team|support agent|security team|refund|refunds|fraud|bank|banking|account|protect|secure|security|remove|cleanup|clean up|fix (it|this|the problem|your)|so (i|we) can (help|assist|fix|check|see|access|connect|remove))"#,
    ])

    /// Remote-support portals where the caller has you enter a session code.
    static let portalDomains = [
        "fastsupport.com", "support.me", "join.me", "helpme.net", "123rescue.com", "rescue.logmein.com",
        "anydesk.com", "teamviewer.com", "get.teamviewer.com", "screenconnect.com", "remotedesktop.google.com",
        "getscreen.me", "islonline.com", "ultraviewer.net", "rustdesk.com", "quickassist.microsoft.com",
    ]

    func fires(in context: RuleContext) -> Bool {
        if Self.matcher.matches(in: context) { return true }
        let hasPortal = context.extraction.webLinks.contains { link in
            Self.portalDomains.contains { link.host == $0 || link.host.hasSuffix("." + $0) }
        }
        if hasPortal { return true }
        let links = context.extraction.webLinks
        // A link built to deceive, or a direct installer file.
        let strangeLink = links.contains { link in
            link.isIPAddress || BrandDomains.isShortener(host: link.host) || BrandDomains.hostLooksLikeLure(link.host)
        } || Self.installerFile.matches(in: context)
        // A link anyone can publish to (TestFlight, file shares), or one that is not a big brand's own.
        let sideloadLink = links.contains { BrandDomains.isUserContent(host: $0.host) }
        let otherLink = sideloadLink || links.contains { !BrandDomains.isKnownBrandHost($0.host) }
        let money = Self.moneyTalk.matches(in: context)
        if Self.installApp.matches(in: context), strangeLink || (otherLink && money) || Self.fixItStory.matches(in: context) { return true }
        if Self.installOurApp.matches(in: context), strangeLink || (otherLink && money) { return true }
        if Self.installAppHere.matches(in: context), strangeLink || (sideloadLink && money) { return true }
        return Self.screenShare.matches(in: context) && Self.screenShareStory.matches(in: context)
    }
}
