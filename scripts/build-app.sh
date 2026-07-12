#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/Morphling.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MorphlingApp "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Sources/MorphlingApp/Resources/. "$APP/Contents/Resources/"
[[ -x "$APP/Contents/MacOS/MorphlingApp" ]]
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" | grep -qx com.workview.morphling
[[ -f "$APP/Contents/Resources/Hooks/morphling-claude-event.sh" ]]
[[ -f "$APP/Contents/Resources/Hooks/morphling-codex-event.sh" ]]
for asset in MascotIdle MascotWorking MascotNeedsInput; do
  [[ -f "$APP/Contents/Resources/Mascots/$asset.svg" ]]
done
chmod +x "$APP/Contents/Resources/Hooks/"*.sh
codesign --force --deep --sign - "$APP"
echo "$APP"
