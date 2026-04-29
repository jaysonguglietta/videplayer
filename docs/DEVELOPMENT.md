# Development and Packaging

## Project Structure

- `Package.swift`: Swift Package Manager manifest.
- `Sources/VideoPlayer`: AppKit app source.
- `Scripts/build_app.sh`: Release build and `.app` bundle packaging.
- `Scripts/build_release_dmg.sh`: Builds the app bundle and wraps it in a drag-install DMG.
- `LICENSE`: MIT License for the Video Player application source code.
- `docs`: User and developer documentation.

## Build From Source

```sh
swift run
```

The app uses AVFoundation for Apple-native playback and dynamically loads LibVLC when available.

LibVLC integration is kept behind `VLCBridge`. New symbols should be loaded dynamically and treated as optional unless playback cannot work without them; this keeps the app tolerant of different VLC 3.x builds.

## Build the App Bundle

```sh
./Scripts/build_app.sh
```

The script creates:

```text
Build/Video Player.app
```

The script calls `Scripts/fetch_vlc_runtime.sh`, which downloads the pinned official VLC 3.0.23 macOS DMG, verifies its SHA-256 checksum, mounts it, and copies VLC's `lib`, `plugins`, and `share` directories into `Contents/Resources/VLC`. This keeps release builds reproducible instead of copying whatever VLC app happens to be installed locally.

## VLC Runtime Lookup

At runtime, the app searches for LibVLC in this order:

1. `Video Player.app/Contents/Resources/VLC/lib/libvlc.dylib`
2. `/Applications/VLC.app/Contents/MacOS/lib/libvlc.dylib`
3. `/opt/homebrew/lib/libvlc.dylib`
4. `/usr/local/lib/libvlc.dylib`

If LibVLC is unavailable, the app can fall back to `mpv` for advanced formats when `mpv` is installed at `/opt/homebrew/bin/mpv`, `/usr/local/bin/mpv`, or `/Applications/mpv.app/Contents/MacOS/mpv`. `PATH` lookup is disabled by default to avoid path hijacking; set `VIDEOPLAYER_ALLOW_PATH_MPV=1` only in trusted development environments.

## Build a Release DMG

```sh
./Scripts/build_release_dmg.sh
```

The script creates:

```text
Build/Video Player.dmg
```

The DMG includes the app and an `/Applications` shortcut. For public distribution, set:

```sh
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
```

`Scripts/build_app.sh` signs nested VLC libraries, signs the app with hardened runtime, and uses `Packaging/VideoPlayer.entitlements` to allow dynamic VLC loading. `Scripts/build_release_dmg.sh` signs the DMG, submits it to `notarytool`, staples the notarization ticket, and validates the staple when `NOTARY_PROFILE` is set. Use `REQUIRE_NOTARIZATION=1` to fail the release build if notarization is not configured.

## Update Checks

The in-app updater checks:

```text
https://api.github.com/repos/jaysonguglietta/videplayer/releases/latest
```

It compares the latest release tag against `CFBundleShortVersionString`, downloads the release's `video-player-update.json` manifest, verifies that manifest against the public key pinned in `UpdateManifest.swift`, downloads the signed manifest's `.dmg`, then verifies the DMG's SHA-256 before offering to open it.

To publish an update:

1. Bump `APP_VERSION` and `APP_BUILD` in `Scripts/build_app.sh`.
2. Keep `.release/update-signing-private-key.pem` private and backed up. The matching public key is pinned in `Sources/VideoPlayer/UpdateManifest.swift`.
3. Configure `CODE_SIGN_IDENTITY` and `NOTARY_PROFILE`.
4. Log in with `gh auth login`.
5. Run:

```sh
./Scripts/publish_release.sh
```

The script builds `Build/Video Player.dmg`, creates a signed update manifest, refuses to publish without Developer ID signing/notarization unless `ALLOW_UNNOTARIZED_RELEASE=1` is set, creates or updates a semver-style GitHub Release such as `v0.2.0`, and attaches both the DMG and manifest.

## State Storage

Playback positions, playlist URLs, selected playlist item, recent media, saved library folders, volume, audio preset, and playback speed are stored in `UserDefaults` through `PlaybackStateStore`. Network stream credentials, query strings, and fragments are redacted before URL persistence to avoid storing signed stream tokens.

## LibVLC Features

The app now uses LibVLC for more than playback:

- metadata parsing before playback for richer movie, TV, artwork, language, and track details
- chapter discovery and chapter selection
- audio delay and output device selection
- video adjustment filters
- playback events for status, track changes, length changes, chapter changes, end, and error handling

## Licensing

Video Player's application source code is released under the MIT License. VLC/libVLC, mpv, Apple frameworks, and other upstream components keep their own license terms; keep the in-app Open Source Licenses notice current when adding or bundling dependencies.

## Validation

Use this before committing:

```sh
swift build
swift test
./Scripts/build_app.sh
./Scripts/build_release_dmg.sh
plutil -lint "Build/Video Player.app/Contents/Info.plist"
```
