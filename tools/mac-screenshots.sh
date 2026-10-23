#!/bin/zsh
# The §13.2 Mac screenshot matrix without XCUITest (no Developer Tools, Accessibility or Screen
# Recording prompt): the DEBUG app's hidden `-FSSnapshot` mode draws each `-FSDemoState` screen in
# its own window (light/dark × default/largest text) plus the menu-bar panel, saves PNGs at 1×
# and exits. Demo models are in memory: no CloudKit, network, checks, Keychain or login item.
# Build first (docs/BUILDING.md §3). If Python with Pillow is installed, the PNGs are
# palette-compressed afterwards (optional; nothing is installed).
# usage: tools/mac-screenshots.sh [outdir]   (default docs/screenshots/mac)
ROOT="${0:A:h}/.."
OUT="${1:-$ROOT/docs/screenshots/mac}"
APP="$ROOT/build/DerivedData/Build/Products/Debug/Family Shield.app/Contents/MacOS/Family Shield"
mkdir -p "$OUT"
# Replace only the PNGs this script writes (mac-*, menubar-*); nothing else in the folder.
rm -f -- "${OUT:?}"/mac-*.png(N) "${OUT:?}"/menubar-*.png(N)
perl -e 'alarm shift; exec @ARGV or die' 900 "$APP" -FSNoCloud -FSSnapshot "$OUT" || { echo "snapshot run failed or timed out"; exit 1; }
python3 - "$OUT" <<'PY' 2>/dev/null || echo "(Pillow not available: PNGs left uncompressed)"
import sys, glob
from PIL import Image
for path in glob.glob(sys.argv[1] + "/*.png"):
    Image.open(path).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT).save(path, optimize=True)
PY
ls "$OUT" | wc -l | xargs echo "screenshots:"
du -sh "$OUT"
