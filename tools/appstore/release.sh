#!/bin/bash
# Archives the app (Release) and uploads it to App Store Connect, signed automatically with the team
# given as first argument (Xcode must be signed in to that developer account: Settings › Accounts).
# The archive is signed for development (needs a device registered in the team, e.g. by choosing a connected
# iPhone in Xcode once); the export signs it again with the team's distribution certificate and prints the
# entitlements of the result (Game Center must be in it).
# Usage (from the repository root):  tools/appstore/release.sh TEAMID [--no-upload]
set -euo pipefail
TEAM="${1:?team ID missing}"
ARCHIVE=build/release/CreepSmash.xcarchive
rm -rf build/release; mkdir -p build/release
cat > build/release/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([ "${2:-}" = "--no-upload" ] && echo export || echo upload)</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
echo "▸ archiving"
xcodebuild -project CreepSmash.xcodeproj -scheme CreepSmash -configuration Release \
  -destination generic/platform=iOS -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" archive 2>&1 | grep -E "error:|warning: .*(sign|provision)|ARCHIVE" || true
[ -d "$ARCHIVE" ] || { echo "** archive failed **"; exit 1; }
plutil -p "$ARCHIVE/Info.plist" | grep -E "CFBundleShortVersionString|CFBundleVersion|SigningIdentity|Team" || true
echo "▸ exporting$([ "${2:-}" = "--no-upload" ] && echo "" || echo " and uploading to App Store Connect")"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/release/export \
  -exportOptionsPlist build/release/ExportOptions.plist -allowProvisioningUpdates 2>&1 \
  | grep -E "error|Upload|uploaded|EXPORT" | tail -15
IPA=$(ls build/release/export/*.ipa 2>/dev/null | head -1)
if [ -n "$IPA" ]; then
  rm -rf build/release/check && mkdir -p build/release/check && unzip -q "$IPA" -d build/release/check
  echo "▸ entitlements of the exported app:"
  codesign -d --entitlements - --xml build/release/check/Payload/*.app 2>/dev/null | plutil -p - 2>/dev/null | sed 's/^/    /'
fi
