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

Version 2.0 moves durable and independently testable responsibilities out of the main controller: `LibraryDatabase` owns SQLite storage, `LibraryScanService` owns cancellable folder enumeration, `PlaybackRoutePlanner` owns engine selection, `StreamCredentialStore` owns Keychain access, `SettingsWindowController` owns preferences, and `LibraryBrowserWindowController` owns indexed-library browsing. Continue extracting orchestration at these boundaries instead of adding new storage, DNS, or release logic directly to `PlayerViewController`.

Playlist import/export uses UTF-8 M3U/M3U8 text files. Imported local entries are resolved through the existing media extension filter, relative entries are resolved against the playlist file location, and imported network entries must pass `NetworkStreamValidator` before they are added. Skipped import entries should include line-level reasons.

Network stream validation resolves public hosts off the main thread before adding a stream and revalidates the stream immediately before playback. DNS results are pinned in memory for the session, and playback is blocked if a previously added stream resolves to a disjoint address set.

`PlaylistWorkflow` owns reusable playlist search, sort, export, path-resolution, and import-result helpers. Keep playlist behavior that can be tested without AppKit in this workflow layer, and leave `PlayerViewController` responsible for UI wiring, dialogs, and playback state coordination.

`AppLogger` writes a rotating diagnostic log to the user's Library Logs folder. The app exposes Video Player > Reveal Log File and Help > Reveal Log File. Log playback routing, codec decisions, external-engine validation, VLC/mpv startup, update checks, and verification failures before risky or blocking operations. `OperationTimeline` separately keeps a bounded in-memory timeline for playback startup, scans, and watchdog incidents; support bundles export it as `operation-timeline.txt`. Log writes redact stream credentials, query strings, URL fragments, home-folder paths, and `/Volumes` media paths before persistence. Security validation subprocesses have a 10-second timeout so `codesign` or `spctl` cannot leave the app indefinitely unresponsive.

Enterprise operations code is intentionally split into testable helpers:

- `EnterprisePolicy` reads managed preferences and exposes a snapshot used by privacy, stream, update, support, and external-engine flows.
- `PlaybackDiagnostics` builds support-ready playback and enterprise status reports without AppKit dependencies.
- `SupportBundleExporter` writes support reports, playback diagnostics, and optional redacted logs.
- `SupportBundleUploader` performs optional policy-configured multipart uploads after bundle export.
- `EnterpriseLicenseManager` imports license JSON files and verifies P-256 signatures when `VPEnterpriseLicensePublicKey` is configured.
- `EnterpriseActivationManager` creates offline activation request JSON files and removes local licenses.
- `ReleaseReadiness`, `MediaEngineDoctor`, `PlaybackEngineSetupAssistant`, `FleetDiagnostics`, `PlaybackRecovery`, `MDMProfileBuilder`, and `LibraryCatalog` keep advanced admin checks testable outside AppKit.
- `SubtitlePreferences` owns default subtitle language/mode/style behavior. VLC subtitle style presets are converted to LibVLC startup arguments, so style changes apply when a VLC codec engine is created.
- `PlaybackQualityPreset` combines video adjustments and audio presets into named user-facing options without adding more global state.

`PlaylistWorkflowSmokeTests` covers playlist behavior below the UI. `VideoPlayerUISmokeTests` instantiates the real AppKit controller and imports a temporary M3U8 containing MP4, MKV, and stream entries before exercising search, sort, metadata-control accessibility, and sidebar state. Manual QA should still exercise the built app with decodable media, authenticated streams, and mixed-result M3U8 files before release.

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
codesign -dv /Applications/VLC.app 2>&1 | grep TeamIdentifier
export ENABLE_EXTERNAL_ENGINES=1
export TRUSTED_EXTERNAL_ENGINE_TEAM_IDS="TEAMID"
./Scripts/build_release_dmg.sh
```

`TRUSTED_EXTERNAL_ENGINE_TEAM_IDS` is required whenever `ENABLE_EXTERNAL_ENGINES=1` unless the build is an explicit debug-only unverified-engine test. An empty trust list produces an app that can see VLC/mpv but must reject it at runtime.

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
export ENTERPRISE_LICENSE_PUBLIC_KEY="base64-x963-p256-public-key-if-used"
```

`Scripts/build_app.sh` signs the app with hardened runtime and uses the sandboxed `Packaging/VideoPlayer.entitlements` by default. The advanced external-engine entitlement also keeps App Sandbox enabled while adding `com.apple.security.cs.disable-library-validation` for controlled VLC/mpv loading. `Scripts/build_release_dmg.sh` signs the DMG, submits it to `notarytool`, staples the notarization ticket, and validates the staple. Direct-distribution builds require Developer ID signing and notarization by default. Use `DEVELOPMENT_BUILD=1` only for local ad-hoc testing.

## Update Checks

The in-app updater checks:

```text
https://api.github.com/repos/jaysonguglietta/videplayer/releases?per_page=20
```

It ignores drafts, applies the effective Stable/Beta prerelease policy, selects the newest applicable release by version, then compares that tag against `CFBundleShortVersionString`. If the installed app is newer than the newest applicable release, the app reports that no newer update is available and prompts you to publish the installed version or later. For newer releases, it downloads the release's `video-player-update.json` manifest, verifies that manifest against the public key pinned in `UpdateManifest.swift`, downloads the signed manifest's `.dmg`, verifies the DMG's SHA-256, verifies the configured Developer ID Team ID, and runs Gatekeeper assessment before offering to open it.

To publish an update:

1. Bump `APP_VERSION` and `APP_BUILD` in `Scripts/build_app.sh`.
2. Keep the update signing private key outside the repository and common synced folders, and backed up securely. The matching public key is pinned in `Sources/VideoPlayer/UpdateManifest.swift`.
3. Store the PEM private key in Keychain for local release signing. Use Keychain Access to create a generic password item named `videoplayer-update-signing-private-key`, then paste the PEM private key into the password field.

4. Commit the release on a clean `main` branch.
5. Create a signed tag at the release commit, for example:

```sh
git tag -s "v2.0" -m "Release v2.0"
```

6. Configure `CODE_SIGN_IDENTITY`, `NOTARY_PROFILE`, `EXPECTED_DEVELOPER_TEAM_ID`, `UPDATE_SIGNING_KEYCHAIN_SERVICE`, and `RELEASE_APPROVAL` with the exact tag being published.
7. Log in with `gh auth login`.
8. Run:

```sh
export RELEASE_APPROVAL="v2.0"
./Scripts/publish_release.sh
```

The script builds `Build/Video Player.dmg`, creates a signed update manifest, uses a Keychain-backed update signing key by default, refuses file-based keys unless `ALLOW_FILE_UPDATE_SIGNING_KEY=1` is explicit, refuses dirty worktrees, refuses production publishing away from `main`, requires explicit `RELEASE_APPROVAL`, requires the release tag to exist at `HEAD`, refuses `ALLOW_UNNOTARIZED_RELEASE=1` on `main`, creates or updates a versioned GitHub Release such as `v2.0`, and attaches the DMG, manifest, and release provenance.

## State Storage

`PlaybackStateStore` is the privacy gate over two storage layers. Lightweight preferences, current playlist, recent items, stream bookmarks, and security-scoped library-folder bookmarks use `UserDefaults`. Indexed media, favorites/watched/tags records, resume positions, and per-media playback profiles use `LibraryDatabase`, a versioned SQLite database in Application Support with WAL enabled. Version 2.0 migrates legacy library records and positions on first use. History saving is off by default; disabling or clearing it removes privacy-sensitive defaults, bookmarks, SQLite rows, saved metadata, and persisted resume/profile data.

`StreamCredentialStore` keeps optional HTTPS/RTSPS credentials in the macOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Persisted URLs never contain credentials, query strings, or fragments. Credentials are attached only to the engine URL at playback time.

## Network Stream Policy

`NetworkStreamValidator` accepts only HTTP, HTTPS, RTSP, and RTSPS. Loopback, link-local, multicast, RFC1918, CGNAT, benchmark ranges, `.local`, `localhost`, single-label hosts, and DNS names resolving to private/local addresses are blocked by default to reduce client-side SSRF and local-network probing risk. DNS checks run off the main UI path with a short timeout and fail closed when private network streams are disabled. A stream must resolve to the same public address set between playlist admission and playback revalidation. Users can enable Privacy > Allow Private Network Streams for trusted LAN cameras or local streams.

Managed deployments can also set `EnterpriseAllowedStreamHostSuffixes` to restrict stream playback to approved host suffixes. This restriction is applied before DNS validation and applies to Open Network Stream, playlist import, and playback revalidation.

## Enterprise Features

See [Enterprise deployment guide](ENTERPRISE_DEPLOYMENT.md) for the admin-facing workflow. In code:

- Help > Enterprise Status calls `PlaybackDiagnostics.enterpriseStatusReport`.
- Help > Release Readiness calls `ReleaseReadiness.report`.
- Help > Playback Diagnostics calls `PlaybackDiagnostics.report` for the selected or current media item.
- Help > Playback Engine Doctor calls `MediaEngineDoctor.report`.
- Help > Playback Engine Setup Assistant calls `PlaybackEngineSetupAssistant.report`.
- Help > Export Fleet Diagnostics JSON calls `FleetDiagnostics.document` and `FleetDiagnostics.jsonData`.
- Help > Recovery Report calls `PlaybackRecovery.state`.
- Help > Export MDM Policy Profile calls `MDMProfileBuilder.mobileconfig`.
- Help > Export Support Bundle calls `SupportBundleExporter.export`.
- Optional support uploads call `SupportBundleUploader.upload` only when `EnterpriseSupportUploadURL` is configured. Upload endpoints must be HTTPS, have no embedded credentials, match `EnterpriseSupportUploadHostSuffixes` when configured, and resolve to public addresses. `EnterpriseSupportUploadTokenKeychainService` lets managed deployments add an `Authorization: Bearer ...` header without storing the token in preferences.
- Help > License Status and Help > Import Enterprise License call `EnterpriseLicenseManager`.
- Help > Create License Activation Request and Help > Deactivate Enterprise License call `EnterpriseActivationManager`.
- File > Manage Library Folders uses `PlaybackStateStore` and remains privacy-aware because saved folders are treated as playback history.
- File > Library Report and library curation actions use `LibraryCatalog` and persisted `MediaLibraryRecord` values.
- The inspector's Save Metadata + Poster button uses `MediaMetadataCache` to write app-owned JSON and poster PNG files under Application Support > Video Player > Saved Metadata. It is gated by the saved playback history preference because saved metadata can include local file paths or stream identities.

Build-time license verification is optional for informational deployments. Set `ENTERPRISE_LICENSE_PUBLIC_KEY` when packaging a customer build that should cryptographically verify offline license files. Without a configured public key, imported licenses are displayed as unverified operational records and are not treated as usable when `EnterpriseRequireLicense=true`.

`EnterpriseUpdateChannel` accepts `github`, `github-stable`, `github-beta`, `sparkle`, or `mdm`. Stable GitHub channels exclude prereleases; the beta channel includes them but retains identical manifest, checksum, Developer ID, and Gatekeeper verification. `sparkle` is intentionally readiness-only rather than a full framework migration.

Broad codec support remains the largest intentionally separate subsystem. See [Codec service architecture](CODEC_SERVICE_ARCHITECTURE.md) for the signed, notarized, out-of-process helper design and the legal/supply-chain gates required before bundling a codec runtime.

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
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme VideoPlayer -destination platform=macOS
DEVELOPMENT_BUILD=1 ./Scripts/build_app.sh
DEVELOPMENT_BUILD=1 ./Scripts/build_release_dmg.sh
plutil -lint "Build/Video Player.app/Contents/Info.plist"
```

The Xcode test command is authoritative on macOS because it runs both the unit/integration target and the AppKit UI smoke target. A standalone Command Line Tools Swift installation may not expose XCTest correctly for `swift test`.
