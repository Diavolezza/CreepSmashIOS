#!/bin/bash
# Energy of an online game: the iPhone plays against a simulator on this Mac over the local network (Bonjour),
# both with the autopilot; for comparison the same game against the computer, also from tick 0.
# Usage (repository root, iPhone unlocked, on the same Wi-Fi as the Mac, on battery for the whole-phone number):
#   bash tools/energy/online.sh <label>; then bash tools/energy/export.sh <label> and python3 tools/energy/report.py <label>
DEV=00008150-001C5D2A0CF0401C
BUNDLE=de.wanner-it.creepsmash.game
SECS=${SECS:-120}
MAP=${MAP:-rennbahn}
LABEL=${1:-online}
OUT=build/energy/$LABEL; mkdir -p "$OUT"
SIMAPP=build/DerivedData/Build/Products/Debug-iphonesimulator/CreepSmash.app
[ -d "$SIMAPP" ] || { echo "** simulator app missing – run ./build.sh first **"; exit 1; }
# NETLOG=1: with the network log (copied to $OUT/phone-netlog.txt at the end).
FLAGS=(); [ -n "${NETLOG:-}" ] && FLAGS=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) NETLOG')
# NOBUILD=1: the app is already on the iPhone (second attempt).
[ -n "${NOBUILD:-}" ] || {
xcodebuild -project CreepSmash.xcodeproj -scheme CreepSmash -configuration Release -destination "id=$DEV" \
  -derivedDataPath "build/DeviceRelease-$LABEL" -allowProvisioningUpdates DEVELOPMENT_TEAM=H2TPCP2Q8W \
  ${FLAGS[@]+"${FLAGS[@]}"} build 2>&1 | grep -E "error:|BUILD" | tail -3
xcrun devicectl device install app --device $DEV "build/DeviceRelease-$LABEL"/Build/Products/Release-iphoneos/CreepSmash.app 2>&1 | grep -E "installed|rror" | head -2
}
# The opponent: the first iPhone simulator with iOS 26.
SIM=$(xcrun simctl list devices available | awk '/^-- iOS 26/{ok=1;next} /^--/{ok=0} ok && /iPhone/{match($0,/[0-9A-F-]{36}/); print substr($0,RSTART,RLENGTH); exit}')
xcrun simctl boot "$SIM" 2>/dev/null; xcrun simctl install "$SIM" "$SIMAPP"
record() {  # name, launch arguments
  local name=$1; shift
  # Over Wi-Fi xctrace often gives up ("Timed out waiting for device to boot"); asking devicectl first wakes the
  # connection, and a second or third attempt usually works.
  for attempt in 1 2 3; do
    rm -rf "$OUT/$name.trace"
    xcrun devicectl device info details --device $DEV >/dev/null 2>&1
    xcrun xctrace record --template 'Power Profiler' --device $DEV --time-limit ${SECS}s --output "$OUT/$name.trace" \
      --launch -- $BUNDLE -language de -musicEnabled NO "$@" 2>&1 | grep -v "^$" | tail -2
    [ -d "$OUT/$name.trace" ] && break
  done
  echo "✓ $name"
  sleep 5
}
record local -demo -demoFromStart -opponents 1 -map $MAP -botLevel normal
# Online scenes: "online" with the default bundle interval, "online<N>" for each N in BUNDLES (e.g. "4").
online() {  # name, extra launch arguments for both devices
  local name=$1; shift
  local code
  code=$(LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' </dev/urandom | head -c5)
  xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null
  xcrun simctl launch "$SIM" $BUNDLE -join "$code" -autopilot -playerName Sim -musicEnabled NO "$@" >/dev/null
  # Screenshots in the middle of the recording show that the game runs on both sides.
  ( sleep $((SECS / 2)); xcrun simctl io "$SIM" screenshot "$OUT/$name-sim.png" >/dev/null 2>&1
    xcrun devicectl device capture screenshot --device $DEV --destination "$OUT/$name-phone.png" >/dev/null 2>&1 ) &
  record "$name" -host "$code" -startWhen 2 -autopilot -map $MAP "$@"
  wait
}
online online
for n in ${BUNDLES:-}; do online "online$n" -bundleTicks "$n"; done
# The iPhone's network log, if built with NETLOG=1.
[ -n "${NETLOG:-}" ] && xcrun devicectl device copy from --device $DEV --domain-type appDataContainer \
  --domain-identifier $BUNDLE --source Documents/netlog.txt --destination "$OUT/phone-netlog.txt" 2>&1 | tail -1
# The simulator's network log, if its app was built with NETLOG ("./build.sh duo netlog").
cp "$(xcrun simctl get_app_container "$SIM" $BUNDLE data)/Documents/netlog.txt" "$OUT/online-sim-netlog.txt" 2>/dev/null
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null; xcrun simctl shutdown "$SIM"
