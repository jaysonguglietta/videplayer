#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Player"
REPO="${GITHUB_REPOSITORY:-jaysonguglietta/videplayer}"
UPDATE_SIGNING_PRIVATE_KEY="${UPDATE_SIGNING_PRIVATE_KEY:-$ROOT_DIR/.release/update-signing-private-key.pem}"
MANIFEST_NAME="video-player-update.json"
DRY_RUN="${DRY_RUN:-0}"
ALLOW_UNNOTARIZED_RELEASE="${ALLOW_UNNOTARIZED_RELEASE:-0}"

if [[ "$DRY_RUN" != "1" && "$ALLOW_UNNOTARIZED_RELEASE" != "1" ]]; then
    if [[ -z "${CODE_SIGN_IDENTITY:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
        echo "Refusing to publish without Developer ID signing and notarization." >&2
        echo "Set CODE_SIGN_IDENTITY and NOTARY_PROFILE, or set ALLOW_UNNOTARIZED_RELEASE=1 for private testing only." >&2
        exit 1
    fi
fi

if [[ ! -f "$UPDATE_SIGNING_PRIVATE_KEY" ]]; then
    echo "Missing update signing private key: $UPDATE_SIGNING_PRIVATE_KEY" >&2
    echo "Generate one with:" >&2
    echo "  mkdir -p .release" >&2
    echo "  openssl ecparam -name prime256v1 -genkey -noout -out .release/update-signing-private-key.pem" >&2
    echo "Then update Sources/VideoPlayer/UpdateManifest.swift with the matching public key." >&2
    exit 1
fi

if [[ "$DRY_RUN" != "1" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "GitHub CLI is required. Install it, then run: gh auth login" >&2
        exit 1
    fi
    gh auth status >/dev/null
fi

"$ROOT_DIR/Scripts/build_release_dmg.sh"

INFO_PLIST="$ROOT_DIR/Build/$APP_NAME.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")"
MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST")"
TAG="${TAG:-v$VERSION}"
DMG_PATH="$ROOT_DIR/Build/$APP_NAME.dmg"
UPLOAD_DMG_PATH="$ROOT_DIR/Build/Video.Player.dmg"
ASSET_NAME="Video Player.dmg"
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/Video.Player.dmg"
MANIFEST_PATH="$ROOT_DIR/Build/$MANIFEST_NAME"
MANIFEST_PAYLOAD_PATH="$ROOT_DIR/Build/update-manifest-payload.txt"
MANIFEST_SIGNATURE_PATH="$ROOT_DIR/Build/update-manifest-signature.der"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

cp "$DMG_PATH" "$UPLOAD_DMG_PATH"

cat > "$MANIFEST_PAYLOAD_PATH" <<PAYLOAD
version=$VERSION
build=$BUILD
tagName=$TAG
minimumSystemVersion=$MINIMUM_SYSTEM_VERSION
assetName=$ASSET_NAME
assetURL=$ASSET_URL
sha256=$SHA256
PAYLOAD

openssl dgst -sha256 -sign "$UPDATE_SIGNING_PRIVATE_KEY" -out "$MANIFEST_SIGNATURE_PATH" "$MANIFEST_PAYLOAD_PATH"
SIGNATURE="$(base64 < "$MANIFEST_SIGNATURE_PATH" | tr -d '\n')"

cat > "$MANIFEST_PATH" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD",
  "tagName": "$TAG",
  "minimumSystemVersion": "$MINIMUM_SYSTEM_VERSION",
  "assetName": "$ASSET_NAME",
  "assetURL": "$ASSET_URL",
  "sha256": "$SHA256",
  "signature": "$SIGNATURE"
}
JSON

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run complete."
    echo "DMG: $DMG_PATH"
    echo "Manifest: $MANIFEST_PATH"
    exit 0
fi

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "$TAG" \
        --repo "$REPO" \
        --target main \
        --title "$APP_NAME $VERSION" \
        --notes "Release $TAG of $APP_NAME. Includes a signed update manifest and verified DMG asset."
fi

gh release upload "$TAG" "$UPLOAD_DMG_PATH#$ASSET_NAME" "$MANIFEST_PATH#$MANIFEST_NAME" --repo "$REPO" --clobber

echo "Published $TAG with $ASSET_NAME and $MANIFEST_NAME"
