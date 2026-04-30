# Commercial Distribution Checklist

This project is configured for direct commercial distribution as an app bundle that contains:

- Video Player application code under this repository's MIT License.
- Apple system frameworks provided by macOS.
- No bundled VLC/libVLC, VLC plugins, mpv, FFmpeg, or other third-party media engines.

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
REQUIRE_NOTARIZATION=1 ./Scripts/build_release_dmg.sh
```

4. Publish updates only through the signed update manifest flow:

```sh
./Scripts/publish_release.sh
```

5. Keep `.release/update-signing-private-key.pem` private and backed up.
6. Do not use VideoLAN, VLC, or mpv names/logos as product branding.
7. Mention VLC/mpv only as optional user-installed integrations.
8. Review codec patent/licensing obligations for the formats you market.

## Optional User-Installed Engines

The app may dynamically use VLC/libVLC or mpv only when users have installed those tools separately. Those projects retain their own upstream license terms and trademarks. Do not ship their binaries, plugins, installers, icons, or source-derived assets in a paid DMG unless you are prepared to meet all upstream redistribution obligations.

## If You Later Bundle Third-Party Engines

Create a separate legal/compliance pass before release. At minimum, expect to:

- Include upstream license texts and notices.
- Provide source code or source offers where required.
- Track exact binary versions and build configuration.
- Verify whether any bundled modules are GPL, LGPL, patented, or trademark-sensitive.
- Confirm the distribution channel terms are compatible with the relevant open-source licenses.
