#!/bin/bash
# Tests the game core and builds the app for the iOS simulator.
# Usage:   ./build.sh         test and build
#          ./build.sh run     also install and start in the simulator
#          ./build.sh demo    like run, but start a game with autopilot right away (for screenshots)
#          ./build.sh play    two visible simulators: you vs. autopilot over the network ("play manual": you operate both)
#          ./build.sh shot    start the app invisibly (with launch arguments), screenshot, quit
#          ./build.sh duo     two simulators play each other (autopilot), screenshots
#          ./build.sh mac     let Xcode build and start the iPad app on this Mac ("Designed for iPad", Apple silicon)
#          ./build.sh commit  commit everything with the message in build/commit-msg.txt and push
#          ./build.sh push    push again after a failed push
#          ./build.sh script  run the one-off script build/script.sh
#          ./build.sh about   set the GitHub description from build/about.txt (needs gh)
#          ./build.sh watch   waits for build requests from Claude (file build/request) and runs them;
#                             stop with Ctrl-C
set -uo pipefail
cd "$(dirname "$0")"

DERIVED=build/DerivedData
APP="$DERIVED/Build/Products/Debug-iphonesimulator/CreepSmash.app"
# Number of commits in the earlier history (archive repository); the version counter continues after it.
VERSION_OFFSET=23

# Writes the string catalog in Xcode's own form (order and layout), so Xcode does not rewrite it
# after changes made with other tools – otherwise it shows up as changed in git again and again.
normalize_strings() {
  swift tools/strings/normalize.swift CreepSmash/Localizable.xcstrings
}

build() {
  # First word = mode, the rest is passed to the app as launch arguments (e.g. "demo -map neon").
  local mode extra
  read -r mode extra <<< "${1:-}"
  if [ "$mode" = "stop" ]; then
    xcrun simctl shutdown all
    osascript -e 'tell application id "com.apple.iphonesimulator" to quit' >/dev/null 2>&1
    echo "✓ all simulators stopped"
    xcrun simctl list devices booted
    return 0
  fi
  if [ "$mode" = "commit" ]; then
    # Commit everything with the message in build/commit-msg.txt and push (runs with your git identity).
    [ -s build/commit-msg.txt ] || { echo "** build/commit-msg.txt is missing **"; return 1; }
    # Version 0.1.N with N = number of this commit, written into the project before committing.
    # VERSION_OFFSET: commits of the earlier history (kept in the archive repository), so the
    # counter continues after the history was started anew.
    local n=$(( $(git rev-list --count HEAD) + 1 + VERSION_OFFSET ))
    sed -i '' -E "s/(MARKETING_VERSION = )[0-9.]+;/\10.1.$n;/; s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$n;/" CreepSmash.xcodeproj/project.pbxproj
    echo "▸ version 0.1.$n"
    normalize_strings
    git add -A && git commit -q -F build/commit-msg.txt && git push 2>&1 && git log --oneline -3
    return $?
  fi
  if [ "$mode" = "mac" ]; then
    # The unchanged iPad app on an Apple-silicon Mac. macOS starts such an app only the way Xcode does
    # it, so Xcode is told to build and run it ("My Mac (Designed for iPad)", like ⌘R). The first time,
    # macOS asks whether Terminal may control Xcode.
    echo "▸ Xcode builds and starts the app on this Mac"
    osascript - "$PWD/CreepSmash.xcodeproj" <<'OSA'
on run argv
  tell application "Xcode"
    activate
    set ws to open POSIX file (item 1 of argv)
    repeat 120 times
      if loaded of ws then exit repeat
      delay 0.5
    end repeat
    set active scheme of ws to scheme "CreepSmash" of ws
    set macs to (run destinations of ws whose name contains "Mac")
    if (count of macs) is 0 then error "no Mac run destination – pick My Mac (Designed for iPad) in Xcode once"
    set active run destination of ws to item 1 of macs
    run ws
    return "✓ started in Xcode: " & (name of item 1 of macs)
  end tell
end run
OSA
    return $?
  fi
  if [ "$mode" = "script" ]; then
    # Runs a one-off script that Claude put into build/script.sh (build/ is not in git).
    [ -f build/script.sh ] || { echo "** build/script.sh is missing **"; return 1; }
    bash build/script.sh
    return $?
  fi
  if [ "$mode" = "push" ]; then
    # Push again (e.g. after a server error during "commit").
    git push 2>&1 && git log --oneline -3
    return $?
  fi
  if [ "$mode" = "about" ]; then
    # Set the GitHub "About" text (build/about.txt) and topics with the GitHub CLI.
    if ! command -v gh >/dev/null; then echo "** gh (GitHub CLI) is not installed: brew install gh && gh auth login **"; return 1; fi
    gh repo edit --description "$(cat build/about.txt)" \
      --add-topic ios --add-topic swift --add-topic swiftui --add-topic game --add-topic tower-defense --add-topic multiplayer \
      && gh repo view --json description,repositoryTopics
    return $?
  fi
  if [ "$mode" = "appcrash" ]; then
    local f
    f=$(ls -t ~/Library/Logs/DiagnosticReports/CreepSmash* 2>/dev/null | head -1)
    echo "▸ $f"
    [ -n "$f" ] && mkdir -p build && cp "$f" build/lastcrash.ips && head -c 200000 "$f"
    return 0
  fi
  if [ "$mode" = "crashes" ]; then
    echo "▸ crash reports of the last 3 minutes:"
    find ~/Library/Logs/DiagnosticReports -mmin -40 -type f 2>/dev/null | sed 's|.*/||'
    defaults read com.apple.CrashReporter 2>&1
    return 0
  fi
  if [ "$mode" = "findsim" ]; then
    mdfind "kMDItemCFBundleIdentifier == 'com.apple.iphonesimulator'"
    mdfind -name "Simulator.app" | head
    ls /Applications/Xcode.app/Contents/Developer/Applications/ 2>&1
    ls /Applications/Xcode.app/Contents/Applications/ 2>&1
    defaults read /Applications/Xcode.app/Contents/Info.plist CFBundleShortVersionString
    find /Applications/Xcode.app -maxdepth 6 -name "Simulator*.app" -type d 2>/dev/null
    ls /Applications /Library/Developer 2>/dev/null | grep -i -E "xcode|simul|coresim"
    return 0
  fi
  if [ "$mode" = "info" ]; then
    xcrun simctl list runtimes
    xcrun simctl list devices available
    xcodebuild -version
    return 0
  fi
  echo "▸ testing the game core"
  (cd CreepSmashCore && swift test 2>&1 | grep -E "error|failed|Executed .* tests" | tail -3)
  normalize_strings
  echo "▸ building the app for the simulator"
  if ! xcodebuild -project CreepSmash.xcodeproj -scheme CreepSmash \
      -configuration Debug -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$DERIVED" -quiet build; then
    echo "** BUILD FAILED **"
    return 1
  fi
  echo "✓ built: $APP"
  if [ "$mode" = "duo" ] || [ "$mode" = "play" ]; then
    # Two simulators play each other over the local network (both with autopilot),
    # then screenshots build/duo-host.png and build/duo-guest.png.
    # "duo quick" tests the quick game instead of a code; DUO_SECONDS = game duration (default 45).
    local devices a b code
    devices=$(xcrun simctl list devices available | awk -v want="${SIM_IOS:-26}" '
      /^-- iOS/ { split($3, v, "."); ios = (v[1] == want); if (ios) { n = 0; split("", d) }; next }
      /^--/     { ios = 0; next }
      ios && /iPhone/ { match($0, /[0-9A-F-]{36}/); d[++n] = substr($0, RSTART, RLENGTH) }
      END { print d[1]; print d[2] }')
    a=$(echo "$devices" | sed -n 1p); b=$(echo "$devices" | sed -n 2p)
    if [ -z "$a" ] || [ -z "$b" ]; then echo "** no two iPhone simulators with iOS ${SIM_IOS:-26} **"; return 1; fi
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    local name_a name_b
    name_a=$(xcrun simctl list devices | grep "$a" | sed -E 's/ *\(.*//; s/^ *//')
    name_b=$(xcrun simctl list devices | grep "$b" | sed -E 's/ *\(.*//; s/^ *//')
    echo "▸ simulators: $name_a (host), $name_b (guest)"
    xcrun simctl boot "$a"; xcrun simctl boot "$b"
    xcrun simctl install "$a" "$APP"; xcrun simctl install "$b" "$APP"
    if [ "$mode" = "play" ]; then
      # Visible: you play on the first simulator, the second one plays against you with autopilot.
      # "play manual": both start in the menu and you operate both yourself.
      local xcode_app simulator_app
      xcode_app="$(xcode-select -p)/../.."
      for candidate in "$xcode_app/Contents/Developer/Applications/Simulator.app" "$xcode_app/Contents/Applications/DeviceHub.app"; do
        [ -d "$candidate" ] && simulator_app="$candidate"
      done
      open "$simulator_app"
      if [[ "$extra" == *manual* ]]; then
        xcrun simctl launch "$a" de.wanner-it.creepsmash
        xcrun simctl launch "$b" de.wanner-it.creepsmash
        echo "✓ Both simulators show the menu – use \"Zu zweit\" on both"
      else
        code=$(LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' </dev/urandom | head -c5)
        xcrun simctl launch "$a" de.wanner-it.creepsmash -host "$code"
        sleep 3
        # The guest is called "Autopilot", so it is obvious which simulator is yours.
        xcrun simctl launch "$b" de.wanner-it.creepsmash -join "$code" -autopilot -playerName Autopilot -musicEnabled NO
        echo "✓ Game $code: you play on \"$name_a\", the autopilot on \"$name_b\""
      fi
      echo "  Stop with: ./build.sh stop"
      return 0
    fi
    if [[ "$extra" == *quick* ]]; then
      xcrun simctl launch "$a" de.wanner-it.creepsmash -quick -autopilot -musicEnabled NO
      sleep 2
      xcrun simctl launch "$b" de.wanner-it.creepsmash -quick -autopilot -musicEnabled NO
    else
      code=$(LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' </dev/urandom | head -c5)
      echo "▸ Code $code"
      # "duo solo": the host does nothing, only the guest plays (to check whose towers end up where).
      local host_auto="-autopilot"; [[ "$extra" == *solo* ]] && host_auto=""
      xcrun simctl launch "$a" de.wanner-it.creepsmash -host "$code" $host_auto -musicEnabled NO
      sleep 3
      xcrun simctl launch "$b" de.wanner-it.creepsmash -join "$code" -autopilot -musicEnabled NO
    fi
    sleep "${DUO_SECONDS:-45}"
    xcrun simctl io "$a" screenshot build/duo-host.png >/dev/null 2>&1 && echo "✓ screenshot: build/duo-host.png"
    xcrun simctl io "$b" screenshot build/duo-guest.png >/dev/null 2>&1 && echo "✓ screenshot: build/duo-guest.png"
    echo "▸ crash reports of the last 2 minutes:"
    find ~/Library/Logs/DiagnosticReports -mmin -2 -type f 2>/dev/null | sed 's|.*/||' | head
    xcrun simctl terminate "$a" de.wanner-it.creepsmash >/dev/null 2>&1 || true
    xcrun simctl terminate "$b" de.wanner-it.creepsmash >/dev/null 2>&1 || true
    xcrun simctl shutdown "$a" >/dev/null 2>&1 || true
    xcrun simctl shutdown "$b" >/dev/null 2>&1 || true
    echo "✓ duo finished, simulators shut down"
    return 0
  fi
  if [ "$mode" = "run" ] || [ "$mode" = "demo" ] || [ "$mode" = "shot" ]; then
    # Simulator: first iPhone of the newest iOS version with major number $SIM_IOS (default 26).
    # Under iOS 17.2 and 27.0 system services keep crashing in the simulator (error dialogs every few seconds).
    local device
    # "--ipad" among the extra words: use an iPad simulator instead of an iPhone.
    local kind="iPhone"
    # "--ipad-air": the smaller iPad Air 11-inch (narrowest iPad screen in portrait).
    if [[ " $extra " == *" --ipad-air "* ]]; then kind="iPad Air 11"; extra="${extra//--ipad-air/}"; fi
    if [[ " $extra " == *" --ipad "* ]]; then kind="iPad"; extra="${extra//--ipad/}"; fi
    device=$(xcrun simctl list devices available | awk -v want="${SIM_IOS:-26}" -v kind="$kind" '
      /^-- iOS/ { split($3, v, "."); ios = (v[1] == want); found = ""; next }
      /^--/     { ios = 0; next }
      ios && $0 ~ kind && found == "" { match($0, /[0-9A-F-]{36}/); found = substr($0, RSTART, RLENGTH); last = found }
      END { print last }')
    if ! xcrun simctl list devices booted | grep -q "$device"; then
      xcrun simctl shutdown all >/dev/null 2>&1 || true
      echo "▸ booting simulator $(xcrun simctl list devices | grep "$device" | sed -E 's/ *\(.*//; s/^ *//') ($device)"
      xcrun simctl boot "$device"
    fi
    # Open the simulator window or bring it to the front (a booted simulator otherwise runs invisibly).
    # Simulator window: "Simulator.app" up to Xcode 26, "DeviceHub.app" from Xcode 27
    local simulator_app xcode_app
    xcode_app="$(xcode-select -p)/../.."
    for candidate in "$xcode_app/Contents/Developer/Applications/Simulator.app" "$xcode_app/Contents/Applications/DeviceHub.app"; do
      [ -d "$candidate" ] && simulator_app="$candidate"
    done
    [ "$mode" = "run" ] && open "$simulator_app" --args -CurrentDeviceUDID "$device"
    xcrun simctl install "$device" "$APP"
    xcrun simctl terminate "$device" de.wanner-it.creepsmash >/dev/null 2>&1 || true
    if [ "$mode" = "demo" ]; then
      xcrun simctl launch "$device" de.wanner-it.creepsmash -demo -musicEnabled NO $extra
      sleep 20
      echo "▸ crash reports of the last 2 minutes:"
      find ~/Library/Logs/DiagnosticReports -mmin -2 -type f 2>/dev/null | sed 's|.*/||' | head
    elif [ "$mode" = "shot" ]; then
      # Screenshots and tests run without background music.
      xcrun simctl launch "$device" de.wanner-it.creepsmash -musicEnabled NO $extra
      sleep 6
    else
      xcrun simctl launch "$device" de.wanner-it.creepsmash $extra
      sleep 4
    fi
    xcrun simctl io "$device" screenshot build/screenshot.png >/dev/null 2>&1 && echo "✓ screenshot: build/screenshot.png"
    if [ "$mode" = "demo" ] || [ "$mode" = "shot" ]; then
      # The demo game keeps playing itself with autopilot (with sound) – quit after the screenshot
      # and shut down the simulator so nothing keeps running in the background.
      xcrun simctl terminate "$device" de.wanner-it.creepsmash >/dev/null 2>&1 || true
      xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
      echo "✓ finished, simulator shut down"
      return 0
    fi
    # Bring the simulator window to the front
    [ "$mode" = "run" ] && open "$simulator_app"
    echo "✓ running in the simulator"
  fi
}

if [ "${1:-}" = "watch" ]; then
  mkdir -p build
  echo "Waiting for build requests (build/request). Stop with Ctrl-C."
  while true; do
    if [ -f build/request ]; then
      mode=$(cat build/request)
      rm -f build/request
      echo "$(date '+%H:%M:%S') build request ($mode)"
      # Call the script anew each time so changes to build.sh take effect immediately.
      "./build.sh" "$mode" > build.log 2>&1
      echo "done $(date '+%s')" >> build.log
      tail -2 build.log
    fi
    sleep 2
  done
elif [ -t 1 ]; then
  build "$*" 2>&1 | tee build.log
else
  build "$*"
fi
