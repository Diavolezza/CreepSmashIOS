#!/bin/bash
# App Store screenshots: every scene on the 6.9" iPhone and the 13" iPad, in English and German (iPhone landscape, iPad portrait).
# Needs the simulator build from ./build.sh. Usage (from the repository root):
#   tools/appstore/screenshots.sh [iphone|ipad] [en|de] [scene-number …]
# Output: build/appstore/<language>/<device>/NN-<name>.png
set -u
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/CreepSmash.app
BUNDLE=de.wanner-it.creepsmash
devices="${1:-iphone ipad}"; languages="${2:-en de}"; only="${*:3}"

# Scenes: number, name, seconds to wait, launch arguments.
scenes=(
  "01|menu|5|"
  "02|duel|9|-demo -opponents 1 -map rennbahn -botLevel normal"
  "03|four-players|9|-demo -opponents 3 -map wurmloch -botLevel hard"
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
  if [ "$kind" = "iphone" ]; then sim=$(find_sim "Pro Max"); else sim=$(find_sim "iPad Pro 13-inch"); fi
  [ -n "$sim" ] || { echo "** no simulator for $kind **"; continue; }
  echo "▸ $kind: $(xcrun simctl list devices | grep "$sim" | sed -E 's/ *\(.*//; s/^ *//')"
  xcrun simctl shutdown all >/dev/null 2>&1
  xcrun simctl boot "$sim"; xcrun simctl bootstatus "$sim" >/dev/null
  # iPhone in landscape (the app supports only that), iPad in portrait (its best layout). Clean status bar.
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
      xcrun simctl io "$sim" screenshot "$out/$num-$name.png" >/dev/null 2>&1 && echo "  ✓ $lang $num $name"
    done
  done
  xcrun simctl terminate "$sim" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl status_bar "$sim" clear >/dev/null 2>&1
  xcrun simctl shutdown "$sim" >/dev/null 2>&1
done
echo "▸ sizes:"; for f in build/appstore/*/*/01-*.png; do echo "  $f $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {printf "%s ", $2}')"; done
