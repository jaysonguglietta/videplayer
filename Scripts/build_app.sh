#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Player"
BUNDLE_ID="${BUNDLE_ID:-com.jaysonguglietta.videoplayer}"
APP_VERSION="${APP_VERSION:-0.1.8}"
APP_BUILD="${APP_BUILD:-9}"
BUILD_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
ENABLE_EXTERNAL_ENGINES="${ENABLE_EXTERNAL_ENGINES:-0}"
DEVELOPMENT_BUILD="${DEVELOPMENT_BUILD:-0}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
ALLOW_UNVERIFIED_EXTERNAL_ENGINES="${ALLOW_UNVERIFIED_EXTERNAL_ENGINES:-0}"
REQUIRE_DEVELOPER_ID="${REQUIRE_DEVELOPER_ID:-}"
EXPECTED_DEVELOPER_TEAM_ID="${EXPECTED_DEVELOPER_TEAM_ID:-${APPLE_TEAM_ID:-}}"
TRUSTED_EXTERNAL_ENGINE_TEAM_IDS="${TRUSTED_EXTERNAL_ENGINE_TEAM_IDS:-}"
ENTERPRISE_LICENSE_PUBLIC_KEY="${ENTERPRISE_LICENSE_PUBLIC_KEY:-}"

if [[ "$ENABLE_EXTERNAL_ENGINES" == "1" ]]; then
    ENTITLEMENTS_PATH="$ROOT_DIR/Packaging/VideoPlayerExternalEngines.entitlements"
    EXTERNAL_MEDIA_ENGINES_PLIST_VALUE="true"
else
    ENTITLEMENTS_PATH="$ROOT_DIR/Packaging/VideoPlayer.entitlements"
    EXTERNAL_MEDIA_ENGINES_PLIST_VALUE="false"
fi

case "$BUILD_CONFIGURATION" in
    debug|release)
        ;;
    *)
        echo "BUILD_CONFIGURATION must be debug or release." >&2
        exit 1
        ;;
esac

UNVERIFIED_EXTERNAL_ENGINES_PLIST_VALUE="false"
if [[ "$DEVELOPMENT_BUILD" == "1" && "$BUILD_CONFIGURATION" == "debug" && "$ALLOW_UNVERIFIED_EXTERNAL_ENGINES" == "1" ]]; then
    UNVERIFIED_EXTERNAL_ENGINES_PLIST_VALUE="true"
fi

cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

if [[ -z "$REQUIRE_DEVELOPER_ID" ]]; then
    if [[ "$DEVELOPMENT_BUILD" == "1" ]]; then
        REQUIRE_DEVELOPER_ID=0
    else
        REQUIRE_DEVELOPER_ID=1
    fi
fi

if [[ "$DEVELOPMENT_BUILD" != "1" && "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
        echo "CODE_SIGN_IDENTITY is required for direct-distribution builds." >&2
        echo "Use DEVELOPMENT_BUILD=1 only for local ad-hoc testing." >&2
        exit 1
    fi
    if [[ -z "$EXPECTED_DEVELOPER_TEAM_ID" ]]; then
        echo "EXPECTED_DEVELOPER_TEAM_ID or APPLE_TEAM_ID is required so updates can verify Developer ID identity." >&2
        exit 1
    fi
    if [[ "$ENABLE_EXTERNAL_ENGINES" == "1" && -z "$TRUSTED_EXTERNAL_ENGINE_TEAM_IDS" ]]; then
        echo "TRUSTED_EXTERNAL_ENGINE_TEAM_IDS is required when ENABLE_EXTERNAL_ENGINES=1." >&2
        exit 1
    fi
fi

swift build -c "$BUILD_CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/$BUILD_CONFIGURATION/VideoPlayer" "$MACOS_DIR/VideoPlayer"
chmod +x "$MACOS_DIR/VideoPlayer"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VideoPlayer</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>VPExpectedDeveloperTeamID</key>
    <string>$EXPECTED_DEVELOPER_TEAM_ID</string>
    <key>VPTrustedExternalEngineTeamIDs</key>
    <string>$TRUSTED_EXTERNAL_ENGINE_TEAM_IDS</string>
    <key>VPExternalMediaEnginesAvailable</key>
    <$EXTERNAL_MEDIA_ENGINES_PLIST_VALUE/>
    <key>VPAllowUnverifiedExternalEnginesForDevelopment</key>
    <$UNVERIFIED_EXTERNAL_ENGINES_PLIST_VALUE/>
    <key>VPEnterpriseLicensePublicKey</key>
    <string>$ENTERPRISE_LICENSE_PUBLIC_KEY</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Media files</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>mp4</string>
                <string>m4v</string>
                <string>mov</string>
                <string>mk4</string>
                <string>mkv</string>
                <string>avi</string>
                <string>webm</string>
                <string>flv</string>
                <string>wmv</string>
                <string>mpg</string>
                <string>mpeg</string>
                <string>ts</string>
                <string>m2ts</string>
                <string>mp3</string>
                <string>m4a</string>
                <string>aac</string>
                <string>wav</string>
                <string>aiff</string>
                <string>aif</string>
                <string>caf</string>
                <string>flac</string>
                <string>ogg</string>
                <string>opus</string>
                <string>srt</string>
                <string>ass</string>
                <string>ssa</string>
                <string>vtt</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [[ "$ENABLE_EXTERNAL_ENGINES" == "1" ]]; then
    echo "No third-party media engines are bundled. Optional user-installed VLC/mpv can be used when trusted."
else
    echo "No third-party media engines are bundled. Default build is sandboxed and native-only."
fi

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    codesign --force \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign "$CODE_SIGN_IDENTITY" \
        "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
    echo "Signed $APP_DIR with $CODE_SIGN_IDENTITY"
else
    if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
        echo "Refusing to create an ad-hoc app when REQUIRE_DEVELOPER_ID=1." >&2
        exit 1
    fi
    codesign --force --deep --entitlements "$ENTITLEMENTS_PATH" --sign - "$APP_DIR" >/dev/null 2>&1 || true
    echo "Built ad-hoc signed app. Set CODE_SIGN_IDENTITY for Developer ID signing."
fi

echo "Built $APP_DIR"
