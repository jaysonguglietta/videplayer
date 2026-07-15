# Enterprise Deployment Guide

Video Player now includes an enterprise operations layer for managed Mac fleets: admin-enforced preferences, playback diagnostics, support bundle export, host allow-listing for streams, and signed offline license status.

## Enterprise Workflows

- Help > Enterprise Status shows the installed version, Developer ID/update readiness, trusted external-engine configuration, license status, and active managed policy.
- Help > Release Readiness checks Developer ID configuration, external-engine build mode, update manifest readiness, license public key state, support redaction, selected update channel, Sparkle appcast readiness, and current code-signature status.
- Help > Playback Diagnostics inspects the selected media item and reports the native playback route, detected codecs, external-engine availability, DNS pinning data for streams, license state, and recommended action.
- Help > Playback Engine Doctor inspects VLC/libVLC and mpv candidate paths, accessibility, Team ID, Gatekeeper/code-signature trust, user opt-in, and policy status.
- Help > Playback Engine Setup Assistant combines build state, engine trust details, discovered Team IDs, and the recommended next step for advanced codec enablement.
- Help > Export Fleet Diagnostics JSON writes a machine-readable report with app/build state, selected media, playlist count, library summary, policy, license, release readiness, recovery state, and subtitle preferences.
- Help > Recovery Report shows whether the previous app session ended cleanly, the last playback item, and the last main-thread watchdog warning.
- Help > Export MDM Policy Profile writes a `.mobileconfig` with the current enterprise policy values.
- Help > Export Support Bundle creates a support folder with `support-report.txt`, `playback-diagnostics.txt`, `operation-timeline.txt`, and optionally a redacted `video-player.log`. If `EnterpriseSupportUploadURL` is configured, users can upload the bundle to that endpoint.
- Help > License Status shows the installed enterprise license record.
- Help > Import Enterprise License installs a signed license JSON into the user's Application Support folder.
- Help > Create License Activation Request creates an offline activation request JSON with the app version, bundle ID, machine hash, requester, and license key.
- Help > Deactivate Enterprise License removes the local license file from the Mac.
- File > Manage Library Folders lets users review, rescan, or remove saved media folders when playback history is enabled.
- File > Browse Media Library opens the searchable SQLite-backed index with continue-watching, favorites, unwatched, streams, and missing-file views.
- File > Library Report summarizes playlist size, stream count, missing local files, favorites, watched items, tag counts, quality buckets, TV episode groups, and duplicate/version groups.
- File > Save Current Stream Bookmark and File > Open Stream Bookmark let users persist approved stream sources when history saving is enabled.
- File > Toggle Favorite, Mark Watched, Mark Unwatched, and Set Tags provide basic enterprise library curation.

## Managed Preferences

Deploy these keys in the `com.jaysonguglietta.videoplayer` preference domain through MDM, configuration profiles, or local `defaults` commands for testing.

| Key | Type | Default | Effect |
| --- | --- | --- | --- |
| `EnterpriseOrganizationName` | string | empty | Displays the managed organization name in Enterprise Status and support reports. |
| `EnterpriseForceDisableExternalMediaEngines` | boolean | false | Disables opt-in VLC/mpv runtime use even in advanced external-engine builds. |
| `EnterpriseForceBlockPrivateNetworkStreams` | boolean | false | Keeps private/local stream targets blocked and disables the user toggle. |
| `EnterpriseForceDisablePlaybackHistory` | boolean | false | Forces playback history off and prevents playlist, recent media, resume positions, and library folders from persisting. |
| `EnterpriseForceClearHistoryOnQuit` | boolean | false | Forces playback history clearing when the app quits. |
| `EnterpriseDisableUpdateChecks` | boolean | false | Disables user-initiated update checks. |
| `EnterpriseDisableSupportBundleLogExport` | boolean | false | Prevents logs from being included in exported support bundles. |
| `EnterpriseRedactSupportBundles` | boolean | true | Redacts home-folder paths, volume paths, stream credentials, and common URL tokens from support bundles. |
| `EnterpriseRequireLicense` | boolean | false | Marks deployment non-compliant in Enterprise Status unless a usable license is installed. |
| `EnterpriseAllowedStreamHostSuffixes` | array or comma-separated string | empty | Restricts network stream hosts to exact domains or subdomains of the listed suffixes. |
| `EnterpriseKioskModeEnabled` | boolean | false | Disables file browsing, playlist import/export, network stream entry, and library edits; optionally loads a managed kiosk playlist. |
| `EnterpriseKioskPlaylistURL` | string | empty | Local file URL/path or stream URL to load when kiosk mode is enabled. |
| `EnterpriseSupportUploadURL` | string | empty | HTTPS endpoint for optional multipart support bundle uploads. The app rejects HTTP, embedded credentials, literal private/local hosts, and DNS results that resolve to private/local addresses. |
| `EnterpriseSupportUploadHostSuffixes` | array or comma-separated string | empty | Optional allow-list for approved support upload host suffixes. Configure this when support uploads are enabled. |
| `EnterpriseSupportUploadTokenKeychainService` | string | empty | Optional Keychain generic-password service name containing the bearer token used for authenticated support uploads. The app first looks for account equal to the app bundle ID, then falls back to any account for the service. |
| `EnterpriseUpdateChannel` | string | `github` | Supported values: `github`, `github-stable`, `github-beta`, `sparkle`, or `mdm`. Stable excludes prereleases; beta includes cryptographically verified prereleases. |
| `EnterpriseSparkleAppcastURL` | string | empty | Sparkle appcast URL for future Sparkle 2 migration readiness checks. |

Example local test policy:

```sh
defaults write com.jaysonguglietta.videoplayer EnterpriseOrganizationName "Acme Media"
defaults write com.jaysonguglietta.videoplayer EnterpriseForceBlockPrivateNetworkStreams -bool true
defaults write com.jaysonguglietta.videoplayer EnterpriseAllowedStreamHostSuffixes -array media.example.com cdn.example.net
defaults write com.jaysonguglietta.videoplayer EnterpriseUpdateChannel github
```

Remove test policy:

```sh
defaults delete com.jaysonguglietta.videoplayer EnterpriseOrganizationName
defaults delete com.jaysonguglietta.videoplayer EnterpriseForceBlockPrivateNetworkStreams
defaults delete com.jaysonguglietta.videoplayer EnterpriseAllowedStreamHostSuffixes
```

## License File

Enterprise licenses are JSON files with a payload and optional P-256 signature. The app treats unsigned licenses as operational records unless a license public key is built into the app.

```json
{
  "license": {
    "customerName": "Acme Media",
    "licenseID": "lic_001",
    "seatLimit": 250,
    "expiresAt": "2027-12-31",
    "supportLevel": "Enterprise",
    "features": ["support-bundle", "managed-policy"],
    "contactEmail": "it@example.com"
  },
  "signature": "base64-der-ecdsa-signature"
}
```

For signed offline enforcement, build the app with:

```sh
export ENTERPRISE_LICENSE_PUBLIC_KEY="base64-x963-p256-public-key"
./Scripts/build_release_dmg.sh
```

The signed payload is stable line-oriented text in this order:

```text
customerName=
licenseID=
seatLimit=
expiresAt=
supportLevel=
features=
contactEmail=
```

The app verifies the DER-encoded P-256 ECDSA signature over that UTF-8 payload.

## Support Bundles

Support bundles are folders created under a user-selected destination. They are designed for enterprise help desk workflows:

- `support-report.txt`: app version, macOS, sandbox/container hint, selected media summary, license status, and active policy.
- `playback-diagnostics.txt`: selected media route, codec assessment, external engine status, DNS pinning details, and next action.
- `video-player.log`: optional rotating app log, omitted when disabled by policy or user choice.
- `operation-timeline.txt`: bounded playback-startup, library-scan, and watchdog events for sequencing freeze investigations.

Redaction is on by default and removes home-folder paths, volume paths, stream credentials, and common URL token parameters. Keep redaction enabled unless support is working on a local filesystem bug that requires exact paths.

## Fleet Diagnostics JSON

Fleet diagnostics are intended for help desk, inventory, and managed deployment review. The JSON export includes app version, macOS, selected media, playlist count, current playback engine, external-engine trust configuration, enterprise policy summary, license status, release-readiness checks, library summary, recovery state, and subtitle preferences. It is designed to be safe to attach to tickets because stream URLs are persisted through the same redaction path used for history and support reports.

## Update Management

The app's built-in updater remains GitHub Release based and requires a signed manifest, SHA-256 validation, Developer ID Team ID verification, and Gatekeeper assessment. `github-stable` excludes prereleases and `github-beta` accepts prereleases that satisfy the same verification chain. Enterprises that distribute Video Player through MDM can set `EnterpriseUpdateChannel=mdm` or `EnterpriseDisableUpdateChecks=true` and deploy updates through their software management system instead.

`EnterpriseUpdateChannel=sparkle` is available as a Sparkle-ready managed setting and Release Readiness check. It reports the configured appcast and intentionally keeps the signed GitHub updater in place until the Sparkle 2 framework and sandbox XPC services are bundled and tested. This avoids downgrading the current signed-manifest security posture during migration.

## Data Protection and Retention

Playback history is off by default. When enabled, indexed media, curation state, resume positions, and per-media profiles are stored in `Library.sqlite3` under the app's Application Support container. User-approved library folders are represented by security-scoped bookmarks. Optional HTTPS/RTSPS stream credentials are stored per host in the macOS Keychain with device-only accessibility and are injected only into the playback request. Clearing history removes the library records, bookmarks, profiles, positions, and saved metadata; Settings also provides an explicit Remove Stream Credentials action.

## Kiosk Mode

Kiosk mode is intended for classrooms, training rooms, retail displays, and locked-down playback stations. When `EnterpriseKioskModeEnabled=true`, the app blocks user file browsing, playlist import/export, manual stream entry, and library edits. Set `EnterpriseKioskPlaylistURL` to a local playlist/media path or approved stream URL to preload managed content.

## Support Uploads

Set `EnterpriseSupportUploadURL` to an HTTPS endpoint to let users upload support bundles after export. Uploads use `multipart/form-data` with the redacted text files from the generated support bundle. The endpoint must resolve to public addresses and cannot include embedded credentials. Configure `EnterpriseSupportUploadHostSuffixes` to the support domains your organization owns.

For authenticated uploads, store the bearer token as a generic password in Keychain and set `EnterpriseSupportUploadTokenKeychainService` to that service name. The app first searches for a generic password item with service equal to that value and account equal to the bundle ID, then falls back to the service alone. Keep `EnterpriseRedactSupportBundles=true` unless support explicitly needs exact local paths.

## Recommended Enterprise Defaults

- Keep `EnterpriseRedactSupportBundles=true`.
- Configure `EnterpriseSupportUploadURL` only to an authenticated public HTTPS endpoint that your organization controls.
- Set `EnterpriseSupportUploadHostSuffixes` and `EnterpriseSupportUploadTokenKeychainService` whenever support uploads are enabled.
- Keep playback history disabled unless resume/library persistence is an approved user workflow.
- Keep private/local streams blocked unless the deployment explicitly supports internal cameras or LAN media servers.
- Use `EnterpriseAllowedStreamHostSuffixes` for kiosk, classroom, or call-center deployments that should only play approved streaming domains.
- Use the default sandboxed native-only build for broad commercial distribution.
- Use the advanced external-engine build only for controlled deployments that require MKV/WebM/AVI/FLAC/OPUS playback and have a documented trust model for user-installed VLC/mpv.
