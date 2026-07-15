# Codec Service Architecture

Video Player 2.0 intentionally does not bundle a third-party codec runtime. The default commercial build uses AVFoundation inside the App Sandbox. Advanced controlled builds may use a separately installed, trusted VLC or mpv engine, but that is not equivalent to shipping broad codec support as part of the sold product.

## Target Design

Broad built-in codec coverage should run in a separately signed and notarized helper, not in the main AppKit process. The helper should have its own narrow sandbox profile, no inherited user environment, no arbitrary executable or plugin search paths, and an authenticated XPC interface. The main app grants access only to the selected media item and receives decoded frames, audio, timing, track metadata, and bounded errors.

The preferred frame path is an IOSurface-backed pool with explicit dimensions, pixel format, frame number, and lifetime ownership. Audio should use a bounded shared-memory ring or AudioToolbox-compatible stream with backpressure. XPC messages must use fixed Codable/NSSecureCoding models, reject unknown fields and oversized payloads, and never accept shell commands, library paths, plugin paths, or arbitrary output paths.

## Trust and Release Controls

- Pin the exact codec source version, download URL, and SHA-256 in source-controlled release metadata.
- Build the helper reproducibly in protected CI or verify an official artifact's signature and checksum before packaging.
- Sign the helper and nested libraries with the same expected Developer ID team, hardened runtime, and least-privilege entitlements.
- Verify the helper's static code identity from the main app before opening the XPC connection.
- Notarize and staple the complete app bundle and DMG; reject release artifacts that contain unsigned nested code.
- Generate an SBOM and retain source, patches, build flags, license texts, and corresponding-source obligations for every distributed module.
- Keep update-manifest signing separate from Developer ID credentials and require an approved, signed release tag.

## Failure Isolation

Treat every media file as hostile. Apply memory, file-size, track-count, dimension, and decode-time limits. The helper must be restartable per item or after a crash, and repeated crashes for the same fingerprint should stop automatic retries and produce a recovery report. The main UI must remain responsive while the helper probes or decodes media.

Network access should be absent from the decode helper unless a separate stream-fetch service is explicitly designed. Stream fetching should retain the existing scheme, host allow-list, private-address, DNS revalidation, credential, timeout, and size controls, then provide bytes to the decoder through a bounded channel.

## Commercial and Legal Gates

Before the helper is distributed, counsel must review the exact dependency graph, LGPL/GPL obligations, dynamic-linking model, source-offer requirements, codec patent exposure, trademarks, and distribution-channel terms. Product copy must not promise a format until the signed release artifact has passed the matching conformance media suite.

## Acceptance Criteria

1. Malformed-media fuzzing and a representative codec/container corpus cannot crash or block the main app.
2. Killing or hanging the helper produces a bounded timeout, useful operation timeline, and recoverable UI state.
3. The helper cannot read arbitrary user files, connect to arbitrary hosts, launch processes, or load code outside its signed bundle.
4. Every nested binary passes strict code-signature validation and the complete package passes Gatekeeper and notarization checks.
5. License notices, source obligations, SBOM, pinned provenance, and vulnerability-response ownership are complete.
6. Native, helper, and unsupported routes have deterministic automated tests plus real-media release QA.

Until these criteria are met, the default sold app should remain native-only and the advanced external-engine build should be described as an administrator-controlled integration with separately installed software.
