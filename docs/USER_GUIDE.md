# User Guide

## Opening Media

Use File > Open to replace the playlist, or File > Add to Playlist to append media. You can also drag files or folders onto the player. Supported local media includes MP4, M4V, MOV, MK4, MKV, AVI, WebM, FLV, WMV, MPEG, TS, MP3, M4A, AAC, WAV, AIFF, CAF, FLAC, OGG, and OPUS.

Use File > Open Network Stream for stream URLs such as HTTP, HTTPS, RTSP, or HLS playlists.

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
- [: previous playlist item
- ]: next playlist item

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

## Resume and Persistence

The app remembers playback position per file or stream. When reopening media with a saved position, it offers to resume or start over. It also restores the previous playlist, selected item, volume, and playback speed when the app opens.

## On-Screen HUD

The player briefly shows an on-screen HUD for common actions such as seeking, volume changes, speed changes, subtitle loading, and resume playback.
