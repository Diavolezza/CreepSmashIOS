#!/bin/bash
# App Store screenshots: every scene on the 6.9" iPhone, the 13" iPad and the inner display of the iPhone Duo,
# in English and German (iPhone and iPhone Duo landscape, iPad portrait).
# Needs the simulator build from ./build.sh. The iPhone Duo simulator cannot be unfolded from the command
# line: boot it, unfold it and turn it to landscape in the Device Hub of Xcode first.
# Usage (from the repository root):
#   tools/appstore/screenshots.sh [iphone|ipad|duo] [en|de] [scene-number …]
# Output: build/appstore/<language>/<device>/NN-<name>.png
set -u
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/CreepSmash.app
BUNDLE=de.wanner-it.creepsmash.game
devices="${1:-iphone ipad}"; languages="${2:-en de}"; only="${*:3}"

# Scenes: number, name, seconds to wait, launch arguments.
scenes=(
  "01|menu|5|"
  "02|duel|9|-demo -opponents 1 -map rennbahn -botLevel normal"
  "03|four-players|9|-demo -opponents 3 -map wurmloch -botLevel easy"
  "04|tower|9|-demo -opponents 1 -map mahlstrom -selectTower"
  "05|setup|5|-setup -map stromschnellen -opponents 3"
  "06|multiplayer|5|-multiplayer -sampleRounds"
  "07|evaluation|6|-sampleProgress -report"
  "08|achievements|6|-sampleProgress -records -recordsTab achievements"
)

find_sim() {  # newest available simulator whose name contains $1
  xcrun simctl list devices available | awk -v kind="$1" '
    /^-- iOS/ { ios = 1; next } /^--/ { ios = 0; next }
    ios && index($0, kind) { match($0, /[0-9A-F-]{36}/); last = substr($0, RSTART, RLENGTH) }
    END { print last }'
}

for kind in $devices; do
  display=()
  case "$kind" in
    iphone) sim=$(find_sim "Pro Max") ;;
    ipad) sim=$(find_sim "iPad Pro 13-inch") ;;
    # The booted, unfolded iPhone Duo; screen 3 is its inner display.
    duo) sim=$(xcrun simctl list devices booted | grep "iPhone Duo\|Duo-" | grep -oE '[0-9A-F-]{36}' | head -1)
         display=(--display=3) ;;
  esac
  [ -n "$sim" ] || { echo "** no simulator for $kind (the iPhone Duo must be booted and unfolded) **"; continue; }
  echo "▸ $kind: $(xcrun simctl list devices | grep "$sim" | sed -E 's/ *\(.*//; s/^ *//')"
  if [ "$kind" != duo ]; then
    xcrun simctl shutdown all >/dev/null 2>&1
    xcrun simctl boot "$sim"; xcrun simctl bootstatus "$sim" >/dev/null
  fi
  # iPhone in landscape (the app supports only that), iPad in portrait (its best layout), iPhone Duo as
  # turned in the Device Hub. Clean status bar.
  xcrun simctl status_bar "$sim" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode notSupported >/dev/null 2>&1
  for lang in $languages; do
    out="build/appstore/$lang/$kind"; mkdir -p "$out"
    # A fresh install per language: no records, no saved game from before.
    xcrun simctl uninstall "$sim" "$BUNDLE" >/dev/null 2>&1
    xcrun simctl install "$sim" "$APP"
    for scene in "${scenes[@]}"; do
      IFS='|' read -r num name wait args <<< "$scene"
      [ -n "$only" ] && [[ " $only " != *" $num "* ]] && continue
      xcrun simctl terminate "$sim" "$BUNDLE" >/dev/null 2>&1
      locale=$([ "$lang" = de ] && echo de_DE || echo en_US)
      # shellcheck disable=SC2086
      xcrun simctl launch "$sim" "$BUNDLE" -musicEnabled NO -soundEnabled NO -language "$lang" -AppleLocale "$locale" \
        -playerName Anna $args >/dev/null
      sleep "$wait"
      xcrun simctl io "$sim" screenshot "${display[@]}" "$out/$num-$name.png" >/dev/null 2>&1 && echo "  ✓ $lang $num $name"
    done
  done
  xcrun simctl terminate "$sim" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl status_bar "$sim" clear >/dev/null 2>&1
  [ "$kind" = duo ] || xcrun simctl shutdown "$sim" >/dev/null 2>&1
done
# App Store Connect asks for the 6.1"/6.3" iPhone (2622 × 1206); the 6.9" shots are scaled down to it.
for lang in $languages; do
  [ -d "build/appstore/$lang/iphone" ] || continue
  mkdir -p "build/appstore/$lang/iphone-6.3"
  for f in build/appstore/$lang/iphone/*.png; do
    sips -z 1206 2622 "$f" --out "build/appstore/$lang/iphone-6.3/$(basename "$f")" >/dev/null
  done
done
echo "▸ sizes:"; for f in build/appstore/*/*/01-*.png; do echo "  $f $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {printf "%s ", $2}')"; done
