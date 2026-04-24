# Development and Packaging

## Project Structure

- `Package.swift`: Swift Package Manager manifest.
- `Sources/VideoPlayer`: AppKit app source.
- `Scripts/build_app.sh`: Release build and `.app` bundle packaging.
- `Scripts/build_release_dmg.sh`: Builds the app bundle and wraps it in a drag-install DMG.
- `docs`: User and developer documentation.

## Build From Source

```sh
swift run
```

The app uses AVFoundation for Apple-native playback and dynamically loads LibVLC when available.

## Build the App Bundle

```sh
./Scripts/build_app.sh
```

The script creates:

```text
Build/Video Player.app
```

If `/Applications/VLC.app` is installed, the script copies VLC's `lib`, `plugins`, and `share` directories into `Contents/Resources/VLC` so the packaged app can use LibVLC without requiring a separate VLC install on the target machine.

## VLC Runtime Lookup

At runtime, the app searches for LibVLC in this order:

1. `Video Player.app/Contents/Resources/VLC/lib/libvlc.dylib`
2. `/Applications/VLC.app/Contents/MacOS/lib/libvlc.dylib`
3. `/opt/homebrew/lib/libvlc.dylib`
4. `/usr/local/lib/libvlc.dylib`

If LibVLC is unavailable, the app can fall back to `mpv` for advanced formats when `mpv` is installed in `PATH`, `/opt/homebrew/bin/mpv`, `/usr/local/bin/mpv`, or `/Applications/mpv.app/Contents/MacOS/mpv`.

## Build a Release DMG

```sh
./Scripts/build_release_dmg.sh
```

The script creates:

```text
Build/Video Player.dmg
```

The DMG includes the app and an `/Applications` shortcut. It is unsigned and not notarized; distribution outside local testing should use an Apple Developer ID certificate and notarization.

## State Storage

Playback positions, playlist URLs, selected playlist item, recent media, saved library folders, volume, audio preset, and playback speed are stored in `UserDefaults` through `PlaybackStateStore`.

## Validation

Use this before committing:

```sh
swift build
./Scripts/build_app.sh
./Scripts/build_release_dmg.sh
plutil -lint "Build/Video Player.app/Contents/Info.plist"
```
