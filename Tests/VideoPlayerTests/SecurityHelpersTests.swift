import Foundation
import XCTest
@testable import VideoPlayer

final class SecurityHelpersTests: XCTestCase {
    func testVersionComparatorUsesNumericOrdering() {
        XCTAssertTrue(VersionComparator.isVersion("v0.1.10", newerThan: "0.1.2"))
        XCTAssertFalse(VersionComparator.isVersion("v0.1.2", newerThan: "0.1.2"))
        XCTAssertFalse(VersionComparator.isVersion("0.1.1", newerThan: "0.1.2"))
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

    func testNetworkStreamValidatorBlocksDNSResolvedPrivateTargets() {
        let resolver: (String) -> [String] = { host in
            host == "public.example.com" ? ["127.0.0.1"] : []
        }

        XCTAssertNil(NetworkStreamValidator.validatedURL(
            from: "https://public.example.com/live.m3u8",
            resolvedAddressesForHost: resolver
        ))
        XCTAssertNotNil(NetworkStreamValidator.validatedURL(
            from: "https://public.example.com/live.m3u8",
            allowPrivateNetworkHosts: true,
            resolvedAddressesForHost: resolver
        ))
    }

    func testNetworkStreamValidatorAllowsDNSResolvedPublicTargets() {
        XCTAssertNotNil(NetworkStreamValidator.validatedURL(
            from: "https://media.example.com/live.m3u8",
            resolvedAddressesForHost: { _ in ["93.184.216.34"] }
        ))
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

}
