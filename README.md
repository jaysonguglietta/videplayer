# Video Player

A native macOS media player inspired by VLC: drag in media, build a playlist, play/pause, seek, boost volume, switch audio/subtitle tracks, load external subtitles, resume playback, open network streams, and go full screen.

## Highlights

- VLC codec engine support for MKV, MP4, AVI, WebM, FLV, FLAC, OGG, OPUS, and more.
- 10-second rewind and fast-forward controls.
- 200% volume boost with slider and mouse-wheel control over the player area.
- Embedded audio/subtitle track selectors for VLC-backed playback.
- Left-pane metadata inspector that shows file details before playback starts.
- LibVLC metadata parsing for embedded movie, TV, artwork, language, and track details.
- Recent files and saved library folders.
- External subtitle loading for SRT, ASS, SSA, and VTT files.
- Subtitle delay control.
- A-B loop markers for repeating a section.
- Chapter navigation for VLC-backed media.
- Frame screenshots saved to Pictures.
- Audio presets, audio delay, and audio output device selection for VLC-backed playback.
- Video adjustment panel for brightness, contrast, saturation, hue, and gamma.
- Mini player, floating picture-in-picture-style window, theater mode, hideable sidebar, and full screen.
- Playback resume per file or stream.
- Playlist, selected item, volume, and speed persistence.
- Network stream opening for HTTP, HTTPS, RTSP, and HLS-style URLs.
- On-screen HUD for seek, volume, speed, subtitle, and resume feedback.

## Controls

- Use the circular 10-second buttons or the left/right arrow keys to rewind and fast-forward.
- Move the volume slider up to 200%, or scroll the mouse wheel over the player area to adjust volume.
- Opened files are selected first so the inspector can show metadata; press Space, K, or double-click the row to start playback.
- Press Space or K to play/pause, J/L to seek, Up/Down for volume, M to mute, F for full screen, B to show or hide the sidebar, and [/] for previous/next playlist items.

## Format support

The app plays Apple-native formats in-app through AVFoundation, including MP4, M4V, MOV, MP3, M4A, AAC, WAV, AIFF, and CAF.

For VLC-like broad codec coverage and 200% volume boost, the app uses LibVLC. The build script downloads the pinned official VLC 3.0.23 macOS DMG, verifies its SHA-256 checksum, and bundles that runtime into the final app bundle. During development, the app can also use `/Applications/VLC.app` directly.

If VLC is not installed, `mpv` can also be used as a fallback external playback engine:

```sh
brew install mpv
```

When `mpv` is available at `/opt/homebrew/bin/mpv`, `/usr/local/bin/mpv`, or `/Applications/mpv.app/Contents/MacOS/mpv`, the app can use it for advanced formats if VLC is unavailable. `PATH` lookup is disabled by default; set `VIDEOPLAYER_ALLOW_PATH_MPV=1` only for trusted development shells.

## Documentation

- [User guide](docs/USER_GUIDE.md)
- [Development and packaging](docs/DEVELOPMENT.md)

## Run from source

```sh
swift run
```

## Build a macOS app bundle

```sh
chmod +x Scripts/build_app.sh
./Scripts/build_app.sh
open "Build/Video Player.app"
```

## Build a release DMG

```sh
./Scripts/build_release_dmg.sh
```

The release DMG is created at `Build/Video Player.dmg`.

## Updates and Licenses

Use Video Player > Check for Updates or Help > Check for Updates to look for the latest GitHub Release. The updater now requires a signed `video-player-update.json` manifest, verifies the manifest against the app's pinned public key, downloads the referenced `.dmg`, and verifies its SHA-256 before offering to open it.

To publish an update, log in with `gh auth login`, bump `APP_VERSION` and `APP_BUILD` in [Scripts/build_app.sh](Scripts/build_app.sh), configure Developer ID signing and notarization, then run:

```sh
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
./Scripts/publish_release.sh
```

Use Video Player > Open Source Licenses or Help > Open Source Licenses for license and open source software notices.

Video Player's application source code is released under the [MIT License](LICENSE). Bundled and optional media engines such as VLC/libVLC and mpv have their own upstream license terms.
