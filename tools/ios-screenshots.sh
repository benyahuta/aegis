#!/bin/zsh
# The §13.2 iPhone screenshot matrix without XCUITest (no Developer Tools prompt): launches the
# built app with -FSNoCloud -FSDemoState <state> in light/dark × default/AX5 and saves PNGs.
# Build first (docs/BUILDING.md §2). Changes only the Simulator's appearance and text size.
# usage: tools/ios-screenshots.sh <simulator-udid> <DeviceName> <outdir>
UDID=$1; NAME=$2; OUT=$3
APP="${0:A:h}/../build/DerivedData/Build/Products/Debug-iphonesimulator/Family Shield.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
STATES=(welcome join whoToCall reminders accountsPicker homeProtected homeOneRed fixStep guidedStep scamEntry resultDanger resultCareful resultNoSigns callQuiz familyRules about familyTab deviceDetail pasteMessage serviceSteps startFamily addPerson feedHealth homeBuildBanner)
mkdir -p "$OUT"
xcrun simctl boot $UDID 2>/dev/null
xcrun simctl bootstatus $UDID -b >/dev/null
xcrun simctl install $UDID "$APP"
xcrun simctl status_bar $UDID override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
for APPEAR in light dark; do
  xcrun simctl ui $UDID appearance $APPEAR
  for SIZE in default ax5; do
    if [[ $SIZE == ax5 ]]; then CAT=UICTContentSizeCategoryAccessibilityXXXL; else CAT=UICTContentSizeCategoryL; fi
    for s in $STATES; do
      xcrun simctl launch --terminate-running-process $UDID $BUNDLE_ID \
        -FSNoCloud -FSDemoState $s -UIPreferredContentSizeCategoryName $CAT >/dev/null
      sleep 2.2
      xcrun simctl io $UDID screenshot "$OUT/$NAME-$APPEAR-$SIZE-$s.png" >/dev/null 2>&1
    done
  done
done
xcrun simctl terminate $UDID $BUNDLE_ID 2>/dev/null
xcrun simctl ui $UDID appearance light
echo "done $NAME"
