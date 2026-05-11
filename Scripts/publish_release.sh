#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Player"
REPO="${GITHUB_REPOSITORY:-jaysonguglietta/videplayer}"
UPDATE_SIGNING_KEYCHAIN_SERVICE="${UPDATE_SIGNING_KEYCHAIN_SERVICE:-videoplayer-update-signing-private-key}"
UPDATE_SIGNING_PRIVATE_KEY="${UPDATE_SIGNING_PRIVATE_KEY:-}"
ALLOW_FILE_UPDATE_SIGNING_KEY="${ALLOW_FILE_UPDATE_SIGNING_KEY:-0}"
MANIFEST_NAME="video-player-update.json"
PROVENANCE_NAME="video-player-release-provenance.json"
DRY_RUN="${DRY_RUN:-0}"
ALLOW_UNNOTARIZED_RELEASE="${ALLOW_UNNOTARIZED_RELEASE:-0}"
EXPECTED_DEVELOPER_TEAM_ID="${EXPECTED_DEVELOPER_TEAM_ID:-${APPLE_TEAM_ID:-}}"
RELEASE_APPROVAL="${RELEASE_APPROVAL:-}"
CURRENT_BRANCH="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
SIGNING_KEY_FILE=""
SIGNING_KEY_SOURCE=""
TEMP_SIGNING_KEY=""

cleanup_temp_signing_key() {
    if [[ -n "$TEMP_SIGNING_KEY" && -f "$TEMP_SIGNING_KEY" ]]; then
        rm -f "$TEMP_SIGNING_KEY"
    fi
}
trap cleanup_temp_signing_key EXIT

if [[ "$DRY_RUN" != "1" && "$ALLOW_UNNOTARIZED_RELEASE" != "1" ]]; then
    if [[ -z "${CODE_SIGN_IDENTITY:-}" || -z "${NOTARY_PROFILE:-}" || -z "$EXPECTED_DEVELOPER_TEAM_ID" ]]; then
        echo "Refusing to publish without Developer ID signing and notarization." >&2
        echo "Set CODE_SIGN_IDENTITY, NOTARY_PROFILE, and EXPECTED_DEVELOPER_TEAM_ID." >&2
        exit 1
    fi
fi

if [[ "$ALLOW_UNNOTARIZED_RELEASE" == "1" && "$CURRENT_BRANCH" == "main" ]]; then
    echo "Refusing ALLOW_UNNOTARIZED_RELEASE=1 on main." >&2
    exit 1
fi

validate_file_signing_key_path() {
    local key_path="$1"
    case "$key_path" in
        "$ROOT_DIR"/*)
            echo "Refusing to use an update signing private key inside the repository or synced workspace." >&2
            exit 1
            ;;
    esac

    local sync_paths=(
        "$HOME/SynologyDrive"
        "$HOME/Library/Mobile Documents"
        "$HOME/Dropbox"
        "$HOME/Google Drive"
        "$HOME/OneDrive"
    )
    local sync_path
    for sync_path in "${sync_paths[@]}"; do
        case "$key_path" in
            "$sync_path"/*)
                echo "Refusing to use an update signing private key inside a synced folder: $sync_path" >&2
                exit 1
                ;;
        esac
    done

    if [[ ! -f "$key_path" ]]; then
        echo "Missing update signing private key: $key_path" >&2
        exit 1
    fi

    local key_mode
    local key_dir
    local key_dir_mode
    key_mode="$(stat -f "%Lp" "$key_path")"
    key_dir="$(dirname "$key_path")"
    key_dir_mode="$(stat -f "%Lp" "$key_dir")"
    if [[ "$key_mode" != "600" ]]; then
        echo "Refusing to use update signing key with permissions $key_mode. Run: chmod 600 \"$key_path\"" >&2
        exit 1
    fi
    if [[ "$key_dir_mode" != "700" ]]; then
        echo "Refusing to use update signing key directory with permissions $key_dir_mode. Run: chmod 700 \"$key_dir\"" >&2
        exit 1
    fi
}

load_update_signing_key() {
    if [[ -n "$UPDATE_SIGNING_KEYCHAIN_SERVICE" ]]; then
        if ! command -v security >/dev/null 2>&1; then
            echo "macOS security CLI is required for Keychain-backed release signing." >&2
            exit 1
        fi

        TEMP_SIGNING_KEY="$(mktemp "/tmp/videoplayer-update-signing-key.XXXXXX")"
        chmod 600 "$TEMP_SIGNING_KEY"
        if ! security find-generic-password -w -s "$UPDATE_SIGNING_KEYCHAIN_SERVICE" > "$TEMP_SIGNING_KEY"; then
            echo "Missing Keychain update signing key service: $UPDATE_SIGNING_KEYCHAIN_SERVICE" >&2
            echo "Store the PEM private key in Keychain or set UPDATE_SIGNING_KEYCHAIN_SERVICE= and ALLOW_FILE_UPDATE_SIGNING_KEY=1 with UPDATE_SIGNING_PRIVATE_KEY." >&2
            exit 1
        fi
        SIGNING_KEY_FILE="$TEMP_SIGNING_KEY"
        SIGNING_KEY_SOURCE="keychain:$UPDATE_SIGNING_KEYCHAIN_SERVICE"
    elif [[ -n "$UPDATE_SIGNING_PRIVATE_KEY" ]]; then
        if [[ "$ALLOW_FILE_UPDATE_SIGNING_KEY" != "1" ]]; then
            echo "Refusing file-based update signing key without ALLOW_FILE_UPDATE_SIGNING_KEY=1." >&2
            echo "Prefer UPDATE_SIGNING_KEYCHAIN_SERVICE=videoplayer-update-signing-private-key." >&2
            exit 1
        fi
        validate_file_signing_key_path "$UPDATE_SIGNING_PRIVATE_KEY"
        SIGNING_KEY_FILE="$UPDATE_SIGNING_PRIVATE_KEY"
        SIGNING_KEY_SOURCE="file"
    else
        echo "Missing update signing key. Prefer storing the PEM key in Keychain service videoplayer-update-signing-private-key." >&2
        exit 1
    fi

    if ! openssl pkey -in "$SIGNING_KEY_FILE" -noout >/dev/null 2>&1; then
        echo "Update signing key could not be parsed by OpenSSL." >&2
        exit 1
    fi
}

load_update_signing_key

if [[ "$DRY_RUN" != "1" ]]; then
    if [[ "$CURRENT_BRANCH" != "main" ]]; then
        echo "Refusing to publish a production release from branch $CURRENT_BRANCH. Switch to main first." >&2
        exit 1
    fi
    if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
        echo "Refusing to publish with uncommitted changes." >&2
        exit 1
    fi
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
PROVENANCE_PATH="$ROOT_DIR/Build/$PROVENANCE_NAME"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
COMMIT_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"

if [[ "$DRY_RUN" != "1" && "$RELEASE_APPROVAL" != "$TAG" ]]; then
    echo "Refusing to publish without explicit release approval." >&2
    echo "Set RELEASE_APPROVAL=$TAG after reviewing the notarized DMG, signed tag, manifest, and provenance." >&2
    exit 1
fi

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

openssl dgst -sha256 -sign "$SIGNING_KEY_FILE" -out "$MANIFEST_SIGNATURE_PATH" "$MANIFEST_PAYLOAD_PATH"
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

MANIFEST_SHA256="$(shasum -a 256 "$MANIFEST_PATH" | awk '{print $1}')"
cat > "$PROVENANCE_PATH" <<JSON
{
  "appName": "$APP_NAME",
  "repository": "$REPO",
  "branch": "$CURRENT_BRANCH",
  "commit": "$COMMIT_SHA",
  "tagName": "$TAG",
  "version": "$VERSION",
  "build": "$BUILD",
  "assetName": "$ASSET_NAME",
  "assetSHA256": "$SHA256",
  "manifestName": "$MANIFEST_NAME",
  "manifestSHA256": "$MANIFEST_SHA256",
  "signingKeySource": "$SIGNING_KEY_SOURCE",
  "developerTeamID": "$EXPECTED_DEVELOPER_TEAM_ID",
  "notarizationRequired": "$([[ "$ALLOW_UNNOTARIZED_RELEASE" == "1" ]] && echo "false" || echo "true")"
}
JSON

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run complete."
    echo "DMG: $DMG_PATH"
    echo "Manifest: $MANIFEST_PATH"
    echo "Provenance: $PROVENANCE_PATH"
    exit 0
fi

if ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Refusing to publish without a local release tag: $TAG" >&2
    echo "Create a signed tag at the release commit first: git tag -s \"$TAG\" -m \"Release $TAG\"" >&2
    exit 1
fi
if ! git -C "$ROOT_DIR" tag -v "$TAG" >/dev/null 2>&1; then
    echo "Refusing to publish because $TAG is not a verifiable signed tag." >&2
    echo "Create it with: git tag -s \"$TAG\" -m \"Release $TAG\"" >&2
    exit 1
fi
if [[ "$(git -C "$ROOT_DIR" rev-list -n 1 "$TAG")" != "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]]; then
    echo "Refusing to publish because $TAG does not point at HEAD." >&2
    exit 1
fi

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "$TAG" \
        --repo "$REPO" \
        --verify-tag \
        --title "$APP_NAME $VERSION" \
        --notes "Release $TAG of $APP_NAME. Includes a signed update manifest and verified DMG asset."
fi

gh release upload "$TAG" "$UPLOAD_DMG_PATH#$ASSET_NAME" "$MANIFEST_PATH#$MANIFEST_NAME" "$PROVENANCE_PATH#$PROVENANCE_NAME" --repo "$REPO" --clobber

echo "Published $TAG with $ASSET_NAME, $MANIFEST_NAME, and $PROVENANCE_NAME"
