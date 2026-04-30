#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Player"
BUNDLE_ID="${BUNDLE_ID:-com.jaysonguglietta.videoplayer}"
APP_VERSION="${APP_VERSION:-0.1.3}"
APP_BUILD="${APP_BUILD:-4}"
BUILD_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
ENTITLEMENTS_PATH="$ROOT_DIR/Packaging/VideoPlayer.entitlements"

cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/VideoPlayer" "$MACOS_DIR/VideoPlayer"
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

echo "No third-party media engines are bundled. Optional user-installed VLC/mpv can be used at runtime."

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
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
    echo "Built ad-hoc signed app. Set CODE_SIGN_IDENTITY for Developer ID signing."
fi

echo "Built $APP_DIR"
