// "Who to call" (SPEC §10.1 screen 3): the phone number the person picked for Ben in Contacts.
// Saved on this device only, in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
// not synchronizable). It is never synced, logged or sent anywhere (§12.2 "the contact chosen
// for Ben"). It is not a secret (H2): it's kept in the Keychain because the spec says so.
// On the Mac it lives in the data-protection keychain, like DeviceIdentity: the legacy login
// keychain ignores ThisDeviceOnly, is included in Time Machine/Migration Assistant, and can show a
// "wants to use your confidential information" prompt after a re-sign.
//
// Only digits and a leading "+" are kept, so the value can only ever become a `tel:` URL.

import Foundation
import os
import Security

public protocol CallBenNumberStore: Sendable {
    /// The saved number, or nil.
    func load() -> String?
    /// Saves `number` (cleaned). Returns false when nothing could be saved.
    @discardableResult func save(_ number: String) -> Bool
    func clear()
}

public enum CallBenNumber {
    /// The number to dial: a leading "+" and the ASCII digits of the part before any dialing pause
    /// or extension. nil when that part has fewer than 3 or more than 15 digits, or holds letters
    /// (a vanity number like 1-800-FLOWERS can't be turned into digits safely).
    ///
    /// Contacts keeps a number as typed, for example "(555) 123-4567,890", "555-123-4567;12" or
    /// "555-123-4567 ext. 12". Joining every digit would dial a different number, so a pause
    /// ("," or ";"), "#", "*" after the number, or an extension word ("x", "ext", "extension")
    /// ends the number.
    public static func clean(_ raw: String) -> String? {
        let main = dialablePart(of: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !main.contains(where: \.isLetter) else { return nil }
        let digits = main.filter { $0.isASCII && $0.isNumber }
        guard (3...15).contains(digits.count) else { return nil }
        return (main.hasPrefix("+") ? "+" : "") + digits
    }

    /// `number` up to the first pause, "#"/"*" after a digit, or extension marker.
    static func dialablePart(of number: String) -> Substring {
        var sawDigit = false
        var index = number.startIndex
        while index < number.endIndex {
            let character = number[index]
            if character == "," || character == ";" { return number[..<index] }
            if (character == "#" || character == "*"), sawDigit { return number[..<index] }
            if character.isLetter, sawDigit, isExtensionMarker(number[index...]) { return number[..<index] }
            if character.isASCII, character.isNumber { sawDigit = true }
            index = number.index(after: index)
        }
        return number[...]
    }

    /// "x12", "x 12", "ext12", "ext. 12", "extension 12" (any case).
    private static func isExtensionMarker(_ rest: Substring) -> Bool {
        let lower = rest.lowercased()
        for marker in ["extension", "ext", "x"] where lower.hasPrefix(marker) {
            let after = lower.dropFirst(marker.count).drop { $0 == "." || $0 == ":" || $0.isWhitespace }
            if let first = after.first, first.isASCII, first.isNumber { return true }
        }
        return false
    }
}

/// The Keychain store used by the apps.
public final class KeychainCallBenStore: CallBenNumberStore {
    public static let service = AppIdentity.prefix + ".callben"
    public static let account = "ben"

    public init() {}

    /// The attributes that identify the item (shared by read, update, add and delete).
    static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// The attributes for a new item.
    static func addQuery(for number: String) -> [String: Any] {
        var query = baseQuery()
        query[kSecValueData as String] = Data(number.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }

    /// A number an earlier Mac build left in the login keychain is deliberately not read (that
    /// read could prompt); the person picks Ben again once.
    public func load() -> String? {
        var query = Self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                Log.app.error("callben.read.failed status=\(status, privacy: .public)")
            }
            return nil
        }
        return CallBenNumber.clean(text)
    }

    @discardableResult
    public func save(_ number: String) -> Bool {
        guard let clean = CallBenNumber.clean(number) else { return false }
        let update: [String: Any] = [kSecValueData as String: Data(clean.utf8)]
        var status = SecItemUpdate(Self.baseQuery() as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(Self.addQuery(for: clean) as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Log.app.error("callben.save.failed status=\(status, privacy: .public)")
            return false
        }
        return true
    }

    public func clear() {
        SecItemDelete(Self.baseQuery() as CFDictionary)
    }
}

/// In memory only (tests, previews, `-FSDemoState`).
public final class InMemoryCallBenStore: CallBenNumberStore {
    private let number: OSAllocatedUnfairLock<String?>

    public init(_ number: String? = nil) {
        self.number = OSAllocatedUnfairLock(initialState: number.flatMap(CallBenNumber.clean))
    }

    public func load() -> String? { number.withLock { $0 } }

    @discardableResult
    public func save(_ value: String) -> Bool {
        guard let clean = CallBenNumber.clean(value) else { return false }
        number.withLock { $0 = clean }
        return true
    }

    public func clear() { number.withLock { $0 = nil } }
}
