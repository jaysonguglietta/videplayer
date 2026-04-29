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
        XCTAssertEqual(NetworkStreamValidator.validatedURL(from: "rtsp://camera.local/stream")?.scheme, "rtsp")
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "file:///etc/passwd"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "javascript:alert(1)"))
        XCTAssertNil(NetworkStreamValidator.validatedURL(from: "https://"))
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

}
