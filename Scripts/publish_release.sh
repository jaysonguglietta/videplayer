#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Player"
REPO="${GITHUB_REPOSITORY:-jaysonguglietta/videplayer}"

if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI is required. Install it, then run: gh auth login" >&2
    exit 1
fi

gh auth status >/dev/null

"$ROOT_DIR/Scripts/build_release_dmg.sh"

INFO_PLIST="$ROOT_DIR/Build/$APP_NAME.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
TAG="${TAG:-v$VERSION}"
DMG_PATH="$ROOT_DIR/Build/$APP_NAME.dmg"
ASSET_LABEL="$APP_NAME.dmg"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG_PATH#$ASSET_LABEL" --repo "$REPO" --clobber
else
    gh release create "$TAG" "$DMG_PATH#$ASSET_LABEL" \
        --repo "$REPO" \
        --title "$APP_NAME $VERSION" \
        --notes "Release $TAG of $APP_NAME. Includes the DMG used by the in-app updater."
fi

echo "Published $TAG with $ASSET_LABEL"
