import CryptoKit
import Foundation
import XCTest
@testable import VideoPlayer

final class SecurityHelpersTests: XCTestCase {
    func testVersionComparatorUsesNumericOrdering() {
        XCTAssertTrue(VersionComparator.isVersion("v0.1.10", newerThan: "0.1.2"))
        XCTAssertFalse(VersionComparator.isVersion("v0.1.2", newerThan: "0.1.2"))
        XCTAssertFalse(VersionComparator.isVersion("0.1.1", newerThan: "0.1.2"))
        XCTAssertEqual(VersionComparator.compare("v0.1.1", to: "0.1.8"), .orderedAscending)
        XCTAssertEqual(VersionComparator.compare("v0.1.8", to: "0.1.8"), .orderedSame)
        XCTAssertEqual(VersionComparator.compare("v0.1.10", to: "0.1.8"), .orderedDescending)
    }

    func testNetworkStreamValidatorRestrictsSchemes() {
        XCTAssertEqual(NetworkStreamValidator.validatedURL(from: " https://example.com/live.m3u8 ")?.scheme, "https")
        XCTAssertEqual(NetworkStreamValidator.validatedURL(from: "rtsp://stream.example.com/live")?.scheme, "rtsp")
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "file:///etc/passwd"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "javascript:alert(1)"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "https://"))
    }

    func testNetworkStreamValidatorBlocksPrivateAndLocalTargetsByDefault() {
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "http://127.0.0.1/live.m3u8"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "http://localhost/live.m3u8"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "http://169.254.169.254/latest/meta-data"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "rtsp://192.168.1.10/stream"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "http://[::1]/stream"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "rtsp://camera.local/stream"))

        XCTAssertNotNil(NetworkStreamValidator.validatedURL(
            from: "rtsp://192.168.1.10/stream",
            allowPrivateNetworkHosts: true
        ))
    }

    func testNetworkStreamValidatorBlocksDNSResolvedPrivateTargets() async {
        let resolver: (String) async -> [String]? = { host in
            host == "public.example.com" ? ["127.0.0.1"] : []
        }

        let blockedURL = await NetworkStreamValidator.validatedURLResolvingHost(
            from: "https://public.example.com/live.m3u8",
            resolvedAddressesForHost: resolver
        )
        XCTAssertNil(blockedURL)

        let allowedURL = await NetworkStreamValidator.validatedURLResolvingHost(
            from: "https://public.example.com/live.m3u8",
            allowPrivateNetworkHosts: true,
            resolvedAddressesForHost: resolver
        )
        XCTAssertNotNil(allowedURL)
    }

    func testNetworkStreamValidatorAllowsDNSResolvedPublicTargets() async {
        let url = await NetworkStreamValidator.validatedURLResolvingHost(
            from: "https://media.example.com/live.m3u8",
            resolvedAddressesForHost: { _ in ["93.184.216.34"] }
        )
        XCTAssertNotNil(url)
    }

    func testNetworkStreamValidatorReturnsPinnedPublicAddresses() async throws {
        let stream = await NetworkStreamValidator.validatedStream(
            from: "https://media.example.com/live.m3u8",
            resolvedAddressesForHost: { _ in ["93.184.216.34", "2606:2800:220:1:248:1893:25c8:1946"] }
        )

        XCTAssertEqual(stream?.url.host, "media.example.com")
        XCTAssertEqual(stream?.resolvedAddresses, Set([
            "93.184.216.34",
            "2606:2800:220:1:248:1893:25c8:1946"
        ]))
    }

    func testNetworkStreamValidatorFailsClosedWhenDNSDoesNotResolve() async {
        let url = await NetworkStreamValidator.validatedURLResolvingHost(
            from: "https://missing.example.com/live.m3u8",
            resolvedAddressesForHost: { _ in nil }
        )
        XCTAssertNil(url)
    }

    func testSafeDownloadFileNameRemovesPathTraversal() {
        XCTAssertEqual(UpdateSecurity.safeDownloadFileName("../Video Player.dmg"), "Video Player.dmg")
        XCTAssertEqual(UpdateSecurity.safeDownloadFileName("bad/name?.zip"), "name-.zip.dmg")
        XCTAssertEqual(UpdateSecurity.safeDownloadFileName(""), "Video Player.dmg")
    }

    func testManifestSignedPayloadIsStable() throws {
        let manifest = UpdateManifest(
            version: "0.1.2",
            build: "3",
            tagName: "v0.1.2",
            minimumSystemVersion: "13.0",
            assetName: "Video Player.dmg",
            assetURL: try XCTUnwrap(URL(string: "https://github.com/jaysonguglietta/videplayer/releases/download/v0.1.2/Video.Player.dmg")),
            sha256: "ABCDEF",
            signature: "signature"
        )

        XCTAssertEqual(
            manifest.signedPayload,
            """
            version=0.1.2
            build=3
            tagName=v0.1.2
            minimumSystemVersion=13.0
            assetName=Video Player.dmg
            assetURL=https://github.com/jaysonguglietta/videplayer/releases/download/v0.1.2/Video.Player.dmg
            sha256=abcdef
            """
        )
    }

    func testSignedManifestVerificationAcceptsPinnedKeySignature() throws {
        let manifestJSON = """
        {
          "version": "9.9.9",
          "build": "999",
          "tagName": "v9.9.9",
          "minimumSystemVersion": "13.0",
          "assetName": "Video Player.dmg",
          "assetURL": "https://github.com/jaysonguglietta/videplayer/releases/download/v9.9.9/Video.Player.dmg",
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "signature": "MEUCIA7bKxkJws+ZZDqTu5AJwCs5MDwhvq74dub2CAQjbn1lAiEA8jrHsDhSB9lRHMIBgje6/A95E7P+3l1LZlDZxhLt/xY="
        }
        """

        let manifest = try UpdateSecurity.verifiedManifest(from: Data(manifestJSON.utf8))
        XCTAssertEqual(manifest.version, "9.9.9")
    }

    func testNetworkPersistenceRedactsCredentialsQueryAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "https://user:pass@example.com/movie.m3u8?token=secret#frag"))
        XCTAssertEqual(MediaPersistence.storageString(for: url), "https://example.com/movie.m3u8")
    }

    func testAppLoggerRedactsSensitiveURLsAndPaths() throws {
        let streamURL = try XCTUnwrap(URL(string: "https://user:pass@example.com/movie.m3u8?token=secret#frag"))
        XCTAssertEqual(AppLogger.redactedURLString(streamURL), "https://example.com/movie.m3u8?[REDACTED]#[REDACTED]")
        XCTAssertFalse(AppLogger.redactedFilePath(NSHomeDirectory() + "/Movies/private.mkv").contains(NSHomeDirectory()))
        XCTAssertEqual(AppLogger.redactedFilePath("/Volumes/downloads/complete/private.mkv"), "/Volumes/[REDACTED]")
    }

    func testPlaybackStateStoreMigratesStoredNetworkSecrets() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(["https://user:pass@example.com/movie.m3u8?token=secret#frag"], forKey: "recentMedia")
        defaults.set(["https://user:pass@example.com/movie.m3u8?token=secret#frag"], forKey: "playlist")
        defaults.set(["https://user:pass@example.com/movie.m3u8?token=secret#frag": 42.0], forKey: "positions")
        PrivacySettings.setSavePlaybackHistory(true, defaults: defaults)

        let store = PlaybackStateStore(defaults: defaults)
        let item = MediaItem(url: try XCTUnwrap(URL(string: "https://user:pass@example.com/movie.m3u8?token=secret#frag")))

        XCTAssertEqual(store.loadRecentMedia().first?.url.absoluteString, "https://example.com/movie.m3u8")
        XCTAssertEqual(store.loadPlaylist().0.first?.url.absoluteString, "https://example.com/movie.m3u8")
        XCTAssertEqual(store.position(for: item), 42.0)
        XCTAssertEqual(defaults.stringArray(forKey: "recentMedia"), ["https://example.com/movie.m3u8"])
        XCTAssertEqual(defaults.stringArray(forKey: "playlist"), ["https://example.com/movie.m3u8"])
        XCTAssertEqual(defaults.dictionary(forKey: "positions") as? [String: Double], ["https://example.com/movie.m3u8": 42.0])
    }

    func testPlaybackStateStoreCanDisableHistoryPersistence() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PlaybackStateStore(defaults: defaults)
        store.setSavePlaybackHistoryEnabled(false)

        let item = MediaItem(url: try XCTUnwrap(URL(string: "file:///Users/example/Private Movie.mkv")))
        store.savePlaylist([item], currentIndex: 0)
        store.addRecentMedia(item)
        store.addLibraryFolder(URL(fileURLWithPath: "/Users/example/Private Folder", isDirectory: true))
        store.savePosition(120, for: item)

        XCTAssertTrue(store.loadPlaylist().0.isEmpty)
        XCTAssertTrue(store.loadRecentMedia().isEmpty)
        XCTAssertTrue(store.loadLibraryFolders().isEmpty)
        XCTAssertEqual(store.position(for: item), 0)
    }

    func testPlaybackHistoryDefaultsOff() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(PrivacySettings.savePlaybackHistory(defaults: defaults))
    }

    func testTrustedEngineTeamIDsIgnoreEnvironmentWhenDevelopmentOverridesDisabled() {
        let teamIDs = AppSecurityPolicy.trustedExternalEngineTeamIDs(
            from: "TEAMFROMPLIST",
            environment: ["VIDEOPLAYER_TRUSTED_ENGINE_TEAM_IDS": "TEAMFROMENV"],
            includeDevelopmentOverrides: false
        )

        XCTAssertEqual(teamIDs, Set(["TEAMFROMPLIST"]))
    }

    func testTrustedEngineTeamIDsIncludeEnvironmentOnlyForDevelopmentOverrides() {
        let teamIDs = AppSecurityPolicy.trustedExternalEngineTeamIDs(
            from: ["TEAMFROMPLIST"],
            environment: ["VIDEOPLAYER_TRUSTED_ENGINE_TEAM_IDS": "TEAMFROMENV"],
            includeDevelopmentOverrides: true
        )

        XCTAssertEqual(teamIDs, Set(["TEAMFROMPLIST", "TEAMFROMENV"]))
    }

    func testExternalEnginesUnavailableByDefault() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PrivacySettings.setExternalMediaEnginesEnabled(true, defaults: defaults)

        XCTAssertFalse(AppSecurityPolicy.externalMediaEnginesAvailable)
        XCTAssertFalse(PrivacySettings.externalMediaEnginesEnabled(defaults: defaults))
    }

    func testMPVLookupUsesTrustedPathsByDefault() {
        let defaultCandidates = MPVBridge.candidateExecutablePaths(environment: ["PATH": "/tmp/malicious"])
        XCTAssertEqual(defaultCandidates.first, "/opt/homebrew/bin/mpv")
        XCTAssertFalse(defaultCandidates.contains("/tmp/malicious/mpv"))

        let optInCandidates = MPVBridge.candidateExecutablePaths(environment: [
            "PATH": "/tmp/tools",
            "VIDEOPLAYER_ALLOW_PATH_MPV": "1"
        ])
        XCTAssertTrue(optInCandidates.contains("/tmp/tools/mpv"))

        let releaseCandidates = MPVBridge.candidateExecutablePaths(
            environment: [
                "PATH": "/tmp/tools",
                "VIDEOPLAYER_ALLOW_PATH_MPV": "1"
            ],
            includeDevelopmentPathLookup: false
        )
        XCTAssertFalse(releaseCandidates.contains("/tmp/tools/mpv"))
        XCTAssertFalse(MPVBridge.isDevelopmentPathLookupAllowed(
            environment: [
                "PATH": "/tmp/tools",
                "VIDEOPLAYER_ALLOW_PATH_MPV": "1"
            ],
            includeDevelopmentPathLookup: false
        ))
    }

    func testNativePlaybackPolicyRequiresExternalForDolbyVisionCodecs() {
        let assessment = NativePlaybackPolicy.assessment(
            fileExtension: "mp4",
            nativeExtensions: ["mp4", "m4v", "mov"],
            videoCodecs: ["dvh1", "hev1"]
        )

        XCTAssertEqual(assessment.routing, .requiresExternal)
        XCTAssertTrue(assessment.requiresExternalEngine)
        XCTAssertTrue(assessment.reason?.contains("Dolby Vision") == true)
    }

    func testNativePlaybackPolicyPrefersExternalForHEVCCodecs() {
        let assessment = NativePlaybackPolicy.assessment(
            fileExtension: "mp4",
            nativeExtensions: ["mp4", "m4v", "mov"],
            videoCodecs: ["hev1"]
        )

        XCTAssertEqual(assessment.routing, .preferExternal)
        XCTAssertTrue(assessment.prefersExternalEngine)
        XCTAssertFalse(assessment.requiresExternalEngine)
    }

    func testNativePlaybackPolicyAllowsNativeAVCInMP4() {
        let assessment = NativePlaybackPolicy.assessment(
            fileExtension: "mp4",
            nativeExtensions: ["mp4", "m4v", "mov"],
            videoCodecs: ["avc1"]
        )

        XCTAssertEqual(assessment.routing, .native)
        XCTAssertFalse(assessment.prefersExternalEngine)
    }

    func testNativePlaybackPolicyRequiresExternalForNonNativeContainer() {
        let assessment = NativePlaybackPolicy.assessment(
            fileExtension: "mkv",
            nativeExtensions: ["mp4", "m4v", "mov"],
            videoCodecs: ["avc1"]
        )

        XCTAssertEqual(assessment.routing, .requiresExternal)
        XCTAssertTrue(assessment.prefersExternalEngine)
        XCTAssertTrue(assessment.requiresExternalEngine)
    }

    func testUpdateReleaseSelectorReportsInstalledBuildNewerThanPublishedRelease() throws {
        let release = try makeRelease(tagName: "v0.1.1")
        let availability = UpdateReleaseSelector.availability(from: [release], currentVersion: "0.1.8")

        XCTAssertEqual(availability, .installedBuildIsNewer(release))
    }

    func testUpdateReleaseSelectorChoosesHighestPublishedSemverRelease() throws {
        let releases = try [
            makeRelease(tagName: "v0.1.9"),
            makeRelease(tagName: "v0.1.10"),
            makeRelease(tagName: "v0.2.0-beta", isPrerelease: true),
            makeRelease(tagName: "v0.3.0", isDraft: true)
        ]

        let selected = UpdateReleaseSelector.newestPublishedRelease(from: releases)
        XCTAssertEqual(selected?.tagName, "v0.1.10")
        XCTAssertEqual(
            UpdateReleaseSelector.availability(from: releases, currentVersion: "0.1.8"),
            .updateAvailable(try makeRelease(tagName: "v0.1.10"))
        )
    }

    func testUpdateReleaseSelectorHandlesUpToDateAndEmptyReleaseLists() throws {
        let release = try makeRelease(tagName: "v0.1.8")

        XCTAssertEqual(
            UpdateReleaseSelector.availability(from: [release], currentVersion: "0.1.8"),
            .upToDate(release)
        )
        XCTAssertEqual(
            UpdateReleaseSelector.availability(from: [], currentVersion: "0.1.8"),
            .noPublishedReleases
        )
    }

    func testTeamIdentifierParsing() {
        let diagnostic = """
        Executable=/Applications/Video Player.app/Contents/MacOS/VideoPlayer
        Identifier=com.jaysonguglietta.videoplayer
        TeamIdentifier=ABCDE12345
        """

        XCTAssertEqual(CodeSignatureVerifier.teamIdentifier(from: diagnostic), "ABCDE12345")
        XCTAssertNil(CodeSignatureVerifier.teamIdentifier(from: "TeamIdentifier=not set"))
    }

    func testExternalEngineVerificationTargetUsesContainingApp() {
        let url = URL(fileURLWithPath: "/Applications/VLC.app/Contents/MacOS/lib/libvlc.dylib")
        XCTAssertEqual(ExternalMediaEngineTrust.verificationTarget(for: url).path, "/Applications/VLC.app")
    }

    func testEnterprisePolicyParsesManagedPreferencesAndHostAllowList() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("JSON Technology", forKey: EnterprisePolicy.Key.organizationName)
        defaults.set("true", forKey: EnterprisePolicy.Key.forceDisablePlaybackHistory)
        defaults.set(["media.example.com", ".trusted.example"], forKey: EnterprisePolicy.Key.allowedStreamHostSuffixes)
        defaults.set(true, forKey: EnterprisePolicy.Key.kioskModeEnabled)
        defaults.set("https://support.example.com/upload", forKey: EnterprisePolicy.Key.supportUploadURL)
        defaults.set(["support.example.com"], forKey: EnterprisePolicy.Key.supportUploadHostSuffixes)
        defaults.set("videoplayer-support-upload-token", forKey: EnterprisePolicy.Key.supportUploadTokenKeychainService)
        defaults.set("sparkle", forKey: EnterprisePolicy.Key.updateChannel)
        defaults.set("https://updates.example.com/appcast.xml", forKey: EnterprisePolicy.Key.sparkleAppcastURL)

        let policy = EnterprisePolicy.snapshot(defaults: defaults)

        XCTAssertEqual(policy.organizationName, "JSON Technology")
        XCTAssertTrue(policy.forceDisablePlaybackHistory)
        XCTAssertTrue(policy.kioskModeEnabled)
        XCTAssertEqual(policy.supportUploadURL?.host, "support.example.com")
        XCTAssertEqual(policy.supportUploadHostSuffixes, ["support.example.com"])
        XCTAssertEqual(policy.supportUploadTokenKeychainService, "videoplayer-support-upload-token")
        XCTAssertEqual(policy.updateChannel, "sparkle")
        XCTAssertEqual(policy.sparkleAppcastURL?.lastPathComponent, "appcast.xml")
        XCTAssertTrue(policy.allowsStreamHost("cdn.media.example.com"))
        XCTAssertTrue(policy.allowsStreamHost("video.trusted.example"))
        XCTAssertFalse(policy.allowsStreamHost("untrusted.example.net"))
        XCTAssertTrue(policy.hasManagedRestrictions)
    }

    func testEnterprisePolicyRejectsUnsafeSupportUploadURLs() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("http://support.example.com/upload", forKey: EnterprisePolicy.Key.supportUploadURL)
        XCTAssertNil(EnterprisePolicy.snapshot(defaults: defaults).supportUploadURL)

        defaults.set("https://127.0.0.1/upload", forKey: EnterprisePolicy.Key.supportUploadURL)
        XCTAssertNil(EnterprisePolicy.snapshot(defaults: defaults).supportUploadURL)

        defaults.set("https://user:pass@support.example.com/upload", forKey: EnterprisePolicy.Key.supportUploadURL)
        XCTAssertNil(EnterprisePolicy.snapshot(defaults: defaults).supportUploadURL)

        defaults.set("https://support.example.com/upload", forKey: EnterprisePolicy.Key.supportUploadURL)
        defaults.set(["support.example.com"], forKey: EnterprisePolicy.Key.supportUploadHostSuffixes)
        XCTAssertEqual(EnterprisePolicy.snapshot(defaults: defaults).supportUploadURL?.host, "support.example.com")

        defaults.set(["other.example.com"], forKey: EnterprisePolicy.Key.supportUploadHostSuffixes)
        XCTAssertNil(EnterprisePolicy.snapshot(defaults: defaults).supportUploadURL)
    }

    func testPrivacySettingsHonorEnterprisePolicyLocks() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: EnterprisePolicy.Key.forceDisablePlaybackHistory)
        defaults.set(true, forKey: EnterprisePolicy.Key.forceBlockPrivateNetworkStreams)
        defaults.set(true, forKey: EnterprisePolicy.Key.forceClearHistoryOnQuit)

        PrivacySettings.setSavePlaybackHistory(true, defaults: defaults)
        PrivacySettings.setAllowPrivateNetworkStreams(true, defaults: defaults)
        PrivacySettings.setClearHistoryOnQuit(false, defaults: defaults)

        XCTAssertFalse(PrivacySettings.savePlaybackHistory(defaults: defaults))
        XCTAssertFalse(PrivacySettings.allowPrivateNetworkStreams(defaults: defaults))
        XCTAssertTrue(PrivacySettings.clearHistoryOnQuit(defaults: defaults))
    }

    func testNetworkStreamValidatorHonorsEnterpriseHostAllowList() {
        XCTAssertNotNil(NetworkStreamValidator.validatedURL(
            from: "https://media.example.com/live.m3u8",
            allowedHostSuffixes: ["example.com"]
        ))
        XCTAssertNil(NetworkStreamValidator.validatedURL(
            from: "https://other.example.net/live.m3u8",
            allowedHostSuffixes: ["example.com"]
        ))
    }

    func testSupportBundleRedactsSensitivePathsAndURLSecrets() {
        let raw = """
        file=/Users/jaysonguglietta/Movies/Private/movie.mkv
        url=https://user:pass@example.com/movie.m3u8?token=secret&safe=1
        volume=/Volumes/downloads/complete/private/movie.mkv
        """

        let redacted = SupportBundleExporter.sanitize(raw, redactPaths: true)

        XCTAssertFalse(redacted.contains("/Users/jaysonguglietta"))
        XCTAssertFalse(redacted.contains("secret"))
        XCTAssertFalse(redacted.contains("/Volumes/downloads/complete"))
        XCTAssertTrue(redacted.contains("~"))
        XCTAssertTrue(redacted.contains("token=[REDACTED]"))
    }

    func testEnterpriseLicenseStatusHandlesUnsignedAndSignedLicenses() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let license = EnterpriseLicense(
            customerName: "Acme Media",
            licenseID: "lic_test",
            seatLimit: 25,
            expiresAt: "2099-01-01",
            supportLevel: "Enterprise",
            features: ["support-bundle", "managed-policy"],
            contactEmail: "it@example.com"
        )

        let unsignedURL = directory.appendingPathComponent("unsigned-license.json")
        let unsignedData = try JSONEncoder().encode(EnterpriseLicenseEnvelope(license: license, signature: nil))
        try unsignedData.write(to: unsignedURL)

        XCTAssertEqual(
            EnterpriseLicenseManager.status(licenseURL: unsignedURL, publicKeyBase64: nil),
            .unverified(license)
        )
        XCTAssertFalse(EnterpriseLicenseManager.status(licenseURL: unsignedURL, publicKeyBase64: nil).isOperationallyUsable)

        let privateKey = P256.Signing.PrivateKey()
        let signature = try privateKey.signature(for: Data(license.signedPayload.utf8))
        let signedURL = directory.appendingPathComponent("signed-license.json")
        let signedData = try JSONEncoder().encode(EnterpriseLicenseEnvelope(
            license: license,
            signature: signature.derRepresentation.base64EncodedString()
        ))
        try signedData.write(to: signedURL)

        XCTAssertEqual(
            EnterpriseLicenseManager.status(
                licenseURL: signedURL,
                publicKeyBase64: privateKey.publicKey.x963Representation.base64EncodedString()
            ),
            .valid(license)
        )
    }

    func testEnterpriseLicenseRejectsOversizedLicenseFiles() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oversizedURL = directory.appendingPathComponent("license.json")
        let oversized = Data(repeating: 65, count: 1_000_001)
        try oversized.write(to: oversizedURL)

        guard case .invalid(let reason) = EnterpriseLicenseManager.status(licenseURL: oversizedURL, publicKeyBase64: nil) else {
            return XCTFail("Expected oversized license to be invalid")
        }
        XCTAssertTrue(reason.contains("too large"))
    }

    func testPlaybackDiagnosticsRecommendsExternalEngineForRequiredCodec() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let item = MediaItem(url: URL(fileURLWithPath: "/Movies/Feature.mkv"))
        let assessment = NativePlaybackAssessment(
            routing: .requiresExternal,
            reason: "MKV requires a trusted external engine.",
            detectedVideoCodecs: ["avc1"]
        )
        let report = PlaybackDiagnostics.report(input: PlaybackDiagnosticInput(
            item: item,
            nativeAssessment: assessment,
            externalEnginesAvailable: false,
            externalEnginesEnabled: false,
            vlcAvailable: false,
            mpvAvailable: false,
            policy: EnterprisePolicy.snapshot(defaults: defaults),
            licenseStatus: .notInstalled,
            resolvedStreamAddresses: []
        ))

        XCTAssertTrue(report.text.contains("Requires trusted VLC/mpv"))
        XCTAssertTrue(report.text.contains("Build the advanced external-engine variant"))
    }

    func testMDMProfileBuilderIncludesEnterpriseKeys() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Acme", forKey: EnterprisePolicy.Key.organizationName)
        defaults.set(true, forKey: EnterprisePolicy.Key.kioskModeEnabled)
        defaults.set(["media.example.com"], forKey: EnterprisePolicy.Key.allowedStreamHostSuffixes)

        let profile = MDMProfileBuilder.mobileconfig(policy: EnterprisePolicy.snapshot(defaults: defaults))

        XCTAssertTrue(profile.contains("com.apple.ManagedClient.preferences"))
        XCTAssertTrue(profile.contains(EnterprisePolicy.Key.kioskModeEnabled))
        XCTAssertTrue(profile.contains("media.example.com"))
        XCTAssertTrue(profile.contains("com.jaysonguglietta.videoplayer"))
    }

    func testLibraryCatalogNormalizesTagsAndReportsCounts() throws {
        let items = [
            MediaItem(url: URL(fileURLWithPath: "/tmp/Movie.mp4")),
            MediaItem(url: try XCTUnwrap(URL(string: "https://media.example.com/live.m3u8")))
        ]
        let records = [
            MediaPersistence.storageString(for: items[0].url): MediaLibraryRecord(
                isFavorite: true,
                isWatched: true,
                tags: ["training", "sales"],
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            MediaPersistence.storageString(for: items[1].url): MediaLibraryRecord(
                isFavorite: false,
                isWatched: false,
                tags: ["training"],
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        ]

        XCTAssertEqual(LibraryCatalog.normalizedTags(from: " Training, sales,training "), ["sales", "training"])
        let report = LibraryCatalog.report(playlist: items, records: records)
        XCTAssertEqual(report.totalItems, 2)
        XCTAssertEqual(report.streamItems, 1)
        XCTAssertEqual(report.favorites, 1)
        XCTAssertEqual(report.watched, 1)
        XCTAssertEqual(report.tags["training"], 2)
    }

    func testLibraryCatalogDetectsQualityAndVersionGroups() {
        let items = [
            MediaItem(url: URL(fileURLWithPath: "/media/Feature.1993.1080p.BluRay.x264.mkv")),
            MediaItem(url: URL(fileURLWithPath: "/media/Feature.1993.2160p.UHD.x265.mkv")),
            MediaItem(url: URL(fileURLWithPath: "/media/Show.Name.S01E01.720p.WEB.mkv")),
            MediaItem(url: URL(fileURLWithPath: "/media/Show.Name.S01E02.720p.WEB.mkv"))
        ]

        let report = LibraryCatalog.report(playlist: items, records: [:])

        XCTAssertEqual(report.qualityCounts["1080p"], 1)
        XCTAssertEqual(report.qualityCounts["4K/UHD"], 1)
        XCTAssertEqual(report.qualityCounts["720p"], 2)
        XCTAssertGreaterThanOrEqual(report.duplicateOrVersionGroups, 1)
        XCTAssertEqual(report.tvEpisodeGroups, 1)
        XCTAssertTrue(report.text.contains("Largest Groups"))
    }

    func testSubtitleTrackSelectorHonorsPreferences() {
        let options = [
            TrackOption(id: -1, name: "Subtitles Off"),
            TrackOption(id: 1, name: "English"),
            TrackOption(id: 2, name: "Spanish Forced")
        ]

        XCTAssertEqual(SubtitleTrackSelector.preferredTrackID(
            options: options,
            preferences: SubtitlePreferences(selectionMode: .off, preferredLanguage: "en", stylePreset: .system)
        ), -1)
        XCTAssertEqual(SubtitleTrackSelector.preferredTrackID(
            options: options,
            preferences: SubtitlePreferences(selectionMode: .preferredLanguage, preferredLanguage: "es", stylePreset: .large)
        ), 2)
        XCTAssertEqual(SubtitleTrackSelector.preferredTrackID(
            options: options,
            preferences: SubtitlePreferences(selectionMode: .forcedOnly, preferredLanguage: "en", stylePreset: .highContrast)
        ), 2)
    }

    func testPlaybackStateStorePersistsStreamBookmarksOnlyWhenHistoryEnabled() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlaybackStateStore(defaults: defaults)
        let stream = MediaItem(url: try XCTUnwrap(URL(string: "https://user:pass@example.com/live.m3u8?token=secret")))

        store.addStreamBookmark(stream)
        XCTAssertTrue(store.loadStreamBookmarks().isEmpty)

        store.setSavePlaybackHistoryEnabled(true)
        store.addStreamBookmark(stream)

        XCTAssertEqual(store.loadStreamBookmarks().first?.url.absoluteString, "https://example.com/live.m3u8")
    }

    func testPlaybackStateStorePersistsSubtitlePreferences() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlaybackStateStore(defaults: defaults)
        let preferences = SubtitlePreferences(
            selectionMode: .preferredLanguage,
            preferredLanguage: "es",
            stylePreset: .highContrast
        )

        store.saveSubtitlePreferences(preferences)

        XCTAssertEqual(store.loadSubtitlePreferences(), preferences)
    }

    func testMediaMetadataCacheSavesMetadataAndPoster() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlayerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = MediaItem(url: try XCTUnwrap(URL(string: "file:///Users/example/Movie.mp4")))
        let metadata = MediaMetadata(
            title: "Movie",
            location: "/Users/example/Movie.mp4",
            kind: "MP4",
            size: "10 MB",
            duration: "1:30",
            dimensions: "1920x1080",
            modified: "Today",
            savedPosition: "--",
            extraDetails: ["Video Tracks: hvc1", "Audio Tracks: aac"]
        )
        let posterData = Data("poster".utf8)

        let cache = MediaMetadataCache(directory: directory)
        let result = try cache.save(item: item, metadata: metadata, posterData: posterData)
        let saved = try XCTUnwrap(cache.load(item: item))

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.metadataURL.path))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(result.posterURL)), posterData)
        XCTAssertEqual(saved.title, "Movie")
        XCTAssertEqual(saved.posterFileName, "\(MediaMetadataCache.key(for: item.url)).png")
        XCTAssertEqual(saved.fields.map(\.value), ["Video Tracks: hvc1", "Audio Tracks: aac"])
    }

    func testMediaMetadataCacheRedactsNetworkSourceSecrets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlayerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = MediaItem(url: try XCTUnwrap(URL(string: "https://user:pass@example.com/movie.m3u8?token=secret#frag")))
        let metadata = MediaMetadata(
            title: "Stream",
            location: "https://example.com/movie.m3u8",
            kind: "Network Stream",
            size: "--",
            duration: "--",
            dimensions: "--",
            modified: "--",
            savedPosition: "--",
            extraDetails: []
        )

        let cache = MediaMetadataCache(directory: directory)
        _ = try cache.save(item: item, metadata: metadata, posterData: nil)
        let saved = try XCTUnwrap(cache.load(item: item))

        XCTAssertEqual(saved.sourceURL, "https://example.com/movie.m3u8")
        XCTAssertNil(saved.posterFileName)
    }

    func testFleetDiagnosticsJSONIncludesEnterpriseAndLibraryState() throws {
        let item = MediaItem(url: URL(fileURLWithPath: "/media/Feature.1080p.mkv"))
        let policy = EnterprisePolicySnapshot(
            organizationName: "Acme",
            forceDisableExternalMediaEngines: false,
            forceBlockPrivateNetworkStreams: true,
            forceDisablePlaybackHistory: false,
            forceClearHistoryOnQuit: false,
            disableUpdateChecks: false,
            disableSupportBundleLogExport: false,
            redactSupportBundlePaths: true,
            requireLicense: false,
            allowedStreamHostSuffixes: ["media.example.com"],
            kioskModeEnabled: false,
            kioskPlaylistURLString: nil,
            supportUploadURLString: nil,
            supportUploadHostSuffixes: [],
            supportUploadTokenKeychainService: nil,
            updateChannel: "github",
            sparkleAppcastURLString: nil
        )
        let libraryReport = LibraryCatalog.report(playlist: [item], records: [:])
        let readiness = ReleaseReadinessReport(checks: [
            ReadinessCheck(title: "Example", status: .pass, detail: "Ready")
        ])
        let recovery = PlaybackRecoveryState(
            previousSessionEndedCleanly: true,
            lastPlaybackTitle: item.title,
            lastPlaybackURL: item.url.absoluteString,
            lastPlaybackAt: Date(timeIntervalSince1970: 0),
            lastHangWarningAt: nil
        )

        let document = FleetDiagnostics.document(
            selectedItem: item,
            playlist: [item],
            currentEngine: "VLC",
            vlcAvailable: true,
            mpvAvailable: false,
            policy: policy,
            licenseStatus: .notInstalled,
            releaseReadiness: readiness,
            libraryReport: libraryReport,
            recoveryState: recovery,
            subtitlePreferences: .default,
            now: Date(timeIntervalSince1970: 0)
        )
        let json = try XCTUnwrap(String(data: FleetDiagnostics.jsonData(from: document), encoding: .utf8))

        XCTAssertTrue(json.contains("\"playlistCount\" : 1"))
        XCTAssertTrue(json.contains("\"organizationName\" : \"Acme\""))
        XCTAssertTrue(json.contains("\"currentEngine\" : \"VLC\""))
    }

    func testPlaybackRecoveryPreservesPreviousSessionCleanStateOnLaunch() throws {
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PlaybackRecovery.markCleanShutdown(defaults: defaults)
        PlaybackRecovery.markLaunch(defaults: defaults)
        XCTAssertTrue(PlaybackRecovery.state(defaults: defaults).previousSessionEndedCleanly)

        PlaybackRecovery.markLaunch(defaults: defaults)
        XCTAssertFalse(PlaybackRecovery.state(defaults: defaults).previousSessionEndedCleanly)
    }

    func testSupportBundleUploaderBuildsMultipartBody() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("support-report.txt")
        try "report".write(to: file, atomically: true, encoding: .utf8)

        let body = try SupportBundleUploader.multipartBody(files: [file], boundary: "Boundary")
        let text = String(data: body, encoding: .utf8)

        XCTAssertTrue(text?.contains("filename=\"support-report.txt\"") == true)
        XCTAssertTrue(text?.contains("report") == true)
        XCTAssertTrue(text?.contains("--Boundary--") == true)
    }

    func testSupportBundleUploaderValidatesEndpoints() async throws {
        let publicURL = try XCTUnwrap(URL(string: "https://support.example.com/upload"))
        let validated = try await SupportBundleUploader.validatedEndpoint(
            publicURL,
            allowedHostSuffixes: ["example.com"],
            resolvedAddressesForHost: { _ in ["93.184.216.34"] }
        )
        XCTAssertEqual(validated, publicURL)
        XCTAssertEqual(SupportBundleUploader.authorizationHeaderValue(forBearerToken: " token "), "Bearer token")
        XCTAssertNil(SupportBundleUploader.authorizationHeaderValue(forBearerToken: " "))

        let httpURL = try XCTUnwrap(URL(string: "http://support.example.com/upload"))
        do {
            _ = try await SupportBundleUploader.validatedEndpoint(
                httpURL,
                resolvedAddressesForHost: { _ in ["93.184.216.34"] }
            )
            XCTFail("Expected HTTP support upload endpoint to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTPS"))
        }

        do {
            _ = try await SupportBundleUploader.validatedEndpoint(
                publicURL,
                allowedHostSuffixes: ["support.example.net"],
                resolvedAddressesForHost: { _ in ["93.184.216.34"] }
            )
            XCTFail("Expected support upload endpoint outside allow-list to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("allow-list"))
        }

        let privateDNSURL = try XCTUnwrap(URL(string: "https://support.example.com/upload"))
        do {
            _ = try await SupportBundleUploader.validatedEndpoint(
                privateDNSURL,
                resolvedAddressesForHost: { _ in ["127.0.0.1"] }
            )
            XCTFail("Expected private DNS support upload endpoint to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("public addresses"))
        }
    }

    func testEnterpriseActivationRequestTrimsInputsAndIsSerializable() throws {
        let request = EnterpriseActivationManager.activationRequest(
            licenseKey: "  ABC-123  ",
            requestedBy: "  it@example.com  ",
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(request.licenseKey, "ABC-123")
        XCTAssertEqual(request.requestedBy, "it@example.com")
        XCTAssertFalse(request.machineHash.isEmpty)
        XCTAssertNoThrow(try JSONEncoder().encode(request))
    }

    func testReleaseReadinessReportIncludesSparkleWarningWhenConfiguredWithoutAppcast() {
        let policy = EnterprisePolicySnapshot(
            organizationName: nil,
            forceDisableExternalMediaEngines: false,
            forceBlockPrivateNetworkStreams: false,
            forceDisablePlaybackHistory: false,
            forceClearHistoryOnQuit: false,
            disableUpdateChecks: false,
            disableSupportBundleLogExport: false,
            redactSupportBundlePaths: true,
            requireLicense: false,
            allowedStreamHostSuffixes: [],
            kioskModeEnabled: false,
            kioskPlaylistURLString: nil,
            supportUploadURLString: nil,
            supportUploadHostSuffixes: [],
            supportUploadTokenKeychainService: nil,
            updateChannel: "sparkle",
            sparkleAppcastURLString: nil
        )

        let report = ReleaseReadiness.report(policy: policy)
        XCTAssertTrue(report.text.contains("Sparkle Readiness"))
        XCTAssertTrue(report.text.contains("EnterpriseSparkleAppcastURL"))
    }

    func testUpdateReleaseSelectorCanIncludeSignedBetaChannelCandidates() throws {
        let stable = try makeRelease(tagName: "v1.0.0")
        let beta = try makeRelease(tagName: "v1.1.0-beta.1", isPrerelease: true)

        XCTAssertEqual(
            UpdateReleaseSelector.newestPublishedRelease(from: [stable, beta])?.tagName,
            "v1.0.0"
        )
        XCTAssertEqual(
            UpdateReleaseSelector.newestPublishedRelease(from: [stable, beta], includePrereleases: true)?.tagName,
            "v1.1.0-beta.1"
        )
    }

    func testReleaseReadinessAcceptsManagedStableAndBetaChannels() {
        for updateChannel in ["github-stable", "github-beta"] {
            let policy = EnterprisePolicySnapshot(
                organizationName: nil,
                forceDisableExternalMediaEngines: false,
                forceBlockPrivateNetworkStreams: false,
                forceDisablePlaybackHistory: false,
                forceClearHistoryOnQuit: false,
                disableUpdateChecks: false,
                disableSupportBundleLogExport: false,
                redactSupportBundlePaths: true,
                requireLicense: false,
                allowedStreamHostSuffixes: [],
                kioskModeEnabled: false,
                kioskPlaylistURLString: nil,
                supportUploadURLString: nil,
                supportUploadHostSuffixes: [],
                supportUploadTokenKeychainService: nil,
                updateChannel: updateChannel,
                sparkleAppcastURLString: nil
            )

            let report = ReleaseReadiness.report(policy: policy)
            XCTAssertFalse(report.text.contains("Unknown update channel"))
        }
    }

    func testNetworkStreamValidatorRejectsEmbeddedCredentials() {
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "https://user:secret@example.com/live.m3u8"))
        XCTAssertNotNil(NetworkStreamValidator.validatedURL(from: "https://example.com/live.m3u8"))
    }

    func testPlaybackRoutePlannerPrefersTrustedEnginesAndFailsClosed() throws {
        let mkv = MediaItem(url: URL(fileURLWithPath: "/tmp/Movie.mkv"))
        let assessment = NativePlaybackAssessment(
            routing: .requiresExternal,
            reason: "Requires external engine",
            detectedVideoCodecs: ["hvc1"]
        )
        let nativeExtensions: Set<String> = ["mp4", "mov"]

        XCTAssertEqual(PlaybackRoutePlanner.route(for: PlaybackRouteContext(
            item: mkv,
            nativeAssessment: assessment,
            nativeExtensions: nativeExtensions,
            vlcAvailable: true,
            mpvAvailable: true
        )), .vlc)
        XCTAssertEqual(PlaybackRoutePlanner.route(for: PlaybackRouteContext(
            item: mkv,
            nativeAssessment: assessment,
            nativeExtensions: nativeExtensions,
            vlcAvailable: false,
            mpvAvailable: true
        )), .mpv)
        XCTAssertEqual(PlaybackRoutePlanner.route(for: PlaybackRouteContext(
            item: mkv,
            nativeAssessment: assessment,
            nativeExtensions: nativeExtensions,
            vlcAvailable: false,
            mpvAvailable: false
        )), .none)
    }

    func testLibraryDatabaseIndexesRecordsPositionsAndProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlayerDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LibraryDatabase(url: directory.appendingPathComponent("Library.sqlite3"))
        let suiteName = "VideoPlayerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlaybackStateStore(defaults: defaults, libraryDatabase: database)
        store.setSavePlaybackHistoryEnabled(true)

        let item = MediaItem(url: URL(fileURLWithPath: "/tmp/Feature.mkv"))
        store.indexLibraryItems([item])
        store.savePosition(73, for: item)
        let record = MediaLibraryRecord(isFavorite: true, isWatched: false, tags: ["demo"], updatedAt: Date())
        store.saveMediaLibraryRecord(record, for: item)
        let profile = MediaPlaybackProfile(
            speedTitle: "1.25x",
            audioPresetName: AudioPreset.speechBoost.rawValue,
            qualityPresetName: PlaybackQualityPreset.cinema.rawValue,
            audioDelaySeconds: 0.2,
            subtitleDelaySeconds: -0.3,
            updatedAt: Date()
        )
        store.savePlaybackProfile(profile, for: item)

        XCTAssertEqual(store.indexedLibraryItems(), [item])
        XCTAssertEqual(store.position(for: item), 73)
        XCTAssertEqual(store.mediaLibraryRecord(for: item).tags, ["demo"])
        XCTAssertEqual(store.playbackProfile(for: item), profile)

        store.clearPlaybackHistory()
        XCTAssertTrue(store.indexedLibraryItems().isEmpty)
        XCTAssertEqual(store.position(for: item), 0)
    }

    func testLibraryScanServiceLimitsAndSortsMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlayerScanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("B.mp4"))
        try Data().write(to: directory.appendingPathComponent("A.mkv"))
        try Data().write(to: directory.appendingPathComponent("notes.txt"))

        let result = await LibraryScanService.scan(
            urls: [directory],
            mediaExtensions: ["mp4", "mkv"],
            maximumMediaFiles: 10,
            maximumEnumeratedItems: 10
        )

        XCTAssertEqual(result.mediaURLs.map(\.lastPathComponent), ["A.mkv", "B.mp4"])
        XCTAssertFalse(result.wasLimited)
        XCTAssertFalse(result.wasCancelled)
    }

    func testSecurityScopedBookmarkRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlayerBookmarkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let data = try SecurityScopedBookmarks.data(for: directory)
        let resolved = try SecurityScopedBookmarks.resolve(data)
        XCTAssertEqual(resolved.url.standardizedFileURL, directory.standardizedFileURL)
    }

    func testMediaMetadataCacheCanReplaceAndRemovePoster() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlayerPosterTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = MediaItem(url: URL(fileURLWithPath: "/tmp/Movie.mp4"))
        let metadata = MediaMetadata(
            title: "Movie",
            location: "/tmp/Movie.mp4",
            kind: "MP4",
            size: "1 MB",
            duration: "1:00",
            dimensions: "1920x1080",
            modified: "Today",
            savedPosition: "--",
            extraDetails: []
        )
        let cache = MediaMetadataCache(directory: directory)
        _ = try cache.save(item: item, metadata: metadata, posterData: nil)
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))

        let posterURL = try cache.replacePoster(item: item, imageData: png)
        XCTAssertTrue(FileManager.default.fileExists(atPath: posterURL.path))
        XCTAssertNotNil(try cache.load(item: item)?.posterFileName)

        try cache.removePoster(item: item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: posterURL.path))
        XCTAssertNil(try cache.load(item: item)?.posterFileName)
    }

    private func makeRelease(
        tagName: String,
        isDraft: Bool = false,
        isPrerelease: Bool = false
    ) throws -> GitHubRelease {
        GitHubRelease(
            tagName: tagName,
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/jaysonguglietta/videplayer/releases/tag/\(tagName)")),
            assets: [],
            isDraft: isDraft,
            isPrerelease: isPrerelease
        )
    }

}
