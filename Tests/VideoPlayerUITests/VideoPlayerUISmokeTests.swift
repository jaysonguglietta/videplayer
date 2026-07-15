import AppKit
import XCTest
@testable import VideoPlayer

@MainActor
final class VideoPlayerUISmokeTests: XCTestCase {
    private var fixtureDirectory: URL!
    private var playlistURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = NSApplication.shared
        fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlayerUISmokeTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

        let secondMediaURL = fixtureDirectory.appendingPathComponent("Alpha Feature.mp4")
        let firstMediaURL = fixtureDirectory.appendingPathComponent("Zulu Feature.mkv")
        XCTAssertTrue(FileManager.default.createFile(atPath: firstMediaURL.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: secondMediaURL.path, contents: Data()))

        playlistURL = fixtureDirectory.appendingPathComponent("Smoke Playlist.m3u8")
        let playlist = """
        #EXTM3U
        \(firstMediaURL.path)
        \(secondMediaURL.path)
        https://192.0.2.1/live.m3u8
        """
        try playlist.write(to: playlistURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let fixtureDirectory {
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }
        try super.tearDownWithError()
    }

    func testPlaylistImportSearchAndSort() async throws {
        let controller = PlayerViewController()
        try await controller.importPlaylistForUISmokeTesting(from: playlistURL)

        var state = controller.snapshotForUISmokeTesting()
        XCTAssertEqual(state.playlistCount, 3)
        XCTAssertEqual(state.visiblePlaylistCount, 3)
        XCTAssertEqual(state.tableAccessibilityIdentifier, "playlist.table")

        controller.setPlaylistSearchForUISmokeTesting("mp4")
        state = controller.snapshotForUISmokeTesting()
        XCTAssertEqual(state.searchText, "mp4")
        XCTAssertEqual(state.visibleTitles, ["Alpha Feature"])
        XCTAssertEqual(state.searchAccessibilityIdentifier, "playlist.search")

        controller.setPlaylistSearchForUISmokeTesting("")
        controller.setPlaylistSortForUISmokeTesting("Sort: Title")
        state = controller.snapshotForUISmokeTesting()
        XCTAssertEqual(state.sortTitle, "Sort: Title")
        XCTAssertEqual(state.visibleTitles, ["Alpha Feature", "live.m3u8", "Zulu Feature"])
        XCTAssertEqual(state.sortAccessibilityIdentifier, "playlist.sort")
    }

    func testSidebarAndMetadataControlsAreReachable() async throws {
        let controller = PlayerViewController()
        try await controller.importPlaylistForUISmokeTesting(from: playlistURL)

        var state = controller.snapshotForUISmokeTesting()
        XCTAssertFalse(state.sidebarHidden)
        XCTAssertTrue(state.metadataSaveEnabled)
        XCTAssertEqual(state.metadataSaveAccessibilityIdentifier, "metadata.save")

        controller.toggleSidebar(nil)
        state = controller.snapshotForUISmokeTesting()
        XCTAssertTrue(state.sidebarHidden)

        controller.toggleSidebar(nil)
        state = controller.snapshotForUISmokeTesting()
        XCTAssertFalse(state.sidebarHidden)
    }
}
