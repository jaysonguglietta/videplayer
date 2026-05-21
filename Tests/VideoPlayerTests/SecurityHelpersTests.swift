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
        defaults.set("sparkle", forKey: EnterprisePolicy.Key.updateChannel)
        defaults.set("https://updates.example.com/appcast.xml", forKey: EnterprisePolicy.Key.sparkleAppcastURL)

        let policy = EnterprisePolicy.snapshot(defaults: defaults)

        XCTAssertEqual(policy.organizationName, "JSON Technology")
        XCTAssertTrue(policy.forceDisablePlaybackHistory)
        XCTAssertTrue(policy.kioskModeEnabled)
        XCTAssertEqual(policy.supportUploadURL?.host, "support.example.com")
        XCTAssertEqual(policy.updateChannel, "sparkle")
        XCTAssertEqual(policy.sparkleAppcastURL?.lastPathComponent, "appcast.xml")
        XCTAssertTrue(policy.allowsStreamHost("cdn.media.example.com"))
        XCTAssertTrue(policy.allowsStreamHost("video.trusted.example"))
        XCTAssertFalse(policy.allowsStreamHost("untrusted.example.net"))
        XCTAssertTrue(policy.hasManagedRestrictions)
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
            updateChannel: "sparkle",
            sparkleAppcastURLString: nil
        )

        let report = ReleaseReadiness.report(policy: policy)
        XCTAssertTrue(report.text.contains("Sparkle Readiness"))
        XCTAssertTrue(report.text.contains("EnterpriseSparkleAppcastURL"))
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
