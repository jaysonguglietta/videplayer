#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Player"
BUNDLE_ID="local.video-player.app"
APP_VERSION="${APP_VERSION:-0.1.1}"
APP_BUILD="${APP_BUILD:-2}"
BUILD_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

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

VLC_MACOS_DIR="/Applications/VLC.app/Contents/MacOS"
if [[ -d "$VLC_MACOS_DIR/lib" && -d "$VLC_MACOS_DIR/plugins" ]]; then
    mkdir -p "$RESOURCES_DIR/VLC"
    ditto "$VLC_MACOS_DIR/lib" "$RESOURCES_DIR/VLC/lib"
    ditto "$VLC_MACOS_DIR/plugins" "$RESOURCES_DIR/VLC/plugins"
    if [[ -d "$VLC_MACOS_DIR/share" ]]; then
        ditto "$VLC_MACOS_DIR/share" "$RESOURCES_DIR/VLC/share"
    fi
    echo "Bundled VLC engine from /Applications/VLC.app"
else
    echo "VLC.app not found; the app will use system VLC/mpv if available at runtime."
fi

echo "Built $APP_DIR"
