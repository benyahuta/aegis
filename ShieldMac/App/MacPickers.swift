// AppKit bridges the shared screens need on the Mac:
// - "Choose Ben from my contacts": `CNContactPicker` (SPEC §3: ContactsUI on Mac). Only the picked
//   phone number comes back; the AppModel saves it in the Keychain and never syncs it. Shown only
//   when the person clicks the button.
// - "Send invite" (Ben): `NSSharingServicePicker` with an `NSItemProvider` registered for the
//   person zone's CKShare (§8.4 "Ben: create a person"), read-write and private.

import AppKit
import CloudKit
import Contacts
import ContactsUI
import ShieldCore

@MainActor
enum MacAnchor {
    /// The view to show pickers from: the key window's content (the Family Shield window).
    static func view() -> NSView? {
        (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey })?.contentView
    }

    /// A small rect near the top middle of `view`, so the picker's arrow points into the window.
    static func rect(in view: NSView) -> NSRect {
        let bounds = view.bounds
        let y = view.isFlipped ? bounds.minY + 120 : bounds.maxY - 120
        return NSRect(x: bounds.midX - 1, y: y, width: 2, height: 2)
    }
}

@MainActor
final class MacContactPicker: NSObject, CNContactPickerDelegate {
    private var continuation: CheckedContinuation<String?, Never>?
    private let picker = CNContactPicker()
    private static var current: MacContactPicker?

    /// Shows the picker limited to phone numbers. Returns the number, or nil when closed.
    static func pick() async -> String? {
        guard let anchor = MacAnchor.view() else { return nil }
        let session = MacContactPicker()
        current = session
        defer { current = nil }
        return await withCheckedContinuation { continuation in
            session.continuation = continuation
            session.picker.displayedKeys = [CNContactPhoneNumbersKey]
            session.picker.delegate = session
            session.picker.showRelative(to: MacAnchor.rect(in: anchor), of: anchor, preferredEdge: .maxY)
        }
    }

    nonisolated func contactPicker(_ picker: CNContactPicker, didSelect contactProperty: CNContactProperty) {
        let number = (contactProperty.value as? CNPhoneNumber)?.stringValue
        MainActor.assumeIsolated {
            finish(number)
            self.picker.close()
        }
    }

    nonisolated func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
        let number = contact.isKeyAvailable(CNContactPhoneNumbersKey) ? contact.phoneNumbers.first?.value.stringValue : nil
        MainActor.assumeIsolated {
            finish(number)
            self.picker.close()
        }
    }

    nonisolated func contactPickerDidClose(_ picker: CNContactPicker) {
        MainActor.assumeIsolated { finish(nil) }
    }

    /// Resumes once; later calls (close after select) do nothing.
    private func finish(_ number: String?) {
        continuation?.resume(returning: number)
        continuation = nil
    }
}

@MainActor
enum MacSharePresenter {
    /// Shows the system share picker (Messages, Mail, …) for a new person's zone-wide share.
    static func present(_ invite: PersonInvite, container: any CloudContainer) -> Bool {
        guard let live = container as? LiveCloudContainer, let anchor = MacAnchor.view() else { return false }
        let provider = NSItemProvider()
        let options = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite,
                                              allowedParticipantAccessOptions: .specifiedRecipientsOnly)
        provider.registerCKShare(invite.share, container: live.container, allowedSharingOptions: options)
        let picker = NSSharingServicePicker(items: [provider])
        picker.show(relativeTo: MacAnchor.rect(in: anchor), of: anchor, preferredEdge: .maxY)
        return true
    }
}
