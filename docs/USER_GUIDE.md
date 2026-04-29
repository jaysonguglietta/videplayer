# User Guide

## Opening Media

Use File > Open to replace the playlist, or File > Add to Playlist to append media. You can also drag files or folders onto the player. Supported local media includes MP4, M4V, MOV, MK4, MKV, AVI, WebM, FLV, WMV, MPEG, TS, MP3, M4A, AAC, WAV, AIFF, CAF, FLAC, OGG, and OPUS.

Use File > Open Network Stream for stream URLs such as HTTP, HTTPS, RTSP, or HLS playlists. Other URL schemes are rejected.

Opened media is selected in the left pane before playback starts. The inspector shows title, type, file size, duration, video dimensions, modified date, saved resume point, location, and LibVLC metadata such as show, season, episode, artwork, language, and track summaries when available. Press Space, K, the play button, or double-click the playlist row to start.

Use File > Open Recent to reload a recently played file or stream. Use File > Add Library Folder to save a folder, then File > Load Library Folders to rebuild the playlist from saved folders.

## Playback

The transport bar includes previous, 10-second rewind, play/pause, 10-second fast-forward, next, speed, volume, and full-screen controls.

Keyboard shortcuts:

- Space or K: play/pause
- Left arrow or J: rewind 10 seconds
- Right arrow or L: fast-forward 10 seconds
- Up arrow: volume up
- Down arrow: volume down
- M: mute
- F: full screen
- B: show or hide the sidebar
- [: previous playlist item
- ]: next playlist item

## View Modes

Use View > Toggle Sidebar to show or hide the playlist and inspector. Use View > Mini Player for a small floating player, View > Picture in Picture for a floating playback window, View > Theater Mode for a clean playback-focused view, or the full-screen button for macOS full screen.

Use View > Video Adjustments to change brightness, contrast, saturation, hue, and gamma for VLC-backed video. Use View > Reset Video Adjustments to return to the original picture.

## Volume Boost

The volume slider goes to 200%. Scroll the mouse wheel or trackpad over the player area to adjust volume without moving the pointer to the slider. VLC-backed playback supports amplification above 100%; AVFoundation playback is limited by macOS and caps audio output at 100%.

## Subtitles

Use File > Load Subtitle or the subtitle load button in the lower controls to add an SRT, ASS, SSA, or VTT file to the current VLC-backed playback session.

If a subtitle file with the same base name as the video is next to the media file, the app attempts to load it automatically. Example:

```text
Movie.mkv
Movie.srt
```

Use the subtitle selector to choose embedded or external subtitle tracks. Use the subtitle delay stepper to move subtitles earlier or later in 0.1-second increments.

## Audio Tracks

For media with multiple embedded audio tracks, use the audio track selector in the lower controls. This is especially useful for MKV files with multiple languages or commentary tracks.

Use the audio preset selector or Playback > Audio Preset for Flat, Speech Boost, Bass Boost, or Night Mode. Presets are applied through VLC's equalizer when VLC-backed playback is active.

Use the audio delay stepper or Playback > Audio Delay to sync audio earlier or later. Use Playback > Audio Output to choose a device when LibVLC reports available outputs.

## Chapters

Use Playback > Previous Chapter, Playback > Next Chapter, or Playback > Chapters to navigate chaptered media such as movies, concert videos, and discs.

## A-B Loop

Use Playback > Set Loop Start at the beginning of the section, then Playback > Set Loop End after it. Playback jumps back to A whenever it reaches B. Use Playback > Clear Loop to stop looping.

## Screenshots

Use Playback > Take Screenshot to save the current frame. Screenshots are written to:

```text
~/Pictures/Video Player Screenshots
```

## Resume and Persistence

The app remembers playback position per file or stream. When reopening media with a saved position, it offers to resume or start over. It also restores the previous playlist, selected item, volume, and playback speed when the app opens. Network stream credentials, query strings, and fragments are redacted before they are saved.

## On-Screen HUD

The player briefly shows an on-screen HUD for common actions such as seeking, volume changes, speed changes, subtitle loading, and resume playback.

## Updates and Licenses

Use Video Player > Check for Updates or Help > Check for Updates to check the GitHub repository releases. If a newer release with a signed update manifest is available, the app verifies the manifest, downloads the `.dmg`, verifies its SHA-256 checksum, and then offers to open it or reveal it in Finder.

Use Video Player > About Video Player for app details. Use Video Player > Open Source Licenses or Help > Open Source Licenses to view bundled/open source software notices for Video Player, VLC/libVLC, and optional mpv support.

Video Player's own app source code is MIT licensed. VLC/libVLC, mpv, and other upstream software keep their own license terms.
