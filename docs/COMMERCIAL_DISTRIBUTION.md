# Commercial Distribution Checklist

This project is configured for direct commercial distribution as an app bundle that contains:

- Video Player application code under this repository's MIT License.
- Apple system frameworks provided by macOS.
- No bundled VLC/libVLC, VLC plugins, mpv, FFmpeg, or other third-party media engines.
- A sandboxed native-only default build.

This document is practical engineering guidance, not legal advice. Have counsel review the exact release package, store terms, trademarks, privacy policy, and patent exposure before broad commercial sale.

## Before Selling a Release

1. Keep `Scripts/build_app.sh` free of third-party media runtime bundling.
2. Confirm the app bundle has no bundled media engines:

```sh
find "Build/Video Player.app/Contents/Resources" -maxdepth 3 -type f
```

3. Build, sign, notarize, and staple the DMG:

```sh
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notarytool-profile"
export EXPECTED_DEVELOPER_TEAM_ID="TEAMID"
./Scripts/build_release_dmg.sh
```

4. Store the update manifest private key in Keychain before publishing. Use Keychain Access to create a generic password item named `videoplayer-update-signing-private-key`, then paste the PEM private key into the password field. The local release script is Keychain-first and refuses file-based signing unless `ALLOW_FILE_UPDATE_SIGNING_KEY=1` is explicitly set.

5. Publish updates only through the signed update manifest flow from a clean `main` branch with a signed release tag and explicit release approval:

```sh
git status --short
git tag -s "v0.1.6" -m "Release v0.1.6"
export UPDATE_SIGNING_KEYCHAIN_SERVICE="videoplayer-update-signing-private-key"
export RELEASE_APPROVAL="v0.1.6"
./Scripts/publish_release.sh
```

6. Keep the original private key file offline or in a secure secret store after adding it to Keychain; do not keep it in synced folders.
7. Keep `ENABLE_EXTERNAL_ENGINES` unset for the default sandboxed commercial DMG.
8. If you intentionally ship an advanced external-engine build, set `ENABLE_EXTERNAL_ENGINES=1` and set `TRUSTED_EXTERNAL_ENGINE_TEAM_IDS` only for external VLC/mpv signatures you intentionally trust.
9. Do not use VideoLAN, VLC, or mpv names/logos as product branding.
10. Mention VLC/mpv only as optional user-installed integrations.
11. Review codec patent/licensing obligations for the formats you market.

## Optional User-Installed Engines

The default commercial build does not load VLC/libVLC or mpv. An advanced build may dynamically use VLC/libVLC or mpv only when users have installed those tools separately, users enable external engines, and strict code-signature, Gatekeeper, and configured Team ID checks accept the engine. Those projects retain their own upstream license terms and trademarks. Do not ship their binaries, plugins, installers, icons, or source-derived assets in a paid DMG unless you are prepared to meet all upstream redistribution obligations.

## Direct-Distribution Security Defaults

- Release builds require Developer ID signing by default.
- DMG builds require notarization by default.
- Default builds use App Sandbox and do not disable library validation.
- Runtime environment variables cannot widen external-engine trust in release builds.
- Local update publishing uses a Keychain-backed signing key by default, requires explicit `RELEASE_APPROVAL`, and uploads release provenance beside the DMG and signed manifest.
- The updater verifies the signed manifest, SHA-256 checksum, Developer ID Team ID, and Gatekeeper assessment before opening an update.
- Private/local network streams, including DNS names resolving to private/local addresses, are blocked by default.
- Playback history is off by default; saved playback history and saved library folders can be enabled, cleared immediately, or cleared on quit.
- Recursive folder scans are capped to reduce accidental denial of service.

## If You Later Bundle Third-Party Engines

Create a separate legal/compliance pass before release. At minimum, expect to:

- Include upstream license texts and notices.
- Provide source code or source offers where required.
- Track exact binary versions and build configuration.
- Verify whether any bundled modules are GPL, LGPL, patented, or trademark-sensitive.
- Confirm the distribution channel terms are compatible with the relevant open-source licenses.
