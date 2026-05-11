# Video Player

A native macOS media player: drag in media, build a playlist, play/pause, seek, boost volume, switch audio/subtitle tracks, load external subtitles, resume playback, open network streams, and go full screen.

## Highlights

- Default commercial builds are sandboxed, native-only, and avoid loading third-party media engines.
- Optional advanced builds can enable user-installed VLC/libVLC or mpv support for MKV, AVI, WebM, FLV, FLAC, OGG, OPUS, and more.
- External VLC/mpv engines are opt-in and must pass strict code-signature, configured Team ID, and Gatekeeper checks.
- 10-second rewind and fast-forward controls.
- 200% volume boost with slider and mouse-wheel control over the player area.
- Embedded audio/subtitle track selectors when using a user-installed VLC/libVLC engine.
- Left-pane metadata inspector that shows file details before playback starts.
- Optional user-installed LibVLC metadata parsing for embedded movie, TV, artwork, language, and track details.
- Recent files and saved library folders when playback history is enabled.
- External subtitle loading for SRT, ASS, SSA, and VTT files.
- Subtitle delay control.
- A-B loop markers for repeating a section.
- Chapter navigation when supported by the active media engine.
- Frame screenshots saved to Pictures.
- Audio presets, audio delay, and audio output device selection when using a user-installed VLC/libVLC engine.
- Video adjustment panel for brightness, contrast, saturation, hue, and gamma.
- Mini player, floating picture-in-picture-style window, theater mode, hideable sidebar, and full screen.
- Playback resume per file or stream.
- Volume and speed persistence, with playlist/history persistence available as an opt-in privacy setting.
- Network stream opening for public HTTP, HTTPS, RTSP, and HLS-style URLs; private/local targets and DNS names resolving to private/local addresses are blocked by default.
- Privacy controls for enabling saved playback history, clearing history on quit, and clearing all history.
- On-screen HUD for seek, volume, speed, subtitle, and resume feedback.
- VoiceOver-friendly labels and help text for the playlist, inspector, transport, volume, speed, audio, subtitle, and adjustment controls.

## Controls

- On first run, the player area offers Open Media and Open Stream actions, and it also accepts drag-and-drop files or folders.
- Use the sidebar search and sort controls to organize the playlist by title, media type, location, or the current order.
- Import or export portable M3U/M3U8 playlist files from the File menu.
- Drag playlist rows to reorder them when using current-order sorting, or remove selected rows with the minus button or Delete key.
- Use the circular 10-second buttons or the left/right arrow keys to rewind and fast-forward.
- Move the volume slider up to 200%, or scroll the mouse wheel over the player area to adjust volume.
- Audio and subtitle tools are split into separate lower control rows so the window stays usable when the sidebar is visible.
- Opened files are selected first so the inspector can show metadata; press Space, K, or double-click the row to start playback.
- Clearing the playlist asks for confirmation and never deletes media files from disk.
- Press Space or K to play/pause, J/L to seek, Up/Down for volume, M to mute, F for full screen, B to show or hide the sidebar, and [/] for previous/next playlist items.

## Format support

The default sold app plays Apple-native formats in-app through AVFoundation, including MP4, M4V, MOV, MP3, M4A, AAC, WAV, AIFF, and CAF. This default build is sandboxed and does not load third-party media engines. Some MP4 files still contain advanced video such as Dolby Vision or HEVC/x265; the app inspects local video sample entries before playback so those files can be routed to a trusted external engine when available instead of silently playing audio-only.

For broad codec coverage, an advanced build can use a copy of VLC/libVLC that the user installed separately. This build mode is disabled by default; it must be created with `ENABLE_EXTERNAL_ENGINES=1`, users must enable external engines, and the engine must pass strict code-signature, Team ID, and Gatekeeper checks. Non-Apple-native containers such as MKV, WebM, AVI, and FLV require an advanced trusted external-engine build rather than a doomed AVFoundation fallback. The commercial DMG does not bundle VLC, libVLC, VLC plugins, mpv, FFmpeg, or any third-party media engine.

If VLC is not installed, `mpv` can also be used as a fallback external playback engine:

```sh
brew install mpv
```

When `mpv` is installed separately by the user at `/opt/homebrew/bin/mpv`, `/usr/local/bin/mpv`, or `/Applications/mpv.app/Contents/MacOS/mpv`, an advanced external-engine build can use it for advanced formats if VLC is unavailable and trusted external engines are enabled. `PATH` lookup and unverified-engine loading are compiled as debug-only development overrides and are not honored by release builds.

## Documentation

- [User guide](docs/USER_GUIDE.md)
- [Development and packaging](docs/DEVELOPMENT.md)
- [Commercial distribution checklist](docs/COMMERCIAL_DISTRIBUTION.md)

## Run from source

```sh
swift run
```

## Build a macOS app bundle

```sh
chmod +x Scripts/build_app.sh
DEVELOPMENT_BUILD=1 ./Scripts/build_app.sh
open "Build/Video Player.app"
```

## Build a release DMG

```sh
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
export EXPECTED_DEVELOPER_TEAM_ID="TEAMID"
./Scripts/build_release_dmg.sh
```

The release DMG is created at `Build/Video Player.dmg`.

To build the advanced external-engine variant instead of the sandboxed native-only default, also set `ENABLE_EXTERNAL_ENGINES=1` and `TRUSTED_EXTERNAL_ENGINE_TEAM_IDS` to the exact Team IDs you intend to trust.

For local QA only, debug development builds can set `BUILD_CONFIGURATION=debug` and `ALLOW_UNVERIFIED_EXTERNAL_ENGINES=1` to test playback against a known local VLC copy when macOS signature validation is failing. Do not use that override for release, notarized, or customer builds.

## Updates and Licenses

Use Video Player > Check for Updates or Help > Check for Updates to look for the newest published GitHub Release by version. If the installed build is newer than the newest published release, the app reports that no newer update is available and tells you to publish the current version. For newer releases, the updater requires a signed `video-player-update.json` manifest, verifies the manifest against the app's pinned public key, downloads the referenced `.dmg`, verifies its SHA-256, verifies the Developer ID Team ID, and runs Gatekeeper assessment before offering to open it.

To publish an update from your local Mac, log in with `gh auth login`, bump `APP_VERSION` and `APP_BUILD` in [Scripts/build_app.sh](Scripts/build_app.sh), store the private update key in Keychain as a generic password named `videoplayer-update-signing-private-key`, configure Developer ID signing and notarization, commit on a clean `main`, create a signed release tag, then run:

```sh
git tag -s "v0.1.8" -m "Release v0.1.8"
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
export EXPECTED_DEVELOPER_TEAM_ID="TEAMID"
export UPDATE_SIGNING_KEYCHAIN_SERVICE="videoplayer-update-signing-private-key"
export RELEASE_APPROVAL="v0.1.8"
./Scripts/publish_release.sh
```

Use Video Player > Reveal Log File or Help > Reveal Log File to open the persistent diagnostic log. The log records app launch, update checks, playback routing, codec detection, trusted VLC/mpv validation, and external-engine startup/failure details.

Video Player's application source code is released under the [MIT License](LICENSE). The distributed app does not bundle VLC/libVLC, mpv, FFmpeg, or other third-party media engines; optional user-installed integrations keep their own upstream license terms.
