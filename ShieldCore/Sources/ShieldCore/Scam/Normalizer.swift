// Scam pipeline step 1 (SPEC §5.3): normalize the input before any rule looks at it.
//
//   - NFKC (folds full-width letters, ligatures, styled "math" letters to plain ones).
//   - Strip zero-width characters (U+200B–U+200F, U+2060, U+FEFF) and bidi controls
//     (U+202A–U+202E, U+2066–U+2069), plus every other character that renders as nothing:
//     Unicode format characters (soft hyphen, invisible operators, tag characters, interlinear
//     annotation marks, the Mongolian vowel separator) and default-ignorable code points
//     (combining grapheme joiner, variation selectors, Hangul fillers). Count them: hidden
//     characters inside a word, or a bidi override, are themselves a sign that someone is trying
//     to fool a checker.
//   - Fold typographic quotes and dashes to ASCII, collapse runs of spaces. An ideographic full
//     stop between two parts of a host ("paypal-secure\u{3002}com") becomes ".", since browsers
//     read it as one.
//   - Fold look-alike letters (Cyrillic, Greek, Armenian, Cherokee, Lisu, IPA and small-capital
//     Latin) inside Latin words, and build a second "leet" reading ("g1ft c4rds", "p@rcel",
//     "P a y P a l") that the phrase rules also check.
//   - Drop combining marks past the fourth on one letter ("Zalgo" text): no language stacks
//     more, and a pile of hundreds per letter is one "character" that would otherwise carry
//     millions of code points through the rules.
//   - Cap at 8,000 characters, counted as Unicode scalars (code points), so the work every rule
//     does is bounded however the characters are built.
//
// The input text is never logged or stored (§5.3 "Storage: none", §5.6).

import Foundation

/// The normalized form of one message. Lives in memory only for the life of the check.
public struct NormalizedText: Sendable, Hashable {
    /// NFKC, invisible characters removed, quotes/dashes folded, spaces collapsed, capped.
    public let text: String
    /// `text`, lowercased.
    public let lowercased: String
    /// `lowercased`, with look-alike letters inside mixed-script words folded to Latin ("pаypal"
    /// with a Cyrillic "а" becomes "paypal"). Rules match against this.
    public let folded: String
    /// `folded`, read a second way: digits and symbols used as letters inside words are folded
    /// ("g1ft c4rds" → "gift cards", "p@rcel" → "parcel"), letters spaced out one by one are
    /// joined ("p a y p a l" → "paypal"), and accents are dropped ("gíft cárds" → "gift cards";
    /// `folded` keeps them so "café" is never a spoofed word). Phrase rules check both strings.
    /// Equal to `folded` when nothing changed. Never shown, so a wrong fold can only add a match,
    /// never hide one.
    public let leetFolded: String
    /// How many zero-width and bidi control characters were removed.
    public let removedInvisibleCount: Int
    /// Removed invisible characters that sat between two ASCII letters or digits ("gi\u{200B}ft").
    /// Only ASCII neighbours count: Persian and Indic text use zero-width joiners inside real words.
    public let hiddenInWordCount: Int
    /// Bidi overrides (U+202D, U+202E) removed. Real messages almost never contain these; they are
    /// used to reverse how a link or file name is displayed. (Embeddings and isolates, which some
    /// apps add around names when copying, are stripped but not counted.)
    public let bidiOverrideCount: Int
    /// Spoofed words: Latin words with look-alike letters from another script mixed in ("Аpple"
    /// with a Cyrillic "А", "cօde" with an Armenian "օ"). A Cyrillic word with a stray Latin
    /// letter is not counted.
    public let mixedScriptWordCount: Int
    /// True when the input was longer than `Normalizer.maxCharacters` and was cut.
    public let wasTruncated: Bool
    /// Letters in `text`, and how many of them are Latin.
    public let letterCount: Int
    public let latinLetterCount: Int

    /// True when there is nothing to check.
    public var isEmpty: Bool { text.allSatisfy { $0.isWhitespace } }

    /// True when most letters are in a script the rules cannot read (the rules are English-only).
    /// A short message with very few letters is not "unreadable".
    public var isMostlyUnreadableScript: Bool {
        letterCount >= 20 && Double(latinLetterCount) / Double(letterCount) < 0.5
    }
}

public enum Normalizer {
    /// SPEC §5.3: cap at 8,000 characters. Counted in Unicode scalars, after NFKC and after
    /// invisible characters and extra combining marks are removed.
    public static let maxCharacters = 8_000

    /// Combining marks kept on one base letter. Vietnamese and Indic text stack two or three;
    /// more than this is decoration meant to bloat or hide the text.
    static let maxCombiningMarksPerLetter = 4

    /// Zero-width characters (§5.3): U+200B–U+200F, U+2060, U+FEFF.
    public static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B...0x200F, 0x2060, 0xFEFF: true
        default: false
        }
    }

    /// Bidi controls (§5.3): U+202A–U+202E, U+2066–U+2069.
    public static func isBidiControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069: true
        default: false
        }
    }

    /// Characters that render as nothing but are not on the §5.3 list: format characters (Cf,
    /// e.g. U+00AD soft hyphen, U+2061–U+2064 invisible operators, U+E0000–U+E007F tags,
    /// U+FFF9–U+FFFB annotation marks) and default-ignorable code points (U+034F, U+FE00–U+FE0F,
    /// U+115F/U+1160/U+3164 Hangul fillers, …). Arabic and Syriac number signs are format
    /// characters that do show, so they are kept.
    public static func isOtherIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0600...0x0605, 0x06DD, 0x070F, 0x0890, 0x0891, 0x08E2, 0x110BD, 0x110CD: return false
        default: break
        }
        let properties = scalar.properties
        return properties.isDefaultIgnorableCodePoint || properties.generalCategory == .format
    }

    /// Every character the normalizer strips.
    public static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        isZeroWidth(scalar) || isBidiControl(scalar) || isOtherIgnorable(scalar)
    }

    /// Full stops that browsers and IDNA read as "." in a host name (U+3002 ideographic, U+FF61
    /// halfwidth, U+FE12 vertical). NFKC leaves them alone.
    static func isHostFullStop(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x3002 || scalar.value == 0xFF61 || scalar.value == 0xFE12
    }

    /// Inputs longer than this many UTF-16 units are cut before NFKC, so a huge paste can't stall
    /// the screen. Generous: invisible characters removed later can't push real text past the cap.
    static let rawInputLimit = maxCharacters * 4

    /// The longest prefix of `text` that fits in `limit` UTF-16 units, cut between code points.
    /// (`String.prefix` counts characters, and one character can hold any number of code points.)
    static func prefix(_ text: String, utf16Units limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var units = 0
        let scalars = text.unicodeScalars
        var end = scalars.startIndex
        while end < scalars.endIndex {
            units += scalars[end].utf16.count
            if units > limit { break }
            end = scalars.index(after: end)
        }
        return String(scalars[..<end])
    }

    public static func normalize(_ input: String) -> NormalizedText {
        var raw = input
        var cutEarly = false
        if raw.utf16.count > rawInputLimit {
            raw = prefix(raw, utf16Units: rawInputLimit)
            cutEarly = true
        }

        // 1. NFKC. Trademark, service-mark and registered signs go first: NFKC turns "USPS™"
        // into "USPSTM", which hides the brand name from every rule.
        if raw.unicodeScalars.contains(where: { $0 == "\u{2122}" || $0 == "\u{2120}" || $0 == "\u{00AE}" }) {
            var kept = String.UnicodeScalarView()
            kept.append(contentsOf: raw.unicodeScalars.lazy.filter { $0 != "\u{2122}" && $0 != "\u{2120}" && $0 != "\u{00AE}" })
            raw = String(kept)
        }
        let nfkc = raw.precomposedStringWithCompatibilityMapping
        let scalars = Array(nfkc.unicodeScalars)

        // 2. Strip invisible characters, counting the suspicious ones.
        var kept = String.UnicodeScalarView()
        kept.reserveCapacity(scalars.count)
        var removed = 0
        var hiddenInWord = 0
        var bidiOverrides = 0
        var lastVisible: Unicode.Scalar?
        var pendingInvisible = 0
        var lastWasSpace = false
        var combiningRun = 0
        var keptScalars = 0
        var truncated = cutEarly

        for (position, scalar) in scalars.enumerated() {
            // 4. Cap (counted in scalars, so the rules' work is bounded).
            if keptScalars >= maxCharacters {
                // Only real text left out counts as a cut, not trailing spaces or hidden marks.
                if !isInvisible(scalar), !scalar.properties.isWhitespace {
                    truncated = true
                    break
                }
                continue
            }
            if isInvisible(scalar) {
                removed += 1
                if scalar.value == 0x202D || scalar.value == 0x202E { bidiOverrides += 1 }
                pendingInvisible += 1
                continue
            }
            // An invisible run is "in a word" when it sits between two letters or digits.
            if pendingInvisible > 0 {
                if let previous = lastVisible, isASCIIWordScalar(previous), isASCIIWordScalar(scalar) {
                    hiddenInWord += pendingInvisible
                }
                pendingInvisible = 0
            }
            lastVisible = scalar

            // Extra combining marks (Zalgo): dropped, like invisible characters.
            if scalar.properties.generalCategory == .nonspacingMark || scalar.properties.generalCategory == .enclosingMark {
                combiningRun += 1
                if combiningRun > maxCombiningMarksPerLetter { continue }
            } else {
                combiningRun = 0
            }

            // 3. Fold quotes, dashes and odd spaces; collapse space runs (newlines are kept,
            //    since rules treat a line break as the end of a clause).
            var folded = foldPunctuation(scalar)
            if isHostFullStop(scalar), let previous = kept.last, isHostScalar(previous),
               let next = scalars[(position + 1)...].first(where: { !isInvisible($0) }), next.isASCII,
               next.properties.isAlphabetic
            {
                // "paypal-secure。com": a working link in Safari. In CJK prose the stop is followed
                // by CJK text, not an ASCII letter, and is kept.
                folded = "."
            }
            if folded == "\r" { continue }
            if folded == " " {
                if lastWasSpace { continue }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
            kept.append(folded)
            keptScalars += 1
        }

        let text = String(kept)

        let lower = text.lowercased()
        let (folded, mixedWords) = foldMixedScriptWords(lower)
        let leet = leetFold(folded).folding(options: [.diacriticInsensitive], locale: nil)

        var letters = 0
        var latin = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if script(of: scalar) == .latin { latin += 1 }
        }

        return NormalizedText(
            text: text,
            lowercased: lower,
            folded: folded,
            leetFolded: leet,
            removedInvisibleCount: removed,
            hiddenInWordCount: hiddenInWord,
            bidiOverrideCount: bidiOverrides,
            mixedScriptWordCount: mixedWords,
            wasTruncated: truncated,
            letterCount: letters,
            latinLetterCount: latin
        )
    }

    // MARK: - Helpers

    static func isASCIIWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || scalar.properties.numericType != nil)
    }

    static func isHostScalar(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIWordScalar(scalar) || scalar == "-"
    }

    private static func foldPunctuation(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x02BC: "'"
        case 0x201C, 0x201D, 0x201E, 0x201F, 0x2033: "\""
        case 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212: "-"
        case 0x0009, 0x00A0, 0x2000...0x200A, 0x202F, 0x205F, 0x3000: " "
        case 0x2028, 0x2029, 0x0085: "\n"
        default: scalar
        }
    }

    enum Script { case latin, cyrillic, greek, armenian, cherokee, lisu, other }

    static func script(of scalar: Unicode.Scalar) -> Script {
        switch scalar.value {
        // Basic Latin, Latin-1, Extended-A/B, IPA, phonetic extensions, Extended Additional/C/D/E.
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x2AF, 0x1D00...0x1DBF, 0x1E00...0x1EFF, 0x2C60...0x2C7F,
             0xA720...0xA7FF, 0xAB30...0xAB6F:
            .latin
        case 0x400...0x52F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: .cyrillic
        case 0x370...0x3FF, 0x1F00...0x1FFF: .greek
        case 0x530...0x58F, 0xFB13...0xFB17: .armenian
        case 0x13A0...0x13FF, 0xAB70...0xABBF: .cherokee
        case 0xA4D0...0xA4FF: .lisu
        default: .other
        }
    }

    /// Letters from other scripts (and odd Latin forms) that look like plain Latin letters
    /// (lowercase forms, since folding runs after lowercasing), after Unicode's confusables list.
    static let confusables: [Unicode.Scalar: Unicode.Scalar] = {
        var map: [Unicode.Scalar: Unicode.Scalar] = [
            // Cyrillic
            "а": "a", "в": "b", "е": "e", "ё": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
            "і": "i", "ї": "i", "ј": "j", "ѕ": "s", "ԁ": "d", "ӏ": "l", "һ": "h", "ԛ": "q", "ԝ": "w",
            "к": "k", "м": "m", "т": "t", "н": "h",
            // Greek
            "α": "a", "β": "b", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p", "τ": "t",
            "υ": "u", "χ": "x", "ω": "w",
            // Armenian
            "օ": "o", "ս": "u", "ո": "n", "հ": "h", "ց": "g", "զ": "q", "ա": "w", "ի": "h", "ւ": "l",
            // IPA and small-capital Latin (no language writes these inside ordinary words)
            "ɡ": "g", "ɑ": "a", "ɩ": "i", "ɪ": "i", "ʏ": "y", "ʀ": "r", "ʙ": "b", "ʜ": "h", "ʟ": "l", "ɴ": "n",
            "ɢ": "g", "ᴀ": "a", "ᴄ": "c", "ᴅ": "d", "ᴇ": "e", "ᴊ": "j", "ᴋ": "k", "ᴍ": "m", "ᴏ": "o",
            "ᴘ": "p", "ᴛ": "t", "ᴜ": "u", "ᴠ": "v", "ᴡ": "w", "ᴢ": "z", "ꜰ": "f", "ꜱ": "s",
            // Lisu (no case)
            "ꓮ": "a", "ꓐ": "b", "ꓚ": "c", "ꓓ": "d", "ꓰ": "e", "ꓝ": "f", "ꓖ": "g", "ꓧ": "h", "ꓲ": "i",
            "ꓙ": "j", "ꓗ": "k", "ꓡ": "l", "ꓟ": "m", "ꓠ": "n", "ꓳ": "o", "ꓑ": "p", "ꓣ": "r", "ꓢ": "s",
            "ꓔ": "t", "ꓴ": "u", "ꓦ": "v", "ꓪ": "w", "ꓫ": "x", "ꓬ": "y", "ꓜ": "z",
        ]
        // Cherokee capitals look like Latin capitals. Lowercasing maps U+13A0–U+13EF to the small
        // letters at U+AB70–U+ABBF, so both forms are listed.
        let cherokee: [(UInt32, Unicode.Scalar)] = [
            (0x13A0, "d"), (0x13A1, "r"), (0x13A2, "t"), (0x13A5, "i"), (0x13A9, "y"), (0x13AA, "a"),
            (0x13AB, "j"), (0x13AC, "e"), (0x13B3, "w"), (0x13B7, "m"), (0x13BB, "h"), (0x13BD, "y"),
            (0x13C0, "g"), (0x13C2, "h"), (0x13C3, "z"), (0x13CF, "b"), (0x13D2, "r"), (0x13D9, "v"),
            (0x13DA, "s"), (0x13DE, "l"), (0x13DF, "c"), (0x13E2, "p"), (0x13E6, "k"), (0x13F4, "b"),
        ]
        for (value, latin) in cherokee {
            if let upper = Unicode.Scalar(value) { map[upper] = latin }
            if let lower = Unicode.Scalar(value - 0x13A0 + 0xAB70) { map[lower] = latin }
        }
        return map
    }()

    /// Folds a single scalar if it is a known look-alike; otherwise returns it unchanged.
    static func foldConfusable(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        confusables[scalar] ?? scalar
    }

    /// Folds look-alike letters only inside spoofed words: words with at least one plain ASCII
    /// letter and at least one look-alike, where every other letter is Latin. Words written in
    /// another script (a real Russian, Greek or Armenian message, even with a stray Latin letter)
    /// are kept, and so are Latin words with real accents ("café", Turkish "kapı").
    private static func foldMixedScriptWords(_ lower: String) -> (String, Int) {
        var output = String.UnicodeScalarView()
        var word: [Unicode.Scalar] = []
        var mixedCount = 0

        func flush() {
            guard !word.isEmpty else { return }
            let hasPlainLetter = word.contains { $0.isASCII && $0.properties.isAlphabetic }
            let hasLookalike = word.contains { !$0.isASCII && confusables[$0] != nil }
            let spoofed = hasPlainLetter && hasLookalike && word.allSatisfy { scalar in
                confusables[scalar] != nil || script(of: scalar) == .latin || !scalar.properties.isAlphabetic
            }
            if spoofed {
                mixedCount += 1
                for scalar in word { output.append(foldConfusable(scalar)) }
            } else {
                output.append(contentsOf: word)
            }
            word.removeAll(keepingCapacity: true)
        }

        for scalar in lower.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                word.append(scalar)
            } else {
                flush()
                output.append(scalar)
            }
        }
        flush()
        return (String(output), mixedCount)
    }

    // MARK: - Leet reading

    /// Digits and symbols scammers put in place of letters to dodge carrier filters.
    private static let leetMap: [Unicode.Scalar: Unicode.Scalar] = [
        "0": "o", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s",
    ]

    private static func isLeetSymbol(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "1" || leetMap[scalar] != nil
    }

    /// The second reading of `folded` (see `NormalizedText.leetFolded`).
    static func leetFold(_ folded: String) -> String {
        let scalars = Array(folded.unicodeScalars)
        var output = String.UnicodeScalarView()
        var token: [Unicode.Scalar] = []

        func isTokenScalar(_ s: Unicode.Scalar) -> Bool {
            s.isASCII && (s.properties.isAlphabetic || s.properties.numericType != nil || s == "@" || s == "$")
        }

        func flushToken() {
            defer { token.removeAll(keepingCapacity: true) }
            let letters = token.filter { $0.properties.isAlphabetic }.count
            let symbols = token.filter(isLeetSymbol).count
            // A word with letters and a few stand-ins ("c0de", "addre$$"), not a number, a code or
            // a price ("$45", "1z999aa1", "10am" stays readable either way).
            let word = String(String.UnicodeScalarView(token))
            guard letters >= 2, symbols >= 1, letters >= symbols, !isOrdinaryAlphanumeric(word) else {
                output.append(contentsOf: token)
                return
            }
            for index in token.indices {
                let scalar = token[index]
                if scalar == "1" {
                    // "g1ft" → "gift", "de1ivered" → "delivered", "emai1" → "email", "bi11" → "bill".
                    let next = index + 1 < token.count ? token[index + 1] : nil
                    let previous = index > 0 ? token[index - 1] : nil
                    if next == nil || next == "1" || previous == "1" || next.map({ "aeiouy".unicodeScalars.contains($0) }) == true {
                        output.append("l")
                    } else {
                        output.append("i")
                    }
                } else {
                    output.append(leetMap[scalar] ?? scalar)
                }
            }
        }

        for scalar in scalars {
            if isTokenScalar(scalar) {
                token.append(scalar)
            } else {
                flushToken()
                output.append(scalar)
            }
        }
        flushToken()
        return joinSpacedLetters(String(output))
    }

    // swiftlint:disable:next force_try
    private static let ordinaryAlphanumeric = try! NSRegularExpression(
        pattern: #"^(\d+(am|pm|st|nd|rd|th|k|s|x|g|gb|mb|tb|hr|hrs|h|min|mins|m|mo|yr|yrs|ft|lb|lbs|oz|mph|kg|km|cm|mm|in|ish)|[a-z]+\d{2,})$"#
    )

    /// "10am", "3rd", "5k", "covid19", "iphone15": numbers with units and model names, not leet.
    static func isOrdinaryAlphanumeric(_ word: String) -> Bool {
        ordinaryAlphanumeric.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)) != nil
    }

    /// Joins four or more single letters spaced out one by one ("p a y p a l" → "paypal").
    static func joinSpacedLetters(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        guard words.count >= 4 else { return text }
        var out: [String] = []
        var run: [String] = []
        func isSingleLetter(_ word: Substring) -> Bool {
            word.unicodeScalars.count == 1 && word.unicodeScalars.first.map { $0.isASCII && $0.properties.isAlphabetic } == true
        }
        func flush() {
            if run.count >= 4 { out.append(run.joined()) } else { out.append(contentsOf: run) }
            run.removeAll()
        }
        for word in words {
            // A trailing ":" or "," still ends the run on a letter ("P a y P a l:").
            if isSingleLetter(word) {
                run.append(String(word))
            } else if let last = word.last, [":", ",", ".", "!", "?"].contains(last), isSingleLetter(word.dropLast()) {
                run.append(String(word))
                flush()
            } else {
                flush()
                out.append(String(word))
            }
        }
        flush()
        return out.joined(separator: " ")
    }
}
