# Video Player

A native macOS media player inspired by VLC: drag in media, build a playlist, play/pause, seek, boost volume, switch audio/subtitle tracks, load external subtitles, resume playback, open network streams, and go full screen.

## Highlights

- VLC codec engine support for MKV, MP4, AVI, WebM, FLV, FLAC, OGG, OPUS, and more.
- 10-second rewind and fast-forward controls.
- 200% volume boost with slider and mouse-wheel control over the player area.
- Embedded audio/subtitle track selectors for VLC-backed playback.
- Left-pane metadata inspector that shows file details before playback starts.
- Recent files and saved library folders.
- External subtitle loading for SRT, ASS, SSA, and VTT files.
- Subtitle delay control.
- A-B loop markers for repeating a section.
- Frame screenshots saved to Pictures.
- Audio presets for flat, speech, bass, and night listening.
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

For VLC-like broad codec coverage and 200% volume boost, the app uses LibVLC. The build script bundles the VLC engine from `/Applications/VLC.app` into the final app bundle when VLC is installed on the build machine. During development, the app can also use `/Applications/VLC.app` directly.

If VLC is not installed, `mpv` can also be used as a fallback external playback engine:

```sh
brew install mpv
```

When `mpv` is available at `/opt/homebrew/bin/mpv`, `/usr/local/bin/mpv`, `/Applications/mpv.app/Contents/MacOS/mpv`, or in `PATH`, the app automatically uses it for advanced formats if VLC is unavailable.

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
