// paste_terminal (weight 5, SPEC §5.3): "Open Terminal", "paste this command", "press
// Command-Space then…" (ClickFix). Also the 2026 Script Editor variant (applescript:// links),
// the Windows "Win+R" version, the Finder path ("Applications > Utilities > Terminal") and other
// terminal apps (iTerm, Warp).
//
// An instruction, not a story: "I'll open Terminal and check the logs" is someone describing what
// they will do themselves.

import Foundation

struct PasteTerminalRule: ScamRule {
    let id = RuleID.pasteTerminal

    static let console = #"(terminal|iterm2?|warp terminal|script editor|command prompt|powershell|run (box|dialog|window)|cmd\.exe|the run command)"#
    static let firstPerson = #"(\bi|\bi'll|\bill|\bi will|\bwe|\bwe'll|\bwe will|\bi'm going to|\bim going to|\bi can|\bwe can|\bi'd|\bi need to|\bi have to|\bi just|\blet me|\bi usually|\bi always|\bi then|\bi'll just) "#
    /// `verbs`, not after a first-person subject ("I'll open Terminal", "we can open the
    /// terminal"). The look-behind sits after the verb so it only runs where a verb matched.
    static func notFirstPerson(_ verbs: String) -> String { verbs + "(?<!" + firstPerson + verbs + ")" }

    static let matcher = PhraseMatcher([
        notFirstPerson(#"(open|launch|search for|type)"#) + #" (the |your |a )?(app called )?"# + console,
        notFirstPerson(#"(open|launch|go to|click|find)"#) + #" [^.!?\n]{0,30}(utilities|applications) ?(>|→|›|/|-|then) ?(utilities ?(>|→|›|/|-|then) ?)?(terminal|script editor)"#,
        #"(paste|type|copy|run|enter|execute|insert) ([\w-]+ ){0,5}(command|commands|script|code|line|text)[^.!?\n]{0,50}"# + console,
        #"(paste|type|run|execute|enter) (this|the following|the|that|these) (command|commands|script|line of code|code snippet)"#,
        #"(paste|copy|run|type)[^.!?\n]{0,40}(into|in) (the |a )?"# + console,
        #"(command|cmd|⌘) ?(\+|-|and)? ?(space|spacebar)"#,
        #"(press|hold|hit) (the )?(command|cmd|⌘) (key )?(\+|and|-)? ?(space|spacebar|v|r)"#,
        #"(windows|win|⊞) ?(key)? ?(\+|and|-) ?r"#,
        #"(press|hit|use) (ctrl|control|cmd|command|⌘) ?(\+|-) ?v[^.!?\n]{0,40}(enter|return)"#,
        "applescript://", "osascript", #"terminal\.app"#, "mshta", #"powershell -"#,
        #"curl [^\n]{0,120}\| ?(ba|z)?sh"#, #"base64 (-d|--decode|-D)"#, #"/bin/(ba|z)?sh"#, #"chmod \+x"#,
        #"xattr -[cdrw]"#, #"echo [a-z0-9+/=]{20,} ?\|"#,
    ], negatable: true)

    func fires(in context: RuleContext) -> Bool {
        Self.matcher.matches(in: context)
    }
}
