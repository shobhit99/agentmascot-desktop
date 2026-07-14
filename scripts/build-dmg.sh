#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/build/Agent Mascot.app"
STAGING_DIR="$ROOT_DIR/build/dmg-root"
OUTPUT_DMG="${1:-$ROOT_DIR/build/Agent Mascot.dmg}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_AUTH_ARGS=()

if [[ -n "${NOTARYTOOL_PROFILE:-}" && -n "${NOTARYTOOL_KEY:-}" ]]; then
  echo "Set either NOTARYTOOL_PROFILE or NOTARYTOOL_KEY credentials, not both." >&2
  exit 2
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  NOTARY_AUTH_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
elif [[ -n "${NOTARYTOOL_KEY:-}" || -n "${NOTARYTOOL_KEY_ID:-}" || -n "${NOTARYTOOL_ISSUER:-}" ]]; then
  if [[ -z "${NOTARYTOOL_KEY:-}" || -z "${NOTARYTOOL_KEY_ID:-}" ]]; then
    echo "API-key notarization requires NOTARYTOOL_KEY and NOTARYTOOL_KEY_ID." >&2
    exit 2
  fi
  NOTARY_AUTH_ARGS=(--key "$NOTARYTOOL_KEY" --key-id "$NOTARYTOOL_KEY_ID")
  if [[ -n "${NOTARYTOOL_ISSUER:-}" ]]; then
    NOTARY_AUTH_ARGS+=(--issuer "$NOTARYTOOL_ISSUER")
  fi
fi

if [[ "$SIGNING_IDENTITY" == "-" && "${ALLOW_ADHOC_DMG:-0}" != "1" ]]; then
  echo "Refusing to create a public-looking DMG with an ad-hoc signature." >&2
  echo "Set SIGNING_IDENTITY to a Developer ID Application identity, or ALLOW_ADHOC_DMG=1 for local testing only." >&2
  exit 2
fi

if [[ "$SIGNING_IDENTITY" == "-" && "${#NOTARY_AUTH_ARGS[@]}" -gt 0 ]]; then
  echo "Notarization requires a Developer ID SIGNING_IDENTITY." >&2
  exit 2
fi

if [[ "$SIGNING_IDENTITY" != "-" && "${#NOTARY_AUTH_ARGS[@]}" -eq 0 && "${ALLOW_UNNOTARIZED_DMG:-0}" != "1" ]]; then
  echo "Refusing to create an unnotarized Developer ID DMG." >&2
  echo "Set NOTARYTOOL_PROFILE or API-key credentials, or ALLOW_UNNOTARIZED_DMG=1 for a non-public test artifact." >&2
  exit 2
fi

"$ROOT_DIR/scripts/build-app.sh"
codesign --verify --strict --verbose=2 "$APP"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP" "$STAGING_DIR/Agent Mascot.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$OUTPUT_DMG"

hdiutil create \
  -volname "Agent Mascot" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$OUTPUT_DMG"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$OUTPUT_DMG"
fi

hdiutil verify "$OUTPUT_DMG"

if [[ "${#NOTARY_AUTH_ARGS[@]}" -gt 0 ]]; then
  xcrun notarytool submit "$OUTPUT_DMG" "${NOTARY_AUTH_ARGS[@]}" --wait
  xcrun stapler staple "$OUTPUT_DMG"
  xcrun stapler validate "$OUTPUT_DMG"
fi

echo "$OUTPUT_DMG"
