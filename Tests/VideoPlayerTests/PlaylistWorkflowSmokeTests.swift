import Foundation
import XCTest
@testable import VideoPlayer

final class PlaylistWorkflowSmokeTests: XCTestCase {
    func testPlaylistSearchFiltersByTitleExtensionPathAndStreamURL() throws {
        let items = [
            MediaItem(url: URL(fileURLWithPath: "/Users/example/Movies/Concert.mkv")),
            MediaItem(url: URL(fileURLWithPath: "/Users/example/Audio/Interview.wav")),
            MediaItem(url: try XCTUnwrap(URL(string: "https://media.example.com/live/channel.m3u8")))
        ]

        XCTAssertEqual(PlaylistWorkflow.visibleIndices(in: items, filter: "concert"), [0])
        XCTAssertEqual(PlaylistWorkflow.visibleIndices(in: items, filter: "wav"), [1])
        XCTAssertEqual(PlaylistWorkflow.visibleIndices(in: items, filter: "channel"), [2])
        XCTAssertEqual(PlaylistWorkflow.visibleIndices(in: items, filter: "missing"), [])
    }

    func testPlaylistSortsByTitleMediaTypeAndLocation() throws {
        let items = [
            MediaItem(url: URL(fileURLWithPath: "/Videos/Zebra.mkv")),
            MediaItem(url: URL(fileURLWithPath: "/Audio/Alpha.wav")),
            MediaItem(url: try XCTUnwrap(URL(string: "https://media.example.com/live/Stream.m3u8")))
        ]

        XCTAssertEqual(PlaylistWorkflow.sorted(items, by: .title).map(\.title), ["Alpha", "Stream.m3u8", "Zebra"])
        XCTAssertEqual(PlaylistWorkflow.sorted(items, by: .mediaType).map(\.fileExtension), ["mkv", "m3u8", "wav"])
        XCTAssertEqual(PlaylistWorkflow.sorted(items, by: .location).map(\.subtitle), [
            "/Audio/Alpha.wav",
            "/Videos/Zebra.mkv",
            "https://media.example.com/live/Stream.m3u8"
        ])
    }

    func testPlaylistExportProducesM3U8WithLocalAndStreamEntries() throws {
        let items = [
            MediaItem(url: URL(fileURLWithPath: "/Videos/Feature.mp4")),
            MediaItem(url: try XCTUnwrap(URL(string: "https://media.example.com/live/channel.m3u8")))
        ]

        let text = PlaylistWorkflow.exportedM3U8Text(for: items)

        XCTAssertTrue(text.hasPrefix("#EXTM3U\n#PLAYLIST:Video Player\n"))
        XCTAssertTrue(text.contains("#EXTINF:-1,Feature\n/Videos/Feature.mp4"))
        XCTAssertTrue(text.contains("#EXTINF:-1,channel.m3u8\nhttps://media.example.com/live/channel.m3u8"))
    }

    func testPlaylistReorderMovesMultipleSelectedRowsAroundDropTarget() {
        let items = [
            MediaItem(url: URL(fileURLWithPath: "/Videos/A.mp4")),
            MediaItem(url: URL(fileURLWithPath: "/Videos/B.mp4")),
            MediaItem(url: URL(fileURLWithPath: "/Videos/C.mp4")),
            MediaItem(url: URL(fileURLWithPath: "/Videos/D.mp4")),
            MediaItem(url: URL(fileURLWithPath: "/Videos/E.mp4"))
        ]

        XCTAssertEqual(
            PlaylistWorkflow.reordered(items, movingIndexes: [1, 3], to: 5).map(\.title),
            ["A", "C", "E", "B", "D"]
        )
        XCTAssertEqual(
            PlaylistWorkflow.reordered(items, movingIndexes: [3, 1, 1], to: 0).map(\.title),
            ["B", "D", "A", "C", "E"]
        )
        XCTAssertEqual(
            PlaylistWorkflow.reordered(items, movingIndexes: [9], to: 0).map(\.title),
            ["A", "B", "C", "D", "E"]
        )
    }

    func testPlaylistRemoveDropsMultipleSelectedRows() {
        let items = [
            MediaItem(url: URL(fileURLWithPath: "/Videos/A.mp4")),
            MediaItem(url: URL(fileURLWithPath: "/Videos/B.mp4")),
            MediaItem(url: URL(fileURLWithPath: "/Videos/C.mp4")),
            MediaItem(url: URL(fileURLWithPath: "/Videos/D.mp4"))
        ]

        XCTAssertEqual(
            PlaylistWorkflow.removing(items, indexes: [0, 2, 2]).map(\.title),
            ["B", "D"]
        )
        XCTAssertEqual(
            PlaylistWorkflow.removing(items, indexes: [9]).map(\.title),
            ["A", "B", "C", "D"]
        )
    }

    func testImportResultsReportSkippedLinesWithReasons() {
        let result = PlaylistImportResult(
            items: [],
            issues: [
                PlaylistImportIssue(lineNumber: 3, entry: "missing.mp4", reason: "File does not exist."),
                PlaylistImportIssue(lineNumber: 5, entry: "ftp://example.com/movie.mp4", reason: "Stream URL is invalid, unsupported, private/local, or could not be resolved.")
            ]
        )

        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertTrue(result.issueSummary.contains("Line 3: missing.mp4 - File does not exist."))
        XCTAssertTrue(result.issueSummary.contains("Line 5: ftp://example.com/movie.mp4"))
    }

    func testRelativePlaylistEntryResolvesAgainstPlaylistLocation() {
        let base = URL(fileURLWithPath: "/Users/example/Playlists", isDirectory: true)
        let resolved = PlaylistWorkflow.fileURL(fromPlaylistEntry: "../Movies/Feature.mp4", baseDirectory: base)
        XCTAssertEqual(resolved.standardizedFileURL.path, "/Users/example/Movies/Feature.mp4")
    }
}
