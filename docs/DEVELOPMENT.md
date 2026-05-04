# Development and Packaging

## Project Structure

- `Package.swift`: Swift Package Manager manifest.
- `Sources/VideoPlayer`: AppKit app source.
- `Scripts/build_app.sh`: Release build and `.app` bundle packaging.
- `Scripts/build_release_dmg.sh`: Builds the app bundle and wraps it in a drag-install DMG.
- `Packaging/VideoPlayer.entitlements`: Sandboxed default commercial entitlements.
- `Packaging/VideoPlayerExternalEngines.entitlements`: Advanced opt-in entitlements for trusted user-installed media engine loading.
- `LICENSE`: MIT License for the Video Player application source code.
- `docs`: User and developer documentation.

## Build From Source

```sh
swift run
```

The app uses AVFoundation for Apple-native playback. The default commercial distribution is sandboxed and native-only. It does not bundle or load VLC, libVLC, VLC plugins, mpv, FFmpeg, or other third-party media engines.

LibVLC integration is kept behind `VLCBridge` for advanced external-engine builds. New symbols should be loaded dynamically and treated as optional unless playback cannot work without them; this keeps the app tolerant of different VLC 3.x builds. External engines are unavailable in default builds and must pass strict code-signature, configured Team ID, and Gatekeeper validation in advanced builds.

## Build the App Bundle

```sh
DEVELOPMENT_BUILD=1 ./Scripts/build_app.sh
```

The script creates:

```text
Build/Video Player.app
```

The script packages only the app binary and resources owned by this project. It intentionally does not download or bundle VLC/libVLC/mpv, which keeps the sold DMG limited to the MIT-licensed app plus Apple platform frameworks.

Default builds use `Packaging/VideoPlayer.entitlements`, which enables App Sandbox, user-selected file access, Downloads/Pictures access for updates and screenshots, and outbound network client access.

## Optional VLC Runtime Lookup

External engines are available only in builds created with `ENABLE_EXTERNAL_ENGINES=1`. At runtime, external engines are considered only when the user enables Playback > Enable External VLC/mpv Engines. The app only supports LibVLC from the signed VLC application bundle and verifies the containing code signature, Gatekeeper assessment, and Team ID against `VPTrustedExternalEngineTeamIDs`:

1. `/Applications/VLC.app/Contents/MacOS/lib/libvlc.dylib`

Raw Homebrew LibVLC library paths are intentionally not used because sibling `libvlccore` and plugin loading creates a wider trust surface. If LibVLC is unavailable, the app can fall back to `mpv` for advanced formats when `mpv` is installed at `/opt/homebrew/bin/mpv`, `/usr/local/bin/mpv`, or `/Applications/mpv.app/Contents/MacOS/mpv` and passes the same trust checks. `PATH` lookup is disabled by default to avoid path hijacking. `VIDEOPLAYER_ALLOW_PATH_MPV`, `VIDEOPLAYER_TRUSTED_ENGINE_TEAM_IDS`, and `VIDEOPLAYER_ALLOW_UNVERIFIED_ENGINES` are debug-only development overrides and are not honored by release builds.

To build the advanced variant:

```sh
export ENABLE_EXTERNAL_ENGINES=1
export TRUSTED_EXTERNAL_ENGINE_TEAM_IDS="TEAMID"
./Scripts/build_release_dmg.sh
```

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
export EXPECTED_DEVELOPER_TEAM_ID="TEAMID"
export UPDATE_SIGNING_PRIVATE_KEY="$HOME/.videoplayer-release/update-signing-private-key.pem"
```

`Scripts/build_app.sh` signs the app with hardened runtime and uses the sandboxed `Packaging/VideoPlayer.entitlements` by default. `Scripts/build_release_dmg.sh` signs the DMG, submits it to `notarytool`, staples the notarization ticket, and validates the staple. Direct-distribution builds require Developer ID signing and notarization by default. Use `DEVELOPMENT_BUILD=1` only for local ad-hoc testing.

## Update Checks

The in-app updater checks:

```text
https://api.github.com/repos/jaysonguglietta/videplayer/releases/latest
```

It compares the latest release tag against `CFBundleShortVersionString`, downloads the release's `video-player-update.json` manifest, verifies that manifest against the public key pinned in `UpdateManifest.swift`, downloads the signed manifest's `.dmg`, verifies the DMG's SHA-256, verifies the configured Developer ID Team ID, and runs Gatekeeper assessment before offering to open it.

To publish an update:

1. Bump `APP_VERSION` and `APP_BUILD` in `Scripts/build_app.sh`.
2. Keep `$HOME/.videoplayer-release/update-signing-private-key.pem` private, outside the repository and common synced folders, and backed up securely. The matching public key is pinned in `Sources/VideoPlayer/UpdateManifest.swift`.
3. Lock down the release key directory and key:

```sh
chmod 700 "$HOME/.videoplayer-release"
chmod 600 "$HOME/.videoplayer-release/update-signing-private-key.pem"
```

4. Commit the release on a clean `main` branch.
5. Create a signed tag at the release commit, for example:

```sh
git tag -s "v0.1.6" -m "Release v0.1.6"
```

6. Configure `CODE_SIGN_IDENTITY`, `NOTARY_PROFILE`, and `EXPECTED_DEVELOPER_TEAM_ID`.
7. Log in with `gh auth login`.
8. Run:

```sh
./Scripts/publish_release.sh
```

The script builds `Build/Video Player.dmg`, creates a signed update manifest, refuses to publish without Developer ID signing/notarization, refuses update private keys inside the repository or common synced folders, verifies key permissions, refuses dirty worktrees, refuses production publishing away from `main`, requires the release tag to exist at `HEAD`, refuses `ALLOW_UNNOTARIZED_RELEASE=1` on `main`, creates or updates a semver-style GitHub Release such as `v0.2.0`, and attaches both the DMG and manifest.

## State Storage

Playback positions, playlist URLs, selected playlist item, recent media, saved library folders, volume, audio preset, and playback speed are stored in `UserDefaults` through `PlaybackStateStore` when history saving is enabled. History saving is off by default. When history saving is disabled, playlists, recent media, resume positions, and saved library folders are not persisted. Network stream credentials, query strings, and fragments are redacted before URL persistence to avoid storing signed stream tokens. Privacy controls can enable saved playback history, clear history on quit, and clear all stored playback history.

## Network Stream Policy

`NetworkStreamValidator` accepts only HTTP, HTTPS, RTSP, and RTSPS. Loopback, link-local, multicast, RFC1918, CGNAT, benchmark ranges, `.local`, `localhost`, single-label hosts, and DNS names resolving to private/local addresses are blocked by default to reduce client-side SSRF and local-network probing risk. DNS checks run off the main UI path with a short timeout and fail closed when private network streams are disabled. Users can enable Privacy > Allow Private Network Streams for trusted LAN cameras or local streams.

## Optional LibVLC Features

When a user has VLC installed separately and the app was built with `ENABLE_EXTERNAL_ENGINES=1`, the app can use LibVLC for more than playback:

- metadata parsing before playback for richer movie, TV, artwork, language, and track details
- chapter discovery and chapter selection
- audio delay and output device selection
- video adjustment filters
- playback events for status, track changes, length changes, chapter changes, end, and error handling

## Licensing

Video Player's application source code is released under the MIT License. The default commercial distribution should remain sandboxed and should not bundle VLC/libVLC, mpv, FFmpeg, or other third-party media engines unless you are prepared to satisfy those upstream license terms. Optional advanced user-installed integrations keep their own upstream license terms.

## Validation

Use this before committing:

```sh
swift build
swift test
DEVELOPMENT_BUILD=1 ./Scripts/build_app.sh
DEVELOPMENT_BUILD=1 ./Scripts/build_release_dmg.sh
plutil -lint "Build/Video Player.app/Contents/Info.plist"
```
