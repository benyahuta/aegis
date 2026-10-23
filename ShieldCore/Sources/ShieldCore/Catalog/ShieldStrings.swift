// ShieldStrings: lookup for every compiled string in `Strings/Localizable.xcstrings`
// (SPEC §6, §7, §11 "Localizable strings in .xcstrings"; H6: all family-visible text is compiled).
//
// Xcode compiles the String Catalog into `en.lproj/Localizable.strings(dict)` inside the
// package resource bundle. `swift build` on the command line copies the raw `.xcstrings`
// instead, so this type falls back to reading the catalog JSON directly. Both paths give the
// same English text, including plural variations.
//
// Step strings may contain `**bold**` Markdown (menu names). Use `attributed(_:)` to render it.

import Foundation

public enum ShieldStrings {
    /// The resource bundle that holds the strings and catalog.json.
    public static let bundle: Bundle = .module

    public static let table = "Localizable"

    private static let missingSentinel = "\u{1}missing\u{1}"

    /// The English text for `key`. Returns the key itself when it is missing (lint tests make
    /// sure that never happens for catalog keys).
    public static func text(_ key: String) -> String {
        if let compiled = compiledLookup(key) { return compiled }
        if let raw = RawStringCatalog.shared.entries[key] {
            return raw.single ?? raw.other ?? key
        }
        return key
    }

    /// True when `key` exists in the String Catalog.
    public static func contains(_ key: String) -> Bool {
        compiledLookup(key) != nil || RawStringCatalog.shared.entries[key] != nil
    }

    /// A plural string for `count` (keys with a `%lld` plural variation).
    public static func plural(_ key: String, count: Int) -> String {
        if let compiled = compiledLookup(key) {
            return String.localizedStringWithFormat(compiled, count)
        }
        guard let raw = RawStringCatalog.shared.entries[key] else { return key }
        let format = (count == 1 ? raw.one : raw.other) ?? raw.other ?? raw.single ?? key
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), count)
    }

    /// The text with `**bold**` Markdown parsed (inline only, whitespace kept).
    public static func attributed(_ key: String) -> AttributedString {
        let string = text(key)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
    }

    /// The text with Markdown markers removed (for notifications and VoiceOver labels).
    public static func plain(_ key: String) -> String {
        String(attributed(key).characters)
    }

    /// Every key in the String Catalog, when the raw catalog is readable (always under
    /// `swift test`; empty in an Xcode-built bundle where the catalog is compiled).
    public static var rawKeys: Set<String> {
        Set(RawStringCatalog.shared.entries.keys)
    }

    /// The raw English values, keyed like `rawKeys` (lint tests scan these).
    public static var rawValues: [String: [String]] {
        RawStringCatalog.shared.entries.mapValues { entry in
            [entry.single, entry.one, entry.other].compactMap { $0 }
        }
    }

    private static func compiledLookup(_ key: String) -> String? {
        let value = bundle.localizedString(forKey: key, value: missingSentinel, table: table)
        return value == missingSentinel ? nil : value
    }
}

/// A parsed `.xcstrings` file (English only, v1).
struct RawStringCatalog: Sendable {
    struct Entry: Sendable {
        var single: String?
        var one: String?
        var other: String?
    }

    let entries: [String: Entry]

    static let shared: RawStringCatalog = {
        guard let url = ShieldStrings.bundle.url(forResource: ShieldStrings.table, withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url)
        else { return RawStringCatalog(entries: [:]) }
        return RawStringCatalog(data: data) ?? RawStringCatalog(entries: [:])
    }()

    init(entries: [String: Entry]) {
        self.entries = entries
    }

    init?(data: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let language = file.sourceLanguage
        var entries: [String: Entry] = [:]
        for (key, item) in file.strings {
            guard let localization = item.localizations?[language] else { continue }
            var entry = Entry()
            entry.single = localization.stringUnit?.value
            entry.one = localization.variations?.plural?["one"]?.stringUnit?.value
            entry.other = localization.variations?.plural?["other"]?.stringUnit?.value
            if entry.single != nil || entry.other != nil || entry.one != nil {
                entries[key] = entry
            }
        }
        self.entries = entries
    }

    private struct File: Decodable {
        let sourceLanguage: String
        let strings: [String: Item]
    }

    private struct Item: Decodable {
        let localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        let stringUnit: StringUnit?
        let variations: Variations?
    }

    private struct Variations: Decodable {
        let plural: [String: PluralCase]?
    }

    private struct PluralCase: Decodable {
        let stringUnit: StringUnit?
    }

    private struct StringUnit: Decodable {
        let value: String
    }
}
