# aegis

An iPhone and Mac app I made so my family can keep their stuff secure without me sitting next to them.

- **Is this a scam?** Paste a text or pick a screenshot and it checks for the usual signs. Runs on the device, nothing gets sent anywhere.
- **Am I up to date?** Tells you if your iPhone or Mac is missing security fixes. On the Mac it also checks FileVault, Gatekeeper, the firewall, remote access and a few other things.
- **Checklist** for what an app can't check itself: Stolen Device Protection, recovery contacts, credit freezes, and two-step sign-in on your email, bank and social accounts.

It never asks for a password and never changes a setting.

## Building

Xcode 26, iOS 18+, macOS 14+. No dependencies.

Make `Config/Identity.local.xcconfig` with your own values:

```
FS_ID_PREFIX = com.yourname.aegis
DEVELOPMENT_TEAM = ABCDE12345
```

Then open `FamilyShield.xcodeproj`. Tests: `cd ShieldCore && swift test`.

The app says "Call Ben" in a few places. That's me. Change it in `Localizable.xcstrings`.

MIT
