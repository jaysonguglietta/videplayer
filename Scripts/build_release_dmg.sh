#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Player"
BUILD_DIR="$ROOT_DIR/Build"
STAGING_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

"$ROOT_DIR/Scripts/build_app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

ditto "$BUILD_DIR/$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
    echo "Signed $DMG_PATH with $CODE_SIGN_IDENTITY"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    echo "Notarized and stapled $DMG_PATH"
elif [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
    echo "REQUIRE_NOTARIZATION=1 but NOTARY_PROFILE is not set." >&2
    exit 1
fi

echo "Built $DMG_PATH"
