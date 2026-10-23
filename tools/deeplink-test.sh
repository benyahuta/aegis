#!/bin/zsh
# BEN-RUN ONLY. AGENTS MUST NOT RUN THIS SCRIPT (not even to "check" it): it opens System
# Settings on this Mac, one pane after another, and asks a person at the keyboard whether each
# one opened the right place.
#
# SPEC §6 deep-link legend / §12.4: a wrong `x-apple.systempreferences:` link fails silently (the
# Settings window just opens somewhere else), so after every macOS major Ben checks each
# `DeepLink` URL by eye. The URLs are read from ShieldCore/Sources/ShieldCore/Catalog/DeepLinks.swift,
# so this always tests exactly what the app ships. Nothing is changed: it only opens panes (H3).
# iOS has one link (`UIApplication.openSettingsURLString`), checked by tapping a card on a device.
#
# Guards: needs an interactive terminal, `--ben`, and FS_BEN_AT_MAC=1; refuses inside Claude Code.
# usage: FS_BEN_AT_MAC=1 tools/deeplink-test.sh --ben
ROOT="${0:A:h}/.."
SRC="$ROOT/ShieldCore/Sources/ShieldCore/Catalog/DeepLinks.swift"

refuse() { echo "deeplink-test: $1"; echo "This is Ben's manual check (it opens System Settings). Agents never run it."; exit 3; }
[[ "${1:-}" == "--ben" ]] || refuse "missing --ben"
[[ "${FS_BEN_AT_MAC:-}" == 1 ]] || refuse "FS_BEN_AT_MAC=1 is not set"
[[ -z "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]] || refuse "running inside Claude Code"
[[ -t 0 && -t 1 ]] || refuse "not an interactive terminal"
[[ "$(uname -s)" == Darwin ]] || refuse "macOS only"
[[ -r "$SRC" ]] || { echo "missing: $SRC"; exit 2; }

prefix="x-apple.systempreferences:"
# Lines like:  case .macSoftwareUpdate: return prefix + "com.apple.Software-Update-Settings.extension"
links=("${(@f)$(grep -E 'case \.[A-Za-z]+: return prefix \+ "' "$SRC" \
  | sed -E 's/.*case \.([A-Za-z]+): return prefix \+ "([^"]+)".*/\1 \2/')}")
(( ${#links} > 0 )) || { echo "no DeepLink URLs found in $SRC"; exit 2; }

echo "macOS $(sw_vers -productVersion): ${#links} links. Each opens System Settings; answer y/n/s(kip)."
pass=0; fail=(); skipped=0
for entry in $links; do
  name="${entry%% *}"
  url="$prefix${entry#* }"
  echo
  echo "$name"
  echo "  $url"
  /usr/bin/open "$url"
  read -r "answer?  Did the right pane open? [y/n/s] "
  case "$answer" in
    y|Y) pass=$(( pass + 1 )) ;;
    s|S) skipped=$(( skipped + 1 )) ;;
    *) fail+=("$name  $url") ;;
  esac
done

echo
echo "deeplink-test: $pass ok, ${#fail} wrong, $skipped skipped (macOS $(sw_vers -productVersion))"
for f in $fail; do echo "  WRONG $f"; done
(( ${#fail} == 0 ))
