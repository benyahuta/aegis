# Mac fix steps and settings links: verification

Checked 2026-10-22 against Apple Support (macOS Tahoe 26 and macOS 27 Golden Gate guides) and, read-only, against the System Settings pane bundles on this Mac (macOS 26.5.1, 25F80). No URL was opened and no setting was changed. Machine-readable copy: `mac-steps.json`.

**Caveat:** macOS 27 pane IDs could not be tested on a 27 Mac. Apple's 27 guide uses the same pane names and no source reports a change. Run `tools/deeplink-test.sh` on a macOS 27 Mac before release.

## Corrections

- **os_patched / written_path**: System Settings → General → Software Update
- **auto_updates / written_path**: System Settings → General → Software Update → click ⓘ next to Automatic Updates → turn on "Download new updates when available", "Install macOS updates" and "Install Security Responses and system files" → Done. Labels are the same in Tahoe 26 and macOS 27.
- **auto_updates / written_path_bsi**: Optional extra (Tahoe 26.1+ and 27): System Settings → Privacy & Security → scroll to Background Security Improvements → turn on Automatically Install. A URL exists: x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?SecurityImprovements (search anchor present) or x-apple.systempreferences:com.apple.SecurityImprovements-Settings.extension (pane present). Neither was opened in this pass.
- **filevault / written_path**: System Settings → Privacy & Security → scroll down to FileVault → Turn On
- **filevault / fail_copy**: Apple's option label is "Allow my iCloud account to unlock my disk" (or "Set up my iCloud account to reset my password" if not using iCloud). Suggested copy: "...Pick the option that says Allow my iCloud account to unlock my disk." Avoid "Create a recovery key and do not use my iCloud account."
- **screen_lock / written_path**: System Settings → Lock Screen → "Require password after screen saver begins or display is turned off" → Immediately. Apple's guide confirms the path and row label for 26 and 27 but does not list the menu choices, so the word 'Immediately' was not confirmed from Apple's docs.
- **find_my / written_path**: System Settings → [your name] → iCloud → See All → Find My Mac → Turn On → Allow. It then asks for an administrator's name and password. Location Services must be on: System Settings → Privacy & Security → Location Services. The copy should say an admin password is needed, and suggest calling Ben if the person is not an admin.
- **remote_access_off / written_path**: System Settings → General → Sharing → turn off Screen Sharing (port 5900), Remote Management (5900), Remote Login (22) and File Sharing (445/548). Name only the service whose port was open.
- **recovery_contact / written_path_mac**: System Settings → [your name] → Sign-In & Security → Recovery Contacts → Add Recovery Contact → pick Ben (or Choose Someone Else) → Continue. The menu item is "Recovery Contacts", not "Account Recovery". It shows only when two-factor authentication is on.
- **recovery_contact / written_path_ios_note**: Apple 102641 (current) for iPhone: Settings → [your name] → Sign-In & Security → Recovery Contacts → Add Recovery Contact. Passed on for the iOS verifier.

## All items

### _all: url_macos27  (could-not-verify)

- Spec: All §6.2 x-apple.systempreferences URLs 'verified on macOS 26.5.1 [V]'
- Verified: Every pane ID below exists on 26.5.1 with allowsXAppleSystemPreferencesURLScheme = true. No Apple or third-party source documents a pane-ID change in macOS 27, and Apple's macOS 27 guide uses the same pane names. macOS 27: could not verify locally (this Mac runs 26.5.1); no public list for 27 contradicts it. Re-run tools/deeplink-test.sh on a macOS 27 Mac.
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80) ; https://github.com/jaywcjlove/SystemSettings-URLs-macOS ; https://github.com/bvanpeski/SystemPreferences

### os_patched: fix_url  (correct)

- Spec: x-apple.systempreferences:com.apple.Software-Update-Settings.extension
- Verified: x-apple.systempreferences:com.apple.Software-Update-Settings.extension (search group 'SoftwareUpdate'; legacy alias com.apple.preferences.softwareupdate)
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### os_patched: written_path  (corrected)

- Spec: (not given for Mac; legend only says a manual path is shown)
- Verified: System Settings → General → Software Update
- Source: https://support.apple.com/guide/mac-help/mchlpx1065/26/mac/26 ; https://support.apple.com/guide/mac-help/mchlpx1065/mac (27)

### os_update_stuck: fix_url  (correct)

- Spec: Software Update link
- Verified: x-apple.systempreferences:com.apple.Software-Update-Settings.extension; path System Settings → General → Software Update
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80) ; https://support.apple.com/guide/mac-help/mchlpx1065/26/mac/26 ; https://support.apple.com/guide/mac-help/mchlpx1065/mac (27)

### beta_catalog: written_path  (correct)

- Spec: Software Update link (§14.1: General → Software Update → turn off Beta Updates)
- Verified: System Settings → General → Software Update → click ⓘ next to Beta Updates → Off. The Beta Updates row shows only when the Mac is enrolled in a beta program.
- Source: https://support.apple.com/guide/mac-help/mchla7037245/mac

### auto_updates: written_path  (corrected)

- Spec: Software Update link → "Automatic Updates"
- Verified: System Settings → General → Software Update → click ⓘ next to Automatic Updates → turn on "Download new updates when available", "Install macOS updates" and "Install Security Responses and system files" → Done. Labels are the same in Tahoe 26 and macOS 27.
- Source: https://support.apple.com/guide/mac-help/mchlpx1065/26/mac/26 ; https://support.apple.com/guide/mac-help/mchlpx1065/mac (27)

### auto_updates: written_path_bsi  (corrected)

- Spec: (not in spec)
- Verified: Optional extra (Tahoe 26.1+ and 27): System Settings → Privacy & Security → scroll to Background Security Improvements → turn on Automatically Install. A URL exists: x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?SecurityImprovements (search anchor present) or x-apple.systempreferences:com.apple.SecurityImprovements-Settings.extension (pane present). Neither was opened in this pass.
- Source: https://support.apple.com/guide/mac-help/mchl44c4c70c/mac ; local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### filevault: fix_url  (correct)

- Spec: ...PrivacySecurity.extension?FileVault
- Verified: x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault (write it out in full; 'FileVault' anchor present; legacy alias com.apple.preference.security?FileVault)
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### filevault: written_path  (corrected)

- Spec: (not given)
- Verified: System Settings → Privacy & Security → scroll down to FileVault → Turn On
- Source: https://support.apple.com/guide/mac-help/mh11785/26.0/mac/26.0 ; https://support.apple.com/guide/mac-help/mh11785/mac (27)

### filevault: fail_copy  (corrected)

- Spec: "...Pick the option to unlock with your Apple Account."
- Verified: Apple's option label is "Allow my iCloud account to unlock my disk" (or "Set up my iCloud account to reset my password" if not using iCloud). Suggested copy: "...Pick the option that says Allow my iCloud account to unlock my disk." Avoid "Create a recovery key and do not use my iCloud account."
- Source: https://support.apple.com/guide/mac-help/mh11785/26.0/mac/26.0 ; https://support.apple.com/guide/mac-help/mh11785/mac

### gatekeeper: fix_url  (correct)

- Spec: ...PrivacySecurity.extension?Security
- Verified: x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security ('Security' anchor's search titles include 'Gatekeeper')
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### gatekeeper: written_path  (correct)

- Spec: (Call Ben)
- Verified: System Settings → Privacy & Security → Security → "Allow applications from" → App Store and Known Developers (Apple's wording; the on-screen menu shows "App Store & Known Developers"). If assessments were turned off from Terminal, the fix is Terminal-only, so keep "Please call Ben".
- Source: https://support.apple.com/guide/mac-help/mh40596/mac

### sip: fix_url  (correct)

- Spec: none (Call Ben)
- Verified: none. Turning SIP back on needs macOS Recovery, which is not a family task.
- Source: general Apple platform knowledge (no settings pane exists)

### xprotect_current: fix_url  (correct)

- Spec: Software Update link
- Verified: x-apple.systempreferences:com.apple.Software-Update-Settings.extension. XProtect comes in as a background update when "Install Security Responses and system files" is on.
- Source: https://support.apple.com/guide/mac-help/mchlpx1065/26/mac/26 ; https://support.apple.com/guide/mac-help/mchlpx1065/mac (27)

### screen_lock: fix_url  (correct)

- Spec: x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension
- Verified: x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension. An optional anchor ?Password ('Require password to wake computer') exists in the search terms but was not click-tested.
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### screen_lock: written_path  (corrected)

- Spec: (not given; fail copy: 'Set your Mac to ask for your password right after it sleeps.')
- Verified: System Settings → Lock Screen → "Require password after screen saver begins or display is turned off" → Immediately. Apple's guide confirms the path and row label for 26 and 27 but does not list the menu choices, so the word 'Immediately' was not confirmed from Apple's docs.
- Source: https://support.apple.com/guide/mac-help/mh11784/26/mac/26 ; https://support.apple.com/guide/mac-help/mh11784/mac

### find_my: fix_url  (correct)

- Spec: x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud
- Verified: x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud ('iCloud' anchor present; lands on iCloud per ux-older-adults.md §2.1)
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### find_my: written_path  (corrected)

- Spec: (not given in spec; family-playbook: System Settings > [name] > iCloud > Find My Mac [U: path])
- Verified: System Settings → [your name] → iCloud → See All → Find My Mac → Turn On → Allow. It then asks for an administrator's name and password. Location Services must be on: System Settings → Privacy & Security → Location Services. The copy should say an admin password is needed, and suggest calling Ben if the person is not an admin.
- Source: https://support.apple.com/guide/mac-help/mh36811/26/mac/26 ; https://support.apple.com/guide/mac-help/mh36811/mac (27)

### firewall: fix_url  (correct)

- Spec: x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall (opens Network only; copy says 'then click Firewall')
- Verified: Same. The 'Firewall' anchor is in the search terms but, per the earlier click test, lands on Network only. Keep the copy: System Settings → Network → Firewall → turn it on.
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80) ; https://support.apple.com/guide/mac-help/mh34041/26/mac/26 ; https://support.apple.com/guide/mac-help/mh34041/mac

### remote_access_off: fix_url  (correct)

- Spec: x-apple.systempreferences:com.apple.Sharing-Settings.extension
- Verified: x-apple.systempreferences:com.apple.Sharing-Settings.extension. Optional anchors Services_RemoteLogin, Services_ScreenSharing, Services_PersonalFileSharing and Services_ARDService exist but were not click-tested.
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### remote_access_off: written_path  (corrected)

- Spec: (not given)
- Verified: System Settings → General → Sharing → turn off Screen Sharing (port 5900), Remote Management (5900), Remote Login (22) and File Sharing (445/548). Name only the service whose port was open.
- Source: https://support.apple.com/guide/mac-help/mh11848/mac ; https://support.apple.com/guide/mac-help/mchlp1066/mac

### mdm_unexpected: fix_url  (correct)

- Spec: x-apple.systempreferences:com.apple.Profiles-Settings.extension
- Verified: x-apple.systempreferences:com.apple.Profiles-Settings.extension; path System Settings → General → Device Management
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80) ; https://support.apple.com/guide/mac-help/mh35561/mac

### time_machine: fix_url  (correct)

- Spec: x-apple.systempreferences:com.apple.Time-Machine-Settings.extension
- Verified: x-apple.systempreferences:com.apple.Time-Machine-Settings.extension; path System Settings → General → Time Machine → Add Backup Disk
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80) ; https://support.apple.com/guide/mac-help/mh11421/mac

### lockdown: written_path  (correct)

- Spec: shown only as 'check yourself' link
- Verified: x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?LockdownMode; path System Settings → Privacy & Security → Lockdown Mode → Turn On
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80) ; https://support.apple.com/105120

### adp: written_path  (correct)

- Spec: shown only as 'check yourself' link
- Verified: System Settings → [your name] → iCloud → Advanced Data Protection → Turn On; link x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud
- Source: https://support.apple.com/108756

### recovery_contact: written_path_mac  (corrected)

- Spec: Settings → [your name] → Sign-In & Security → Account Recovery → Add Recovery Contact → Ben
- Verified: System Settings → [your name] → Sign-In & Security → Recovery Contacts → Add Recovery Contact → pick Ben (or Choose Someone Else) → Continue. The menu item is "Recovery Contacts", not "Account Recovery". It shows only when two-factor authentication is on.
- Source: https://support.apple.com/102641 ; https://support.apple.com/guide/mac-help/mchlc7ba8f3e/26/mac/26 ; https://support.apple.com/guide/mac-help/mchlc7ba8f3e/mac (27)

### recovery_contact: written_path_ios_note  (corrected)

- Spec: Settings → [your name] → Sign-In & Security → Account Recovery → Add Recovery Contact
- Verified: Apple 102641 (current) for iPhone: Settings → [your name] → Sign-In & Security → Recovery Contacts → Add Recovery Contact. Passed on for the iOS verifier.
- Source: https://support.apple.com/102641

### recovery_contact: fix_url_mac  (correct)

- Spec: AppleIDSettings
- Verified: x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings (lands on Apple Account; the person then clicks Sign-In & Security)
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80)

### login_item_approval: fix_url  (correct)

- Spec: §10.2: x-apple.systempreferences:com.apple.LoginItems-Settings.extension
- Verified: x-apple.systempreferences:com.apple.LoginItems-Settings.extension; path System Settings → General → Login Items & Extensions (Family Shield appears under 'Open at Login' / 'App Background Activity')
- Source: local read-only: /System/Library/ExtensionKit/Extensions/*.appex Info.plist + en.lproj/*.searchTerms on macOS 26.5.1 (25F80) ; https://support.apple.com/guide/mac-help/mtusr003/mac
