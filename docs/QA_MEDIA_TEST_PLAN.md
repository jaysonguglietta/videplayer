# QA Media Test Plan

Use this plan before publishing a customer release or when changing playback routing, external engine trust, playlist import, diagnostics, or support bundle behavior.

## Test Matrix

| Area | Test Media or Input | Expected Result |
| --- | --- | --- |
| Apple-native video | MP4/H.264 with AAC audio | Plays in-app with AVFoundation, timeline updates, screenshot works. |
| HEVC/x265 MP4 | MP4 with `hvc1` or `hev1` sample entry | Prefers trusted external engine when available; native fallback does not hang. |
| Dolby Vision MP4 | MP4 with `dvh1` or `dvhe` sample entry | Requires trusted external engine and shows a clear diagnostic if unavailable. |
| Non-native container | MKV, WebM, AVI, FLV | Requires advanced trusted external-engine build. |
| Audio-only | MP3, M4A, FLAC, OGG, OPUS | Native formats play in-app; non-native audio requires trusted external engine. |
| Subtitles | Matching `.srt`, manually loaded `.vtt` | Sidecar auto-loads under VLC; manual load reports success/failure. |
| Subtitle Center | Automatic, preferred language, forced only, off, style presets | Preference is saved; matching tracks auto-select once per item; style applies when VLC engine is created. |
| Quality presets | Neutral, Cinema, Bright Room, Vivid, Low Light | Preset applies the expected video adjustments and audio preset without breaking manual controls. |
| Playlist import | M3U8 with valid local files, missing files, unsupported entries, public streams, blocked streams | Imports valid entries and shows per-line skipped results. |
| Indexed library | Saved folders with favorites, resume points, streams, and a removed file | Search and each library filter return the expected SQLite-backed results; opening a result uses normal playback routing. |
| Library scan | Large folder, inaccessible folder, cancellation | UI remains responsive, progress updates, caps are enforced, and cancellation leaves the previous playlist usable. |
| Network streams | HTTPS/HLS, RTSP, private IP, localhost, `.local`, DNS to private IP | Public streams pass; private/local targets are blocked unless explicitly allowed. |
| Stream bookmarks | Save current public stream, reopen, remove | Bookmarks are available only when history saving is enabled and persisted URLs are redacted. |
| Authenticated stream | HTTPS/RTSPS with session-only and saved credentials | URL is stored without credentials; saved credential is available after relaunch; Remove Stream Credentials deletes it. |
| Playback profile | Save custom speed/preset/audio/subtitle delays for one item | Profile reapplies only to that item and Remove Profile restores global defaults on the next open. |
| Metadata poster | Auto poster, manually chosen image, oversized image, remove | Preview updates, valid image is normalized, oversized input is rejected, and remove clears the cached poster. |
| Enterprise host allow-list | Stream outside `EnterpriseAllowedStreamHostSuffixes` | Stream is rejected even if it is public. |
| Support bundle | Export with logs, export without logs, policy-blocked logs | Bundle includes expected files and redacts paths/tokens by default. |
| Support upload | Policy-configured HTTPS upload endpoint | App offers upload after export only for HTTPS public endpoints; HTTP, embedded credentials, hosts outside `EnterpriseSupportUploadHostSuffixes`, private literal hosts, and private DNS results are rejected. Authenticated uploads use a Keychain-backed bearer token when configured. |
| License status | No license, unsigned license, signed license, expired license | Help > License Status reports the correct state. |
| Activation request | License key and requester email | App writes a JSON activation request with trimmed input and machine hash. |
| Managed policy | Force disable history, private streams, external engines, update checks | Menus are disabled or actions are blocked with clear feedback. |
| Kiosk mode | `EnterpriseKioskModeEnabled=true` with and without playlist URL | File browsing, stream entry, playlist import/export, and library edits are blocked; managed playlist loads when configured. |
| MDM profile export | Help > Export MDM Policy Profile | `.mobileconfig` contains Video Player managed preference keys. |
| Release readiness | Help > Release Readiness | Report shows pass/warn/fail status for signing, Team ID, update, license, Sparkle, and support redaction readiness. |
| Engine doctor | Help > Playback Engine Doctor | Report shows VLC/mpv candidate paths and why each is accepted/rejected. |
| Engine setup assistant | Help > Playback Engine Setup Assistant | Report gives the next setup step and build command when Team IDs are discoverable. |
| Fleet diagnostics | Help > Export Fleet Diagnostics JSON | JSON contains app/build state, policy, library summary, release readiness, recovery state, and subtitle preferences. |
| Recovery report | Help > Recovery Report after clean quit and force quit | Report correctly distinguishes clean and unclean previous sessions. |
| Library curation | Favorite, watched/unwatched, tags, report | Metadata and library report reflect persisted curation state, quality buckets, TV groups, and version groups when history is enabled. |
| Accessibility | Keyboard-only playback, playlist selection, delete, diagnostics dialogs | Core workflows work without a mouse and controls expose meaningful labels. |

## Manual Release Pass

1. Build the default sandboxed app:

```sh
DEVELOPMENT_BUILD=1 ./Scripts/build_app.sh
```

2. Open the built app and run through:

- Empty state Open Media and Open Stream.
- Drag-and-drop files and folders.
- Playlist search, sort, drag reorder, multi-select delete, and export.
- File > Manage Library Folders with history on and with history off.
- Cancel a running folder scan and use File > Browse Media Library with every filter.
- Save and remove a per-media Playback Profile, then reopen the item.
- Choose, replace, and remove an inspector poster.
- Open an HTTPS/RTSPS credentialed stream with session-only and Keychain-backed credentials.
- Change Settings on each tab and verify MDM-managed controls are disabled.
- Help > Playback Diagnostics with no selection, native MP4, HEVC/x265 MP4, and MKV.
- Help > Playback Engine Doctor with no external engines and with trusted VLC/mpv when available.
- Help > Playback Engine Setup Assistant with no engine, rejected engine, and trusted engine states.
- Help > Release Readiness.
- Help > Export Fleet Diagnostics JSON and verify valid JSON.
- Help > Recovery Report after a normal quit and after force quitting a debug build.
- Help > Export MDM Policy Profile.
- Help > Export Support Bundle with logs, without logs, and with policy upload endpoint configured.
- Support upload policy with HTTP, embedded credentials, host outside the allow-list, private host, private DNS result, missing Keychain token, and valid authenticated public HTTPS endpoint.
- Help > Enterprise Status, License Status, Create License Activation Request, and Deactivate Enterprise License.
- File > Toggle Favorite, Mark Watched, Mark Unwatched, Set Tags, and Library Report.
- File > Save Current Stream Bookmark and File > Open Stream Bookmark with a public stream.
- Playback > Subtitle Center and Playback > Quality Preset.
- Kiosk mode policy with a managed playlist.

3. Build the advanced external-engine debug QA app only when testing local VLC/mpv behavior:

```sh
DEVELOPMENT_BUILD=1 \
BUILD_CONFIGURATION=debug \
ENABLE_EXTERNAL_ENGINES=1 \
TRUSTED_EXTERNAL_ENGINE_TEAM_IDS="TEAMID" \
ALLOW_UNVERIFIED_EXTERNAL_ENGINES=1 \
./Scripts/build_app.sh
```

4. Confirm production release protections are still enforced:

- Release builds do not honor unverified external engine overrides.
- `ENABLE_EXTERNAL_ENGINES=1` requires trusted Team IDs for every non-unverified build, including local ad-hoc QA builds.
- GitHub update downloads require a signed manifest, checksum match, Developer ID Team ID match, and Gatekeeper approval.

## Automated Checks

Run the macOS XCTest suite:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -scheme VideoPlayer -destination platform=macOS
```

Expected coverage includes AppKit playlist import/search/sort/sidebar/metadata smoke workflows, playlist reorder/delete, SQLite migration and privacy clearing, security-scoped bookmarks, cancellable scanning, playback profiles and route planning, poster replacement/removal, Stable/Beta release selection, version comparison, update asset validation, URL validation, DNS/private-host blocking, Keychain-safe credential rules, persistence redaction, stream bookmarks, subtitle preferences, fleet diagnostics JSON, recovery state, external-engine lookup hardening, enterprise policy parsing, support bundle redaction/upload generation, MDM profile generation, library catalog reports, activation requests, license verification, release readiness, and diagnostic recommendations.
