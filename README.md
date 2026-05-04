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

## Controls

- Use the circular 10-second buttons or the left/right arrow keys to rewind and fast-forward.
- Move the volume slider up to 200%, or scroll the mouse wheel over the player area to adjust volume.
- Opened files are selected first so the inspector can show metadata; press Space, K, or double-click the row to start playback.
- Press Space or K to play/pause, J/L to seek, Up/Down for volume, M to mute, F for full screen, B to show or hide the sidebar, and [/] for previous/next playlist items.

## Format support

The default sold app plays Apple-native formats in-app through AVFoundation, including MP4, M4V, MOV, MP3, M4A, AAC, WAV, AIFF, and CAF. This default build is sandboxed and does not load third-party media engines.

For broad codec coverage, an advanced build can use a copy of VLC/libVLC that the user installed separately. This build mode is disabled by default; it must be created with `ENABLE_EXTERNAL_ENGINES=1`, users must enable external engines, and the engine must pass strict code-signature, Team ID, and Gatekeeper checks. The commercial DMG does not bundle VLC, libVLC, VLC plugins, mpv, FFmpeg, or any third-party media engine.

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

## Updates and Licenses

Use Video Player > Check for Updates or Help > Check for Updates to look for the latest GitHub Release. The updater requires a signed `video-player-update.json` manifest, verifies the manifest against the app's pinned public key, downloads the referenced `.dmg`, verifies its SHA-256, verifies the Developer ID Team ID, and runs Gatekeeper assessment before offering to open it.

To publish an update from your local Mac, log in with `gh auth login`, bump `APP_VERSION` and `APP_BUILD` in [Scripts/build_app.sh](Scripts/build_app.sh), keep the private update key outside the repo and common sync folders, configure Developer ID signing and notarization, commit on a clean `main`, create a signed release tag, then run:

```sh
chmod 700 "$HOME/.videoplayer-release"
chmod 600 "$HOME/.videoplayer-release/update-signing-private-key.pem"
git tag -s "v0.1.6" -m "Release v0.1.6"
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
export EXPECTED_DEVELOPER_TEAM_ID="TEAMID"
export UPDATE_SIGNING_PRIVATE_KEY="$HOME/.videoplayer-release/update-signing-private-key.pem"
./Scripts/publish_release.sh
```

Use Video Player > Open Source Licenses or Help > Open Source Licenses for license and open source software notices.

Video Player's application source code is released under the [MIT License](LICENSE). The distributed app does not bundle VLC/libVLC, mpv, FFmpeg, or other third-party media engines; optional user-installed integrations keep their own upstream license terms.
