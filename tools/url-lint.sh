#!/bin/zsh
# SPEC §12.4 CI lint: every displayed URL comes from compiled constants in DeepLinks.swift,
# Services.swift or catalog.json, so `URL(string:` anywhere else in app code fails.
# Scans the Swift sources of ShieldCore and the apps (tests are not app code). Lines that are
# only a `//` comment are ignored. Same rule as CatalogLintTests.testURLConstantsLiveOnlyInAllowedFiles.
# Exit 0: clean. Exit 1: prints each offending file:line.
# usage: tools/url-lint.sh
setopt extended_glob
ROOT="${0:A:h}/.."
cd "$ROOT" || exit 2
ALLOWED=(
  "ShieldCore/Sources/ShieldCore/Catalog/DeepLinks.swift"
  "ShieldCore/Sources/ShieldCore/Catalog/Services.swift"
)
DIRS=(ShieldCore/Sources ShieldiOS ShieldMac ShieldShare)
existing=()
for d in $DIRS; do [[ -d "$d" ]] && existing+=("$d"); done
(( ${#existing} > 0 )) || { echo "no source folders found"; exit 2; }

hits=("${(@f)$(grep -rnF --include='*.swift' 'URL(string:' $existing 2>/dev/null)}")
bad=0
for hit in $hits; do
  [[ -z "$hit" ]] && continue
  file="${hit%%:*}"
  rest="${hit#*:}"
  text="${rest#*:}"
  (( ${ALLOWED[(Ie)$file]} )) && continue
  [[ "${text##[[:space:]]#}" == //* ]] && continue
  echo "$hit"
  bad=$(( bad + 1 ))
done

if (( bad > 0 )); then
  echo "url-lint: $bad use(s) of URL(string: outside DeepLinks.swift / Services.swift (SPEC §12.4)"
  exit 1
fi
echo "url-lint: ok (URL(string: only in DeepLinks.swift and Services.swift)"
