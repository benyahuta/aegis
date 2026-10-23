# Verified: money, shopping, government and credit items (SPEC §6.3, §6.4)

Verified 2026-10-22 with read-only web research (official help pages and live URL checks). The data is also in `accounts-money-gov.json`. Status is one of **correct**, **corrected** or **could-not-verify**. Carrier menus change often, so keep the label "Menu names may differ a little."

## Summary of corrections

1. **FTC URL**: the indexed article is `https://consumer.ftc.gov/articles/credit-freezes-and-fraud-alerts`. The spec's slug (`what-know-about-...`) is not the indexed URL.
2. **The spec's claim that the FTC page "lists the official bureau links" is wrong.** For adult freezes, the page points to IdentityTheft.gov's bureau contacts and to general bureau help pages. Each `credit_freeze_*` item should open its own bureau's free-freeze page:
   - Equifax: `https://www.equifax.com/personal/credit-report-services/credit-freeze/`
   - Experian: `https://www.experian.com/help/credit-freeze/`
   - TransUnion: `https://www.transunion.com/credit-freeze`
3. **PayPal**: the canonical URL is `https://www.paypal.com/myaccount/security/`. The spec URL redirects there through sign-in. PayPal says to set up 2-step verification in a web browser, not in the app.
4. **Cash App**: the path is Profile → **Security** → **Security Lock**. "Privacy & Security" is the older label.
5. **Venmo**: "Me → Settings → Security" is not confirmed as an in-app path. Confirmed paths are Me → Settings → Face ID & Passcode in the app, and venmo.com → Settings → Security on the web.
6. **Verizon**: the tab is **Me**, not Account. The path is Me → Edit profile and settings → Security → Number Lock / SIM Protection.
7. **AT&T**: the app is now called "AT&T", not myAT&T. The path is Account icon → Wireless account lock, not Profile.
8. **T-Mobile**: SIM Protection is at Manage (or Account) → gear → Security → SIM Protection. Port Out Protection is a free **add-on**, at Manage → See plans → Manage add-ons, and has to be added per line.
9. **New carriers** (spec only says "Ask Ben"): Visible **Line Lock**, Mint **Number Lock** and Cricket **Account Lock** paths are confirmed. UScellular is now T-Mobile, so use the T-Mobile steps once the account has moved to T-Life.
10. **SSA**: sign-in has been Login.gov or ID.me only since 2025-06-07. Add that to the copy.
11. **IRS**: the URL is correct. Add "You get a new one every year."
12. **link-check.sh**: plain curl gets 404 or 403 from several official sites that work fine in a browser (FTC, SSA, TransUnion, PayPal, T-Mobile, Mint). The tool needs a browser User-Agent and a hand-verified allowlist, or the build will fail on links that are fine.

## Money

| Item | Spec | Verified | Source | Status |
|---|---|---|---|---|
| `paypal` URL | `https://www.paypal.com/myaccount/settings/security` | `https://www.paypal.com/myaccount/security/` (the spec URL redirects there via sign-in) | [PayPal help 167](https://www.paypal.com/us/cshelp/article/what-is-2-step-verification-help167) | corrected |
| `paypal` steps | generic | Settings (gear) → Security → 2-step verification → Set Up → authenticator app or "Text me a code". Use a web browser, not the app. | same | correct |
| `venmo` | in the app: Me → Settings → Security | App: Me → Settings (gear) → Face ID & Passcode (under Preferences). Web: venmo.com → Settings → Security (remembered devices, sessions). Venmo already sends sign-in codes on every account. No in-app "Security" label confirmed. | [Venmo Login Security](https://help.venmo.com/cs/articles/login-security-vhel151) | could-not-verify |
| `zelle` | "Zelle lives inside your bank's app. Use the bank steps." | Correct. The standalone app stopped payments 2025-04-01 and logins 2025-08-11. | [zelle.com](https://www.zelle.com/), 2025 news | correct |
| `cash_app` | in the app: Profile → Privacy & Security | Profile → **Security** → **Security Lock** (applies to opening the app, payments, or both; 4-digit code). Older label: Privacy & Security. Web: cash.app/account → Account → Security. | [Cash App 3120](https://cash.app/help/3120-enable-security-lock) | corrected |
| `brokerage` | bank copy + "Add a trusted contact" | Correct (FINRA Rule 4512). A trusted contact cannot trade or move money. The firm may call them only if it suspects exploitation or can't reach you. | [FINRA trusted contact](https://www.finra.org/investors/insights/trusted-contact) | correct |

## Shopping

| Item | Spec | Verified | Source | Status |
|---|---|---|---|---|
| `amazon` | `https://www.amazon.com/a/settings/approval` | Resolves (goes through sign-in). Your Account → Login & security → Two-Step Verification (2SV) Settings → Turn on. Needs a backup phone or authenticator app. | [Amazon 2SV help](https://www.amazon.com/gp/help/customer/display.html?nodeId=TMmdiAyib3Uq4SCdLm) | correct |

## Carrier locks (`carrier_lock`)

| Carrier | Spec | Verified | Source | Status |
|---|---|---|---|---|
| Verizon | My Verizon → Account → Security → Number Lock, SIM Protection | My Verizon app → **Me** → Edit profile and settings → Security → **Number Lock** / **SIM Protection** (toggle each number → Confirm). Owner or Manager only. Reps can't turn SIM Protection off. | [Verizon KB 309293](https://www.verizon.com/support/knowledge-base-309293/) | corrected |
| AT&T | myAT&T → Profile → Wireless Account Lock | **AT&T app** → Home → **Account** icon → **Wireless account lock** → Swipe to lock. Prepaid: Profile & Settings → Account Info & Preferences → Wireless Account Lock → Turn on. | [AT&T iOS app article](https://www.att.com/device-support/article/155671/at&t/app-myatt-ios-smartphone/) | corrected |
| T-Mobile | T-Life → Profile → Privacy & Security → SIM Protection, Port-out Protection | **SIM Protection** (Postpaid): T-Life → Manage (or Account) → gear → Security → SIM Protection → Save Changes. **Port Out Protection** (free add-on; Postpaid, Prepaid, Metro): Manage → See plans → Manage add-ons → line → check Port Out Protection → Agree & Submit, once per line. | [T-Mobile SIM Protection](https://www.t-mobile.com/support/plans-features/sim-protection/) | corrected |
| UScellular | (Ask Ben) | Now T-Mobile (deal closed 2025-08-01). Migrated accounts use T-Life, so follow the T-Mobile steps. No lock path confirmed for accounts that haven't moved yet: keep "Ask Ben". | [UScellular joining T-Mobile](https://m.uscc.com/joining-t-mobile) | could-not-verify |
| Visible | (Ask Ben) | Visible app/site → Dashboard → Device details → **Line Lock & portout-PIN** → Lock. Unlocking takes about 30 min. | [Visible Line Lock](https://www.visible.com/m/help/your-account/line-lock) | corrected |
| Mint | (Ask Ben) | Mint app → Account → Security → **Number Lock** → on. Web: my.mintmobile.com → My Account → My Profile & Security. | [Mint Number Lock](https://www.mintmobile.com/help/what-is-number-lock/) | corrected |
| Cricket | (Ask Ben) | myCricket app → Settings → Security → **Account Lock** → on. Blocks SIM swaps and port-outs on every line. | [Cricket Account Lock](https://www.cricketwireless.com/support/fraud-protection/account-lock) | corrected |

## Government

| Item | Spec | Verified | Source | Status |
|---|---|---|---|---|
| `ssa` | `https://www.ssa.gov/myaccount/` "Create your own account before a criminal does." | URL is correct. Since 2025-06-07 you can only sign in with **Login.gov or ID.me**. SSA says to choose Login.gov if unsure. You need an email, a phone and a photo ID. Suggested line: "You'll sign in with Login.gov or ID.me. Ben can sit with you for this." | [SSA creating an account](https://www.ssa.gov/myaccount/creating-an-account.html) | correct |
| `irs_ip_pin` | `https://www.irs.gov/identity-theft-fraud-scams/get-an-identity-protection-pin` | Resolves (200; `irs.gov/ippin` redirects here). Get it in the IRS Online Account → Profile → IP PIN. Anyone can opt in, and a new PIN comes every calendar year. The IRS "will never ask for your IP PIN." Add: "You get a new one every year." | [IRS IP PIN](https://www.irs.gov/identity-theft-fraud-scams/get-an-identity-protection-pin) | correct |

## Credit freezes (`credit_freeze_*`)

| Item | Spec | Verified | Source | Status |
|---|---|---|---|---|
| FTC URL | `.../articles/what-know-about-credit-freezes-and-fraud-alerts` | `https://consumer.ftc.gov/articles/credit-freezes-and-fraud-alerts` | [FTC](https://consumer.ftc.gov/articles/credit-freezes-and-fraud-alerts) | corrected |
| FTC claim | FTC page lists official bureau links | It doesn't for adult freezes. It links to [IdentityTheft.gov bureau contacts](https://www.identitytheft.gov/#/CreditBureauContacts) instead. Link each bureau directly. | same | corrected |
| Equifax | FTC page | `https://www.equifax.com/personal/credit-report-services/credit-freeze/`: free "Security Freeze" through a myEquifax account; (888) 298-0045. The paid product to avoid is Lock & Alert. | Equifax page | corrected |
| Experian | FTC page | `https://www.experian.com/help/credit-freeze/` (the old `/freeze/center.html` redirects here): "Freeze your credit file for free"; 1-888-397-3742. The paid product to avoid is CreditLock. | Experian page | corrected |
| TransUnion | FTC page | `https://www.transunion.com/credit-freeze`: free freeze through the TransUnion Service Center; 800-916-8800 (from the search index). | TransUnion page | corrected |
| Copy | "Choose the free freeze, not a paid lock." | Correct. A freeze has to be placed at each bureau separately. It's free, doesn't hurt your credit score, and lasts until you lift it. | FTC | correct |
