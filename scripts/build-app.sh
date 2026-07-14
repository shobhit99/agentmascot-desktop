#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${CONFIGURATION:-release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
RESOURCE_BUNDLE_NAME="AgentMascot_AgentMascotApp.bundle"
BUILD_ARGS=(-c "$CONFIGURATION")

if [[ "${DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
  BUILD_ARGS=(--disable-sandbox "${BUILD_ARGS[@]}")
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP="$ROOT_DIR/build/Agent Mascot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AgentMascotApp" "$APP/Contents/MacOS/"
cp "$ROOT_DIR/Resources/Info.plist" "$APP/Contents/"
cp -R "$BIN_DIR/$RESOURCE_BUNDLE_NAME" "$APP/Contents/Resources/"

[[ -x "$APP/Contents/MacOS/AgentMascotApp" ]]
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" | grep -qx com.workview.agentmascot
RESOURCE_BUNDLE="$APP/Contents/Resources/$RESOURCE_BUNDLE_NAME"
[[ -f "$RESOURCE_BUNDLE/agent-mascot-claude-event.sh" ]]
[[ -f "$RESOURCE_BUNDLE/agent-mascot-codex-event.sh" ]]
for asset in MascotIdle MascotWorking MascotNeedsInput; do
  [[ -f "$RESOURCE_BUNDLE/$asset.svg" ]]
done
[[ -f "$RESOURCE_BUNDLE/frame-001.png" ]]
[[ -f "$RESOURCE_BUNDLE/frame-049.png" ]]
for unused_asset in haland.apng haland_out.mov; do
  if [[ -e "$RESOURCE_BUNDLE/$unused_asset" ]]; then
    echo "Unexpected unused release asset: $RESOURCE_BUNDLE/$unused_asset" >&2
    echo "Run 'swift package clean' before rebuilding." >&2
    exit 1
  fi
done
chmod +x "$RESOURCE_BUNDLE/"*.sh

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"
echo "$APP"
