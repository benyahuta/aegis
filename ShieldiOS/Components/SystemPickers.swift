// UIKit bridges the shared screens need on iPhone:
// - "Choose Ben from my contacts": `CNContactPickerViewController`, which needs NO Contacts
//   permission (SPEC §3, §4: no NSContactsUsageDescription). Only the picked phone number comes
//   back; it is saved in the Keychain by the AppModel and never synced.
// - "Send invite": `UICloudSharingController` for a person zone's CKShare (§8.4).

import CloudKit
import ContactsUI
import ShieldCore
import UIKit

@MainActor
enum Presenter {
    /// The top-most view controller of the key window, to present system pickers from.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

@MainActor
final class ContactPhonePicker: NSObject, CNContactPickerDelegate {
    private var continuation: CheckedContinuation<String?, Never>?
    private static var current: ContactPhonePicker?

    /// Presents the picker limited to phone numbers. Returns the number, or nil on cancel.
    static func pick() async -> String? {
        guard let presenter = Presenter.topViewController() else { return nil }
        let picker = ContactPhonePicker()
        current = picker
        defer { current = nil }
        return await withCheckedContinuation { continuation in
            picker.continuation = continuation
            let controller = CNContactPickerViewController()
            controller.delegate = picker
            controller.displayedPropertyKeys = [CNContactPhoneNumbersKey]
            controller.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
            // Tapping a contact with one number picks it; otherwise the person taps a number.
            controller.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
            controller.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
            presenter.present(controller, animated: true)
        }
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let number = contact.phoneNumbers.first?.value.stringValue
        MainActor.assumeIsolated { finish(number) }
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        let number = (contactProperty.value as? CNPhoneNumber)?.stringValue
        MainActor.assumeIsolated { finish(number) }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        MainActor.assumeIsolated { finish(nil) }
    }

    private func finish(_ number: String?) {
        continuation?.resume(returning: number)
        continuation = nil
    }
}

@MainActor
enum CloudSharingPresenter {
    /// Shows the system sharing sheet for a new person's zone-wide share (read-write, private).
    static func present(_ invite: PersonInvite, container: any CloudContainer) -> Bool {
        guard let live = container as? LiveCloudContainer, let presenter = Presenter.topViewController() else { return false }
        let controller = UICloudSharingController(share: invite.share, container: live.container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        presenter.present(controller, animated: true)
        return true
    }
}
