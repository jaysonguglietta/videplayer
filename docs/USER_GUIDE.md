# User Guide

## Opening Media

Use the Open Media action in the empty player, File > Open to replace the playlist, or File > Add to Playlist to append media. You can also drag files or folders onto the player. Apple-native playback supports MP4, M4V, MOV, MP3, M4A, AAC, WAV, AIFF, and CAF. Some MP4 files contain Dolby Vision or HEVC/x265 video that macOS can expose as audio-only; the app detects those codecs before playback and uses a trusted external engine when available. Additional formats such as MKV, AVI, WebM, FLV, FLAC, OGG, and OPUS require an advanced external-engine build when the user has VLC or mpv installed separately and trusted.

Use Open Stream in the empty player or File > Open Network Stream for public stream URLs such as HTTP, HTTPS, RTSP, or HLS playlists. Other URL schemes are rejected, and private/local network targets, including DNS names that resolve to private/local addresses, are blocked by default. The app checks public stream hosts before adding them to the playlist and again before playback. Use Privacy > Allow Private Network Streams only for trusted LAN cameras or local streams.

The stream dialog accepts an optional username and password for HTTPS or RTSPS sources. Keep Save credential in Keychain enabled to store the credential for that host with device-only Keychain protection, or turn it off to use the credential for the current app session only. Credentials are added only to the playback request; embedded URL credentials are rejected and playlists, history, logs, and support reports retain the credential-free URL.

When playback history is enabled, use File > Save Current Stream Bookmark to save the selected stream and File > Open Stream Bookmark to reopen or remove saved stream sources. Stream bookmarks redact credentials, query strings, and fragments before persistence.

Opened media is selected in the left pane before playback starts. The inspector shows title, type, file size, duration, video dimensions, modified date, saved resume point, location, saved metadata/poster status, and extra metadata from a user-installed VLC copy when available. Press Space, K, the play button, or double-click the playlist row to start.

Use Save Metadata + Poster in the inspector to persist the selected item's inspected metadata and best available poster image. The app saves local metadata JSON and embedded artwork or a frame poster under Application Support > Video Player > Saved Metadata. The inspector shows the saved poster and provides choose/replace and remove buttons for manual artwork. Imported poster files are size-limited and normalized to PNG. If no poster can be extracted, the metadata still saves and the HUD reports that the poster is unavailable. These actions require playback history to be enabled so users who turn off history do not accidentally persist media paths or stream references.

Use File > Open Recent to reload a recently played file or stream when playback history is enabled. Use File > Add Library Folder to save a folder, then File > Load Library Folders to rebuild the playlist from saved folders. Use File > Manage Library Folders to review saved folders, rescan all folders, remove one folder, or remove all saved folder references. Saved folders require playback history to be enabled and are not persisted when history is off or disabled by policy.

Library scans run in the background, report the number of discovered files, and can be cancelled from Manage Library Folders. Use File > Browse Media Library to open the indexed-library window without replacing the current playlist. Search by title, type, or location, or filter for Continue Watching, Favorites, Unwatched, Streams, or Missing Files. Double-click a result or use Open Selected to send it through the normal playback route.

Use File > Toggle Favorite, Mark Watched, Mark Unwatched, and Set Tags to curate a playlist/library. Use File > Library Report to summarize item counts, streams, missing local files, favorites, watched items, tags, quality buckets, duplicate/version groups, and TV episode groups.

Use the search field above the playlist to filter by title, file extension, path, or stream URL. Use the sort menu to keep the current order or sort by title, media type, or location. The inspector tells you when nothing matches the current search.

Use File > Import Playlist, File > Open, or drag-and-drop to load `.m3u` or `.m3u8` playlists. Relative paths are resolved next to the playlist file, local entries must point to supported media, and network entries go through the same public/private stream checks as Open Network Stream. Use File > Export Playlist to save the current playlist as `.m3u8`.

When an imported playlist has skipped entries, the app shows the line number, entry, and reason for each skipped line so you can fix missing files, unsupported extensions, or blocked stream URLs.

Drag playlist rows to reorder them when the sort menu is set to current order and no search filter is active. Select one or more rows and use the minus button, File > Remove Selected from Playlist, or the Delete key to remove them from the playlist. Use the trash button to clear the current playlist. Clearing or removing playlist rows never deletes media files from disk.

The playlist, media inspector, transport controls, volume and speed controls, audio controls, subtitle controls, video adjustment sliders, and network stream field expose labels and help text for VoiceOver.

## Playback

The transport bar includes previous, 10-second rewind, play/pause, 10-second fast-forward, next, speed, volume, sidebar, and full-screen controls. Audio and subtitle tools sit in separate rows below the transport controls so they remain readable when the sidebar is open.

Keyboard shortcuts:

- Space or K: play/pause
- Left arrow or J: rewind 10 seconds
- Right arrow or L: fast-forward 10 seconds
- Up arrow: volume up
- Down arrow: volume down
- M: mute
- F: full screen
- B: show or hide the sidebar
- Delete: remove selected playlist rows
- [: previous playlist item
- ]: next playlist item

## View Modes

Use View > Toggle Sidebar to show or hide the playlist and inspector. Use View > Mini Player for a small floating player, View > Picture in Picture for a floating playback window, View > Theater Mode for a clean playback-focused view, or the full-screen button for macOS full screen.

Use Playback > Enable External VLC/mpv Engines to opt in to separately installed media engines when the app was built as an advanced external-engine variant. Default commercial builds keep this option unavailable. Advanced builds only use external engines when strict code-signature, Team ID, and Gatekeeper checks trust the engine. If a file requires an external engine for video, the app can prompt you to enable trusted external playback before it starts instead of repeatedly trying Apple-native playback.

If a local file starts with sound but no picture under Apple-native playback, Video Player stops the native attempt and either falls back to a trusted VLC/mpv engine or shows a codec message explaining that the current build cannot render that video stream.

Use View > Video Adjustments to change brightness, contrast, saturation, hue, and gamma for video backed by a trusted user-installed VLC copy. Use View > Reset Video Adjustments to return to the original picture. Use Playback > Quality Preset to apply Neutral, Cinema, Bright Room, Vivid, or Low Light presets that combine useful picture and audio settings.

Use Playback > Playback Profile to save media-specific speed, quality, audio preset, audio delay, and subtitle delay values. The profile is applied automatically when that item is opened again and can be removed without changing global playback defaults.

Use Help > Playback Diagnostics when a file plays audio-only, fails to start, or appears to need VLC/mpv. The diagnostic report shows the selected media item, native playback assessment, detected video codecs, external-engine availability, enterprise policy, license status, stream DNS details, and recommended next action.

Use Help > Playback Engine Doctor to inspect VLC/libVLC and mpv candidates. It shows whether each engine path exists, is readable/executable, passes trust checks, and reports its Team ID when available.

Use Help > Playback Engine Setup Assistant when advanced codec playback is not working. It combines the engine doctor output with build configuration and gives the next setup step, including the Team ID build command when an installed engine exposes one.

## Volume Boost

The volume slider goes to 200%. Scroll the mouse wheel or trackpad over the player area to adjust volume without moving the pointer to the slider. Playback through a user-installed VLC copy supports amplification above 100%; AVFoundation playback is limited by macOS and caps audio output at 100%.

## Subtitles

Use File > Load Subtitle or the subtitle load button in the lower controls to add an SRT, ASS, SSA, or VTT file to the current session when playback is using a user-installed VLC copy.

If a subtitle file with the same base name as the video is next to the media file, the app attempts to load it automatically. Example:

```text
Movie.mkv
Movie.srt
```

Use the subtitle selector to choose embedded or external subtitle tracks. Use the subtitle delay stepper to move subtitles earlier or later in 0.1-second increments.

Use Playback > Subtitle Center to choose the default subtitle mode, preferred language, and style preset. Track selection preferences apply once per opened item so manual subtitle choices stay in place. Style presets are passed to VLC when its codec engine is created; reopen VLC-backed playback if changing the style while VLC is already active.

## Audio Tracks

For media with multiple embedded audio tracks, use the audio track selector in the lower controls. This is especially useful for MKV files with multiple languages or commentary tracks.

Use the audio preset selector or Playback > Audio Preset for Flat, Speech Boost, Bass Boost, or Night Mode. Presets are applied through VLC's equalizer when playback is using a user-installed VLC copy.

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

Privacy > Save Playback History is off by default. When you enable it, the app remembers playback position per file or stream. When reopening media with a saved position, it offers to resume or start over. It also restores the previous playlist, selected item, saved library folders, volume, and playback speed when the app opens. Indexed media, curation records, resume positions, and playback profiles use the app's SQLite library; lightweight UI preferences remain in UserDefaults. Saved folders use security-scoped bookmarks so the sandbox can regain user-approved access. Network stream credentials, query strings, and fragments are never stored in the library URL.

Use Privacy > Save Playback History to turn history saving on or off. When it is off, playlists, recent media, resume positions, and saved library folders are not persisted. Use Privacy > Clear History on Quit to clear playback history when the app closes. Use Privacy > Clear All Playback History to remove playlist, recent media, resume positions, and saved library folders immediately.

Use Video Player > Settings or Command-, for one place to manage playback defaults, subtitle defaults, history/privacy, private streams, trusted external engines, saved metadata, stored stream credentials, Stable/Beta updates, and effective enterprise policy. Controls locked by MDM are disabled.

Managed enterprise policy can disable playback history, force clear-on-quit, block private/local streams, disable external VLC/mpv engines, disable update checks, restrict stream hosts, and control support bundle log export. When a setting is managed, the menu item is disabled or the action reports that it is controlled by policy.

Kiosk policy can disable file browsing, playlist import/export, manual stream entry, and library edits. In kiosk mode, administrators can provide a managed playlist URL so the app opens to approved content.

## On-Screen HUD

The player briefly shows an on-screen HUD for common actions such as seeking, volume changes, speed changes, subtitle loading, and resume playback.

## Updates and Licenses

Use Video Player > Check for Updates or Help > Check for Updates to check the GitHub repository releases. Choose Stable or Beta in Settings. Stable excludes GitHub prereleases; Beta includes them, but every update still requires the pinned signed manifest, SHA-256 match, expected Developer ID Team ID, and Gatekeeper approval before the DMG can be opened. If the installed build is newer than GitHub's newest applicable release, the app reports that no newer update is available.

Use Video Player > About Video Player for app details. Use Video Player > Open Source Licenses or Help > Open Source Licenses to view notices for Video Player and optional external VLC/mpv integrations.

Use Video Player > Reveal Log File or Help > Reveal Log File when playback freezes, an update check fails, or an external engine is rejected. The log records the playback route, detected codecs, trusted-engine validation commands, VLC/mpv startup, update-check results, and verification failures. Logs redact stream credentials, query strings, URL fragments, home-folder paths, and `/Volumes` media paths before they are written.

Use Help > Export Support Bundle to create a support folder with a support report, playback diagnostics, an operation timeline, and optionally the app log. Support bundles redact home-folder paths, volume paths, stream credentials, and common URL tokens by default unless enterprise policy turns redaction off. If your organization configures support uploads, the endpoint must be public HTTPS, match the managed upload host policy when present, pass DNS safety checks, and use a Keychain-backed bearer token when configured.

Use Help > Recovery Report after a force quit or freeze to see whether the previous session ended cleanly, the last playback item, and the last watchdog warning. Use Help > Export Fleet Diagnostics JSON to save a machine-readable report for help desk, inventory, or MDM workflows.

Use Help > Release Readiness to check whether the current build is ready for customer distribution. Use Help > Export MDM Policy Profile to save a `.mobileconfig` profile for managed deployments. Use Help > Enterprise Status to review the installed version, update readiness, trusted external-engine configuration, active managed preferences, and enterprise license status. Use Help > License Status or Help > Import Enterprise License when your organization provides a license JSON file. Use Help > Create License Activation Request when support asks for an offline activation request.

Use Help > Keyboard Shortcuts and Accessibility to review keyboard workflows and support-facing accessibility notes.

Video Player's own app source code is MIT licensed. The default distributed app is sandboxed and does not bundle or load VLC/libVLC, mpv, FFmpeg, or other third-party media engines. Optional advanced user-installed integrations keep their own upstream license terms.
