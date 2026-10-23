#!/bin/zsh
# SPEC §12.4: every https page the family can be sent to is a compiled constant in
# ShieldCore/Sources/ShieldCore/Catalog/DeepLinks.swift, Services.swift or catalog.json.
# This checks that each one still answers: `curl -sI` (a HEAD request) per URL, and a report of
# every URL whose answer is not 2xx/3xx. Redirects are followed to the end. A site that refuses
# HEAD is retried once with a plain GET (body discarded).
#
# Every non-2xx/3xx answer is printed, in one of three classes:
#   FAIL     the page is gone: the site answers curl, but not for this path, or it answers 200
#            with a "Page Not Found" title (a soft 404, which support.apple.com does) (exit 1).
#   BLOCKED  the site refuses curl altogether (its home page fails the same way). Bot protection,
#            not a dead link; open it in a browser to confirm (warning only).
#   SIGNIN   401, or a redirect to the site's own sign-in page: expected for an account-settings
#            page the person signs in to themselves (H2; warning only).
#   VERIFIED a URL on the hand-verified list below: it refuses or misanswers curl but was opened
#            in a real browser and reached the right page (or its sign-in with the path kept)
#            (docs/verified/AUDITED.md §1 #10; warning only, so it stays visible).
# --strict makes BLOCKED, SIGNIN and VERIFIED fail too.
#
# Read-only: no cookies, no form data, nothing sent but the request line and a User-Agent.
# Safe for agents and CI (curl only, H4). Needs the network.
# usage: tools/link-check.sh [-v] [--strict]     (-v also prints the URLs that passed)
setopt extended_glob
ROOT="${0:A:h}/.."
CATALOG="$ROOT/ShieldCore/Sources/ShieldCore/Catalog"
FILES=("$CATALOG/DeepLinks.swift" "$CATALOG/Services.swift" "$CATALOG/catalog.json")
UA="FamilyShield-link-check/1"
VERBOSE=0
STRICT=0
for arg in "$@"; do
  case "$arg" in
    -v) VERBOSE=1 ;;
    --strict) STRICT=1 ;;
    *) echo "usage: tools/link-check.sh [-v] [--strict]"; exit 2 ;;
  esac
done

for f in $FILES; do
  [[ -r "$f" ]] || { echo "missing: $f"; exit 2; }
done

urls=("${(@f)$(grep -ohE 'https://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+' $FILES | sort -u)}")
(( ${#urls} > 0 )) || { echo "no https URLs found"; exit 2; }

good() { [[ "$1" == 2* || "$1" == 3* ]] }
# "<code> <final url>" after following redirects; HEAD first, GET if HEAD is refused.
probe() {
  local out code
  out="$(curl -sIL -o /dev/null -A "$UA" --max-time 30 --max-redirs 10 -w '%{http_code} %{url_effective}' "$1" 2>/dev/null)"
  code="${out%% *}"
  if ! good "$code"; then
    out="$(curl -sL -o /dev/null -A "$UA" --max-time 30 --max-redirs 10 -w '%{http_code} %{url_effective}' "$1" 2>/dev/null)"
  fi
  echo "$out"
}
first_code() { curl -sI -o /dev/null -A "$UA" --max-time 20 -w '%{http_code}' "$1" 2>/dev/null }
# The page's <title> (first 256 KB), for soft-404 detection.
page_title() {
  curl -sL -A "$UA" --max-time 30 --max-redirs 10 -r 0-262143 "$1" 2>/dev/null \
    | LC_ALL=C tr '\n' ' ' | LC_ALL=C grep -oiE '<title[^>]*>[^<]*' | head -1 | sed -E 's/<title[^>]*>//I; s/^ +//; s/ +$//'
}

# Hand-verified in a browser on 2026-10-23 (docs/verified/AUDITED.md). Re-check by eye when a
# URL changes; add a URL here only after opening it in a real browser.
VERIFIED_URLS=(
  "https://accountscenter.facebook.com/password_and_security"          # 400 to curl; login with next= in a browser
  "https://consumer.ftc.gov/articles/credit-freezes-and-fraud-alerts"  # 404 to curl for all of consumer.ftc.gov
  "https://www.ssa.gov/myaccount/"                                     # 403 to curl
  "https://www.transunion.com/credit-freeze"                           # 403 to curl
  "https://www.paypal.com/myaccount/security/"                         # 302 to sign-in, then 403
)

failed=0
warned=0
for url in $urls; do
  first="$(first_code "$url")"
  read code final <<< "$(probe "$url")"
  if good "$code"; then
    title="$(page_title "$url")"
    if [[ "$title" == (#i)*(page not found|not found|404)* ]]; then
      echo "FAIL    $first->$code  $url  (soft 404: \"$title\")"
      failed=$(( failed + 1 ))
    else
      (( VERBOSE )) && echo "ok      $first->$code  $url  ${title:+\"$title\"}"
    fi
    continue
  fi
  if (( ${VERIFIED_URLS[(Ie)$url]} )); then
    echo "VERIFIED $first->$code  $url  (hand-verified in a browser; curl is refused)"
    warned=$(( warned + 1 ))
    continue
  fi
  host="${${url#https://}%%/*}"
  final_path="${final#https://*/}"
  if [[ "$first" == 401 || "$final_path" == (#i)*(signin|login|sign-in|log-in)* ]]; then
    echo "SIGNIN  $first->$code  $url  ($final)"
    warned=$(( warned + 1 ))
    continue
  fi
  read rcode _ <<< "$(probe "https://$host/")"
  if ! good "$rcode"; then
    echo "BLOCKED $first->$code  $url  (https://$host/ answers curl with $rcode too)"
    warned=$(( warned + 1 ))
    continue
  fi
  echo "FAIL    $first->$code  $url  ($final; https://$host/ answers $rcode)"
  failed=$(( failed + 1 ))
done

echo "checked ${#urls} URLs: $failed failed, $warned warnings (BLOCKED/SIGNIN/VERIFIED: check in a browser)"
(( failed == 0 )) || exit 1
(( STRICT && warned > 0 )) && exit 1
exit 0
