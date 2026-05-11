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

The app uses AVFoundation for Apple-native playback. The default commercial distribution is sandboxed and native-only. It does not bundle or load VLC, libVLC, VLC plugins, mpv, FFmpeg, or other third-party media engines. `NativePlaybackPolicy` inspects local video format descriptions before playback; Dolby Vision sample entries and non-Apple-native containers require a trusted external engine, HEVC/x265 prefers one when available, and a native playback watchdog catches audio-only native starts so the app can fail over or show a clear codec message.

LibVLC integration is kept behind `VLCBridge` for advanced external-engine builds. New symbols should be loaded dynamically and treated as optional unless playback cannot work without them; this keeps the app tolerant of different VLC 3.x builds. External engines are unavailable in default builds and must pass strict code-signature, configured Team ID, and Gatekeeper validation in advanced builds. VLC runtime loading must validate `libvlc.dylib` and `libvlccore.dylib`; plugin/data paths are allowed only inside a verified `.app` runtime so raw dylib installs cannot load unverified sibling plugins.

The main AppKit surface is built programmatically in `PlayerViewController`. Keep the first screen focused on the player itself, keep the sidebar optional, and give new controls explicit tooltips plus accessibility labels/help text. Dense playback tools should wrap into clear rows rather than requiring a wide window.

Playlist import/export uses UTF-8 M3U/M3U8 text files. Imported local entries are resolved through the existing media extension filter, relative entries are resolved against the playlist file location, and imported network entries must pass `NetworkStreamValidator` before they are added. Skipped import entries should include line-level reasons.

Network stream validation resolves public hosts off the main thread before adding a stream and revalidates the stream immediately before playback. DNS results are pinned in memory for the session, and playback is blocked if a previously added stream resolves to a disjoint address set.

`PlaylistWorkflow` owns reusable playlist search, sort, export, path-resolution, and import-result helpers. Keep playlist behavior that can be tested without AppKit in this workflow layer, and leave `PlayerViewController` responsible for UI wiring, dialogs, and playback state coordination.

`AppLogger` writes a rotating diagnostic log to the user's Library Logs folder. The app exposes Video Player > Reveal Log File and Help > Reveal Log File. Log playback routing, codec decisions, external-engine validation, VLC/mpv startup, update checks, and verification failures before risky or blocking operations. Security validation subprocesses have a 10-second timeout so `codesign` or `spctl` cannot leave the app indefinitely unresponsive.

`PlaylistWorkflowSmokeTests` covers the UI-facing playlist workflows that can run without launching AppKit: search, sort, M3U8 export, skipped-entry reporting, relative path resolution, drag reorder math, and multi-row removal. Manual QA should still exercise the built app with local media, stream URLs, and mixed-result M3U8 files before release.

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

For local playback QA only, a debug development app can bypass external-engine signature checks when the separately installed engine is known but macOS signature validation is failing locally:

```sh
DEVELOPMENT_BUILD=1 \
BUILD_CONFIGURATION=debug \
ENABLE_EXTERNAL_ENGINES=1 \
TRUSTED_EXTERNAL_ENGINE_TEAM_IDS="TEAMID" \
ALLOW_UNVERIFIED_EXTERNAL_ENGINES=1 \
./Scripts/build_app.sh
```

Do not use that debug-only override for release, notarized, or customer builds.

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
export UPDATE_SIGNING_KEYCHAIN_SERVICE="videoplayer-update-signing-private-key"
```

`Scripts/build_app.sh` signs the app with hardened runtime and uses the sandboxed `Packaging/VideoPlayer.entitlements` by default. `Scripts/build_release_dmg.sh` signs the DMG, submits it to `notarytool`, staples the notarization ticket, and validates the staple. Direct-distribution builds require Developer ID signing and notarization by default. Use `DEVELOPMENT_BUILD=1` only for local ad-hoc testing.

## Update Checks

The in-app updater checks:

```text
https://api.github.com/repos/jaysonguglietta/videplayer/releases?per_page=20
```

It ignores draft and prerelease entries, selects the newest published release by version, then compares that tag against `CFBundleShortVersionString`. If the installed app is newer than the newest published release, the app reports that no newer update is available and prompts you to publish the installed version or later. For newer releases, it downloads the release's `video-player-update.json` manifest, verifies that manifest against the public key pinned in `UpdateManifest.swift`, downloads the signed manifest's `.dmg`, verifies the DMG's SHA-256, verifies the configured Developer ID Team ID, and runs Gatekeeper assessment before offering to open it.

To publish an update:

1. Bump `APP_VERSION` and `APP_BUILD` in `Scripts/build_app.sh`.
2. Keep the update signing private key outside the repository and common synced folders, and backed up securely. The matching public key is pinned in `Sources/VideoPlayer/UpdateManifest.swift`.
3. Store the PEM private key in Keychain for local release signing. Use Keychain Access to create a generic password item named `videoplayer-update-signing-private-key`, then paste the PEM private key into the password field.

4. Commit the release on a clean `main` branch.
5. Create a signed tag at the release commit, for example:

```sh
git tag -s "v0.1.8" -m "Release v0.1.8"
```

6. Configure `CODE_SIGN_IDENTITY`, `NOTARY_PROFILE`, `EXPECTED_DEVELOPER_TEAM_ID`, `UPDATE_SIGNING_KEYCHAIN_SERVICE`, and `RELEASE_APPROVAL` with the exact tag being published.
7. Log in with `gh auth login`.
8. Run:

```sh
export RELEASE_APPROVAL="v0.1.8"
./Scripts/publish_release.sh
```

The script builds `Build/Video Player.dmg`, creates a signed update manifest, uses a Keychain-backed update signing key by default, refuses file-based keys unless `ALLOW_FILE_UPDATE_SIGNING_KEY=1` is explicit, refuses dirty worktrees, refuses production publishing away from `main`, requires explicit `RELEASE_APPROVAL`, requires the release tag to exist at `HEAD`, refuses `ALLOW_UNNOTARIZED_RELEASE=1` on `main`, creates or updates a semver-style GitHub Release such as `v0.2.0`, and attaches the DMG, manifest, and release provenance.

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
