#!/bin/bash
# Energy measurement on the iPhone with the Power Profiler (Instruments). Usage (repository root, iPhone connected and unlocked): bash tools/energy/measure.sh <label>; then bash tools/energy/export.sh <label> and python3 tools/energy/report.py <label>
# Builds a Release build for the iPhone, installs it and records four scenes of 60 s each.
DEV=00008150-001C5D2A0CF0401C
BUNDLE=de.wanner-it.creepsmash.game
# SRC: another copy of the sources (e.g. an older commit from git archive), default the working copy.
SRC=${SRC:-.}
OUT=build/energy/${1:-run}; mkdir -p "$OUT"
xcodebuild -project "$SRC/CreepSmash.xcodeproj" -scheme CreepSmash -configuration Release -destination "id=$DEV" \
  -derivedDataPath "build/DeviceRelease-${1:-run}" -allowProvisioningUpdates DEVELOPMENT_TEAM=H2TPCP2Q8W build 2>&1 | grep -E "error:|BUILD" | tail -3
xcrun devicectl device install app --device $DEV "build/DeviceRelease-${1:-run}"/Build/Products/Release-iphoneos/CreepSmash.app 2>&1 | grep -E "installed|rror" | head -2
scene() {  # name, seconds, launch arguments
  local name=$1 secs=$2; shift 2
  rm -rf "$OUT/$name.trace"
  xcrun xctrace record --template 'Power Profiler' --device $DEV --time-limit ${secs}s --output "$OUT/$name.trace" \
    --launch -- $BUNDLE -language de "$@" 2>&1 | grep -v "^$" | tail -2
  echo "✓ $name"
  sleep 5
}
# Effects on everywhere (builds up to 1.0.5 read "-soundEnabled NO" as on, so old and new compare fairly).
scene menu 60 -musicEnabled NO
scene menu-music 60 -musicEnabled YES
scene duel 90 -demo -opponents 1 -map rennbahn -botLevel easy -musicEnabled NO
scene four 90 -demo -opponents 3 -map wurmloch -botLevel easy -musicEnabled NO
