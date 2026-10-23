# Verified: online accounts, email and social (SPEC §6.4)

Checked 2026-10-22 against official help centres and by fetching each URL (unauthenticated, read-only). Status key: **correct** = spec is right; **corrected** = change needed; **could-not-verify** = official source not reachable without signing in (JS-rendered help or account-only page), so text is best available and should be re-checked by a human.

## Corrections to make in `Services.swift` / §6.4

1. **yahoo** URL → `https://login.yahoo.com/myaccount/security` (old path is a redirect).
2. **aol** URL → `https://login.aol.com/myaccount/security`.
3. **facebook**: `/privacy/checkup` is *Privacy* Checkup. Use Accounts Center → Password and security → Security Checkup; URL `https://accountscenter.facebook.com/password_and_security`.
4. **instagram**: add '→ Security Checkup' and the full path Profile → ☰ → Accounts Center → Password and security.
5. **whatsapp**: two-step verification is now a **password**, not a six-digit PIN (Aug 2026). Add Settings → Account → **Passkeys**. Skip checkup/third_party/alerts.
6. **tiktok**: menu is **Security & permissions**, not 'Security'.
7. **snapchat**: path is Settings → **My Account** → Two-Factor Authentication.
8. **alerts step**: only Facebook, Instagram (toggle) and TikTok (review list) have a user-facing sign-in alerts control. Gmail has a review page (always on). iCloud, Outlook, Yahoo, AOL, X, LinkedIn, Snapchat, WhatsApp send alerts automatically: skip the step or make it informational.
9. **checkup step**: only Google, Facebook, Instagram and TikTok have a real 'security checkup'. Outlook/Yahoo/AOL/X/LinkedIn get the security settings page with copy 'Open the company's security page'. iCloud/Snapchat/WhatsApp have none.

## Steps that apply

| Service | 2fa | unique_pw | recovery_info | sessions | third_party | alerts | checkup |
|---|---|---|---|---|---|---|---|
| gmail | yes | yes | yes | yes | yes | yes (review only) | yes |
| icloud_mail | yes | yes | yes | yes | yes | skip | skip |
| outlook | yes | yes | yes | yes | yes | skip | yes |
| yahoo | yes | yes | yes | yes | yes | skip | yes |
| aol | yes | yes | yes | yes | yes | skip | yes |
| facebook | yes | yes | yes | yes | yes | yes | yes |
| instagram | yes | yes | yes | yes | yes | yes | yes |
| whatsapp | yes | yes | yes | yes | skip | skip | skip |
| x | yes | yes | yes | yes | yes | skip | yes |
| tiktok | yes | yes | yes | yes | yes | yes | yes |
| linkedin | yes | yes | yes | yes | yes | skip | yes |
| snapchat | yes | yes | yes | yes | yes | skip | skip |

TikTok alerts = review Security alerts list, not a toggle.

## gmail

- **checkup_url** — status: **correct**
  - Spec: https://myaccount.google.com/security-checkup
  - Verified: https://myaccount.google.com/security-checkup (official; g.co/securitycheckup redirects to the same page; signed-out visitors see /intro/security-checkup)
  - Source: https://myaccount.google.com/security-checkup
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Google Account → Security → "How you sign in to Google" → 2-Step Verification (https://myaccount.google.com/signinoptions/twosv) and Passkeys and security keys. On iPhone: Gmail app → profile picture → Manage your Google Account → Security.
  - Source: https://support.google.com/accounts/answer/185839
- **recovery_info** — status: **correct**
  - Spec: (not in spec)
  - Verified: Google Account → Security → "How you sign in to Google" → Recovery phone / Recovery email
  - Source: https://support.google.com/accounts/answer/183723
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Google Account → Security → Your devices → Manage all devices (https://myaccount.google.com/device-activity)
  - Source: https://myaccount.google.com/device-activity
- **third_party** — status: **correct**
  - Spec: (not in spec)
  - Verified: Google Account → Security → Your connections to third-party apps & services (https://myaccount.google.com/connections)
  - Source: https://support.google.com/accounts/answer/13533235
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Security alerts are always on and cannot be turned off; review them at Google Account → Security → Recent security activity (https://myaccount.google.com/notifications). Copy should say "check" not "turn on".
  - Source: https://myaccount.google.com/notifications
- **steps** — status: **correct**
  - Spec: (not in spec)
  - Verified: All 7 apply (alerts step = review, not toggle).
  - Source: https://myaccount.google.com/security

## icloud_mail

- **checkup_url** — status: **correct**
  - Spec: Settings → [your name] → Sign-In & Security (no URL; covered by Apple steps)
  - Verified: Settings → [your name] → Sign-In & Security (iOS 26). Apple has no web security checkup; web equivalent is https://account.apple.com → Sign-In and Security. Safety Check is separate (Settings → Privacy & Security → Safety Check).
  - Source: https://support.apple.com/guide/iphone/use-two-factor-authentication-iphd709a3c46/ios
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → [your name] → Sign-In & Security → Two-Factor Authentication (on by default for nearly all accounts). Optional: Security Keys in the same screen.
  - Source: https://support.apple.com/en-us/102660
- **recovery_info** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → [your name] → Sign-In & Security → Two-Factor Authentication → trusted phone numbers (add a second number not tied to this iPhone); Account Recovery / Recovery Contact in the same Sign-In & Security screen.
  - Source: https://support.apple.com/en-us/122621
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → [your name] → scroll to the device list → tap an unknown device → Remove from Account.
  - Source: https://support.apple.com/guide/iphone/use-two-factor-authentication-iphd709a3c46/ios
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Settings → [your name] → Sign-In & Security → Sign in with Apple (apps using your Apple Account); app-specific passwords are managed at account.apple.com → Sign-In and Security → App-Specific Passwords.
  - Source: https://account.apple.com
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: No toggle: Apple always sends sign-in approval prompts to trusted devices and email notices. Skip alerts step (or make it informational).
  - Source: https://support.apple.com/en-us/102660
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Apply: 2fa, unique_pw, recovery_info, sessions, third_party. Skip: alerts (automatic), checkup (no Apple checkup page; point to Safety Check instead).
  - Source: https://support.apple.com/en-us/102660

## outlook

- **checkup_url** — status: **correct**
  - Spec: https://account.microsoft.com/security
  - Verified: https://account.microsoft.com/security (official Microsoft account Security dashboard; redirects to sign-in). Microsoft does not call it a 'checkup'; copy should say "Microsoft's security page".
  - Source: https://support.microsoft.com/en-us/accounts-billing/security/how-to-use-two-step-verification-with-your-microsoft-account
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: account.microsoft.com/security → Manage how I sign in → Additional security → Two-step verification → Turn on. Passkeys are added from the same 'Manage how I sign in' page (Microsoft accounts are now passkey-first for new accounts).
  - Source: https://support.microsoft.com/en-us/accounts-billing/security/how-to-use-two-step-verification-with-your-microsoft-account
- **recovery_info** — status: **correct**
  - Spec: (not in spec)
  - Verified: account.microsoft.com/security → Manage how I sign in → 'Ways to prove who you are' (phone/email). Also generate a recovery code here.
  - Source: https://support.microsoft.com/en-us/accounts-billing/manage/microsoft-account-security-info-verification-codes
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Review: Security dashboard → Sign-in activity (https://account.live.com/activity). Sign out: Manage how I sign in → 'Sign out everywhere' (takes up to 24 h; not per-device).
  - Source: https://support.microsoft.com/en-us/accounts-billing/manage/how-to-sign-out-of-your-microsoft-account-everywhere
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: 'Apps and services that can access your data' at https://account.live.com/consent/Manage (linked from the Privacy/Security dashboards).
  - Source: https://account.live.com/consent/Manage
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: No user toggle; Microsoft automatically emails/texts on unusual sign-in. Make alerts step informational or skip.
  - Source: https://support.microsoft.com/en-us/account-billing/what-is-the-recent-activity-page-23cf5556-4dbe-70da-82c8-bb3a8d8f8016
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Apply: 2fa, unique_pw, recovery_info, sessions (sign out everywhere), third_party, checkup. Skip/informational: alerts.
  - Source: https://account.microsoft.com/security

## yahoo

- **checkup_url** — status: **corrected**
  - Spec: https://login.yahoo.com/account/security
  - Verified: https://login.yahoo.com/myaccount/security (the spec URL still works but redirects here; hard-code the canonical one). Yahoo has no 'checkup' wizard; this is the Account Security page.
  - Source: https://help.yahoo.com/kb/SLN2080.html
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Account Security → 'Ways of signing in' → 2-Step Verification (phone, authenticator app, security key); Passkeys section on the same page. In Yahoo Mail iOS app: profile → Manage accounts → Account info → Security settings.
  - Source: https://help.yahoo.com/kb/SLN5013.html
- **recovery_info** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: https://login.yahoo.com/myaccount/personalinfo → recovery phone and email (Account Info).
  - Source: https://help.yahoo.com/kb/SLN2080.html
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: https://login.yahoo.com/myaccount/recentactivity (Recent activity → sign out of sessions you don't recognize).
  - Source: https://help.yahoo.com/kb/SLN2080.html
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Account Security → app passwords (delete unknown) and https://login.yahoo.com/myaccount/permissions (connected apps).
  - Source: https://help.yahoo.com/kb/SLN2080.html
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: No toggle; Yahoo automatically notifies on security changes. Informational only.
  - Source: https://help.yahoo.com/kb/SLN37259.html
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Apply: 2fa, unique_pw, recovery_info, sessions, third_party, checkup (security page). Skip: alerts.
  - Source: https://help.yahoo.com/kb/SLN2080.html

## aol

- **checkup_url** — status: **corrected**
  - Spec: https://login.aol.com/account/security
  - Verified: https://login.aol.com/myaccount/security (spec URL redirects here; use canonical).
  - Source: https://help.aol.com/articles/secure-your-aol-account
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Account Security page → 2-Step Verification (phone, authenticator app, security key).
  - Source: https://help.aol.com/articles/2-step-verification-stronger-than-your-password-alone
- **recovery_info** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Account Info → recovery phone/email (https://login.aol.com/myaccount/personalinfo).
  - Source: https://help.aol.com/articles/secure-your-aol-account
- **sessions** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: https://login.aol.com/myaccount/recentactivity (Recent activity).
  - Source: https://help.aol.com/articles/secure-your-aol-account
- **third_party** — status: **correct**
  - Spec: (not in spec)
  - Verified: Account Security → app passwords; remove ones you don't use.
  - Source: https://help.aol.com/articles/allow-apps-that-use-less-secure-sign-in
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: No toggle; AOL automatically emails primary and backup addresses on security changes. Informational.
  - Source: https://help.aol.com/articles/understanding-security-changes-on-your-aol-account
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Same as Yahoo: skip alerts toggle.
  - Source: https://help.aol.com/articles/secure-your-aol-account

## facebook

- **checkup_url** — status: **corrected**
  - Spec: https://www.facebook.com/privacy/checkup
  - Verified: This is Privacy Checkup (official, resolves) - not Security Checkup. Security Checkup now lives in Accounts Center: Menu → Settings & privacy → Settings → Accounts Center → Password and security → Security Checkup. Recommended hard-coded URL: https://accountscenter.facebook.com/password_and_security (resolves). Facebook Help links Security Checkup at https://www.facebook.com/privacy/review?review_id=573933453011661 (could not confirm with an unauthenticated fetch).
  - Source: https://www.facebook.com/help/799880743466869
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Accounts Center → Password and security → Two-factor authentication (also Passkey, rolled out 2025).
  - Source: https://about.fb.com/news/2025/06/introducing-passkeys-facebook-easier-sign-in/
- **recovery_info** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Accounts Center → Personal details → Contact info.
  - Source: https://www.facebook.com/help/213481848684090
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Accounts Center → Password and security → Where you're logged in → Select devices to log out. (Some accounts show 'Meta Account settings' instead of Accounts Center.)
  - Source: https://www.facebook.com/help/211990645501187
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Settings & privacy → Settings → Apps and websites (under 'Your activity'/'Permissions').
  - Source: https://www.facebook.com/help/213481848684090
- **alerts** — status: **correct**
  - Spec: (not in spec)
  - Verified: Accounts Center → Password and security → Login alerts.
  - Source: https://www.facebook.com/help/213481848684090
- **steps** — status: **correct**
  - Spec: (not in spec)
  - Verified: All 7 apply.
  - Source: https://www.facebook.com/help/213481848684090

## instagram

- **checkup_url** — status: **corrected**
  - Spec: in the app: Accounts Center → Password and security
  - Verified: Correct, but full path is Profile → ☰ → Accounts Center → Password and security → Security Checkup. Web: https://accountscenter.instagram.com/password_and_security/ (resolves).
  - Source: https://help.instagram.com/iphone-app/566810106808145
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Profile → ☰ → Accounts Center → Password and security → Two-factor authentication → pick account → authentication app (recommended), SMS, or security key.
  - Source: https://help.instagram.com/iphone-app/566810106808145
- **recovery_info** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Accounts Center → Personal details → Contact info.
  - Source: https://help.instagram.com/1028697851146674/
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Accounts Center → Password and security → Where you're logged in.
  - Source: https://help.instagram.com/2761108904184084
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Profile → ☰ → Website permissions → Apps and websites (also check Accounts Center → Accounts for linked accounts you don't recognize).
  - Source: https://about.instagram.com/blog/announcements/keeping-instagram-safe-and-secure
- **alerts** — status: **correct**
  - Spec: (not in spec)
  - Verified: Accounts Center → Password and security → Login alerts.
  - Source: https://about.instagram.com/blog/announcements/staying-safe-and-secure-on-instagram
- **steps** — status: **correct**
  - Spec: (not in spec)
  - Verified: All 7 apply.
  - Source: https://help.instagram.com/iphone-app/566810106808145

## whatsapp

- **checkup_url** — status: **corrected**
  - Spec: in the app: Settings → Account → Two-step verification
  - Verified: Path correct, but as of Aug 2026 the two-step verification PIN is now a full password (letters, numbers, symbols) - copy must not say 'six-digit PIN'. Also add passkey: Settings → Account → Passkeys (multiple passkeys allowed). WhatsApp has no security checkup; skip checkup.
  - Source: https://blog.whatsapp.com/one-billion-people-are-now-protected-with-passkeys-on-whatsapp-plus-more-account-security-features
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → Account → Two-step verification → Turn on (create password, add recovery email). Plus Settings → Account → Passkeys → Create passkey.
  - Source: https://about.fb.com/news/2026/08/new-account-security-features-for-whatsapp/
- **recovery_info** — status: **correct**
  - Spec: (not in spec)
  - Verified: Recovery email inside Settings → Account → Two-step verification → Email address. Account is tied to the phone number, so keep the carrier PIN on (§6.3).
  - Source: https://faq.whatsapp.com/1278661612895630/
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → Linked Devices → tap device → Log Out.
  - Source: https://faq.whatsapp.com/834124628020911/?cms_platform=iphone
- **unique_pw** — status: **corrected**
  - Spec: (not in spec)
  - Verified: No account password at login; the two-step password should be unique and saved in the Passwords app. Step applies to the two-step password.
  - Source: https://blog.whatsapp.com/one-billion-people-are-now-protected-with-passkeys-on-whatsapp-plus-more-account-security-features
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Apply: 2fa, unique_pw (two-step password), recovery_info, sessions (Linked Devices). Skip: third_party, alerts, checkup.
  - Source: https://faq.whatsapp.com/1095301557782068/

## x

- **checkup_url** — status: **correct**
  - Spec: https://x.com/settings/security_and_account_access
  - Verified: https://x.com/settings/security_and_account_access (official; resolves to login). X has no checkup wizard; this is the Security and account access page.
  - Source: https://help.x.com/en/managing-your-account/two-factor-authentication
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings and privacy → Security and account access → Security → Two-factor authentication (authentication app or security key; SMS is X Premium only). Passkey: same Security screen → Additional password protection → Passkey.
  - Source: https://help.x.com/en/managing-your-account/how-to-use-passkey
- **recovery_info** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Settings and privacy → Your account → Account information → Phone / Email.
  - Source: https://help.x.com/en/managing-your-account/two-factor-authentication
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Security and account access → Apps and sessions → Sessions (https://x.com/settings/sessions).
  - Source: https://x.com/settings/sessions
- **third_party** — status: **correct**
  - Spec: (not in spec)
  - Verified: Security and account access → Apps and sessions → Connected apps (https://x.com/settings/connected_apps).
  - Source: https://x.com/settings/connected_apps
- **alerts** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: No login-alert toggle; X emails on new logins automatically. Informational.
  - Source: https://help.x.com/en/managing-your-account/two-factor-authentication
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Apply: 2fa, unique_pw, recovery_info, sessions, third_party, checkup (security page). Skip: alerts.
  - Source: https://help.x.com/en/managing-your-account/two-factor-authentication

## tiktok

- **checkup_url** — status: **corrected**
  - Spec: in the app: Profile → ☰ → Settings and privacy → Security
  - Verified: Profile → ☰ → Settings and privacy → Security & permissions → Security checkup ('Security' label is now 'Security & permissions').
  - Source: https://support.tiktok.com/en/safety-hc/account-and-user-safety/account-safety
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings and privacy → Security & permissions → 2-step verification → choose at least two methods (phone, email, authenticator app). Passkey option appears in the same menu where available.
  - Source: https://support.tiktok.com/en/safety-hc/account-and-user-safety/account-safety
- **recovery_info** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Settings and privacy → Account → Account information → Phone / Email.
  - Source: https://www.tiktok.com/support/faq_detail?id=7543897457344928262
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings and privacy → Security & permissions → Manage devices.
  - Source: https://support.tiktok.com/en/safety-hc/account-and-user-safety/account-safety
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Settings and privacy → Security & permissions → Security alerts (review, not a toggle).
  - Source: https://support.tiktok.com/en/safety-hc/account-and-user-safety/avoid-fraudulent-message-attacks-on-tiktok
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Settings and privacy → Security & permissions → Apps and services permissions.
  - Source: https://support.tiktok.com/en/account-and-privacy
- **steps** — status: **correct**
  - Spec: (not in spec)
  - Verified: All 7 apply (alerts = review Security alerts).
  - Source: https://support.tiktok.com/en/safety-hc/account-and-user-safety/account-safety

## linkedin

- **checkup_url** — status: **correct**
  - Spec: https://www.linkedin.com/mypreferences/d/categories/sign-in-and-security
  - Verified: https://www.linkedin.com/mypreferences/d/categories/sign-in-and-security (official; it is LinkedIn's canonical redirect target). No checkup wizard; this is the Sign in & security page.
  - Source: https://www.linkedin.com/help/linkedin/answer/a1381088/turn-two-step-verification-on-and-off
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Profile photo → Settings → Sign in & security → Two-step verification (authenticator app preferred, or SMS). Passkeys: Sign in & security → Passkeys.
  - Source: https://www.linkedin.com/help/linkedin/answer/a5946277
- **recovery_info** — status: **correct**
  - Spec: (not in spec)
  - Verified: Sign in & security → Email addresses / Phone numbers.
  - Source: https://www.linkedin.com/help/linkedin/answer/a1381088/turn-two-step-verification-on-and-off
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Sign in & security → Where you're signed in (https://www.linkedin.com/mypreferences/d/sessions) → Sign out.
  - Source: https://www.linkedin.com/mypreferences/d/sessions
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Settings → Data privacy → Permitted services (https://www.linkedin.com/mypreferences/d/permitted-services).
  - Source: https://www.linkedin.com/mypreferences/d/permitted-services
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: No login-alert toggle; LinkedIn emails on new sign-ins and sends in-app sign-in prompts when 2-step is on. Informational.
  - Source: https://www.linkedin.com/help/linkedin/answer/a1427042
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Apply: 2fa, unique_pw, recovery_info, sessions, third_party, checkup. Skip: alerts.
  - Source: https://www.linkedin.com/help/linkedin/answer/a1381088

## snapchat

- **checkup_url** — status: **corrected**
  - Spec: in the app: Settings → Two-Factor Authentication
  - Verified: Profile → ⚙️ Settings → My Account → Two-Factor Authentication (the 'My Account' level was missing). No checkup wizard; web account page https://accounts.snapchat.com resolves.
  - Source: https://help.snapchat.com/hc/en-us/articles/7012304106644
- **2fa** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → My Account → Two-Factor Authentication → Continue → SMS or authenticator app; Snapchat also recommends a passkey. Snapchat requires both a phone and email on file first.
  - Source: https://help.snapchat.com/hc/en-us/articles/7012304746644
- **recovery_info** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → My Account → Mobile Number / Email; save a Recovery Code under Two-Factor Authentication.
  - Source: https://help.snapchat.com/hc/en-us/articles/7012304746644
- **sessions** — status: **correct**
  - Spec: (not in spec)
  - Verified: Settings → My Account → Session Management → X next to unknown sessions (web: accounts.snapchat.com → Session Management). Also Two-Factor Authentication → Forget Devices.
  - Source: https://help.snapchat.com/hc/en-us/articles/23515601788948
- **third_party** — status: **could-not-verify**
  - Spec: (not in spec)
  - Verified: Settings → Privacy Controls → Connected Apps.
  - Source: https://values.snap.com/privacy/privacy-through-security
- **alerts** — status: **corrected**
  - Spec: (not in spec)
  - Verified: No toggle; Snapchat sends sign-in alerts automatically. Informational.
  - Source: https://help.snapchat.com/hc/en-us/articles/45269894320404
- **steps** — status: **corrected**
  - Spec: (not in spec)
  - Verified: Apply: 2fa, unique_pw, recovery_info, sessions, third_party. Skip: alerts (automatic), checkup (none).
  - Source: https://help.snapchat.com/hc/en-us/articles/7012304746644
