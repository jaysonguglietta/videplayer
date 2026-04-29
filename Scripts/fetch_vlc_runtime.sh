#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VLC_VERSION="${VLC_VERSION:-3.0.23}"
VLC_ARCH="${VLC_ARCH:-arm64}"
BUILD_DIR="$ROOT_DIR/Build"
CACHE_DIR="$BUILD_DIR/ThirdParty/VLC-$VLC_VERSION-$VLC_ARCH"
RUNTIME_DIR="$CACHE_DIR/runtime"
DMG_NAME="vlc-$VLC_VERSION-$VLC_ARCH.dmg"
DMG_PATH="$CACHE_DIR/$DMG_NAME"
MOUNT_POINT="$CACHE_DIR/mount"

case "$VLC_ARCH" in
    arm64)
        VLC_SHA256="fc6fac08d87f538517d44aca0c5e7a244b67c8c4cb589bf478363a7315fd5e0d"
        ;;
    intel64)
        VLC_SHA256="ec01530ce69d849dd057fba8876e68ac39bf279dc28de4e9c04e4aec11fc98db"
        ;;
    universal)
        VLC_SHA256="56ee657c3aaf5c71b4ab7d6e4f4a77f6eca54633e0bf42a93b8116eb1d1f6ec9"
        ;;
    *)
        echo "Unsupported VLC_ARCH: $VLC_ARCH" >&2
        exit 1
        ;;
esac

if [[ -d "$RUNTIME_DIR/lib" && -d "$RUNTIME_DIR/plugins" && -f "$CACHE_DIR/.sha256" ]]; then
    if [[ "$(cat "$CACHE_DIR/.sha256")" == "$VLC_SHA256" ]]; then
        echo "Using pinned VLC $VLC_VERSION runtime from $RUNTIME_DIR"
        exit 0
    fi
fi

mkdir -p "$CACHE_DIR"

if [[ ! -f "$DMG_PATH" ]]; then
    VLC_URL="https://downloads.videolan.org/videolan/vlc/$VLC_VERSION/macosx/$DMG_NAME"
    echo "Downloading pinned VLC runtime from $VLC_URL"
    curl -fL "$VLC_URL" -o "$DMG_PATH"
fi

ACTUAL_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$VLC_SHA256" ]]; then
    echo "VLC checksum mismatch for $DMG_PATH" >&2
    echo "Expected: $VLC_SHA256" >&2
    echo "Actual:   $ACTUAL_SHA256" >&2
    exit 1
fi

rm -rf "$MOUNT_POINT" "$RUNTIME_DIR"
mkdir -p "$MOUNT_POINT" "$RUNTIME_DIR"

cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

VLC_APP="$(find "$MOUNT_POINT" -maxdepth 1 -name "VLC*.app" -print -quit)"
if [[ -z "$VLC_APP" ]]; then
    echo "Could not find VLC.app in $DMG_PATH" >&2
    exit 1
fi

VLC_MACOS_DIR="$VLC_APP/Contents/MacOS"
ditto "$VLC_MACOS_DIR/lib" "$RUNTIME_DIR/lib"
ditto "$VLC_MACOS_DIR/plugins" "$RUNTIME_DIR/plugins"
if [[ -d "$VLC_MACOS_DIR/share" ]]; then
    ditto "$VLC_MACOS_DIR/share" "$RUNTIME_DIR/share"
fi

echo "$VLC_SHA256" > "$CACHE_DIR/.sha256"
echo "Prepared pinned VLC $VLC_VERSION runtime at $RUNTIME_DIR"
