import Foundation

enum PlaylistSortMode: String, CaseIterable {
    case currentOrder
    case title
    case mediaType
    case location

    init?(title: String?) {
        guard let title,
              let mode = Self.allCases.first(where: { $0.title == title })
        else {
            return nil
        }
        self = mode
    }

    var title: String {
        switch self {
        case .currentOrder:
            "Sort: Current Order"
        case .title:
            "Sort: Title"
        case .mediaType:
            "Sort: Media Type"
        case .location:
            "Sort: Location"
        }
    }

    var shortTitle: String {
        switch self {
        case .currentOrder:
            "current order"
        case .title:
            "title"
        case .mediaType:
            "media type"
        case .location:
            "location"
        }
    }
}

struct PlaylistImportIssue: Equatable {
    let lineNumber: Int
    let entry: String
    let reason: String

    var displayText: String {
        "Line \(lineNumber): \(entry) - \(reason)"
    }
}

struct PlaylistImportResult {
    let items: [MediaItem]
    let issues: [PlaylistImportIssue]

    var skippedCount: Int {
        issues.count
    }

    var issueSummary: String {
        guard !issues.isEmpty else { return "" }
        return issues.map(\.displayText).joined(separator: "\n")
    }
}

struct PlaylistEntryImportResult {
    let items: [MediaItem]
    let issue: PlaylistImportIssue?
}

enum PlaylistWorkflow {
    static func visibleIndices(in playlist: [MediaItem], filter: String) -> [Int] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return Array(playlist.indices)
        }

        return playlist.indices.filter { index in
            let item = playlist[index]
            let searchableValues = [
                item.title,
                item.fileExtension,
                item.isNetworkStream ? item.url.absoluteString : item.url.path
            ]
            return searchableValues.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    static func sorted(_ playlist: [MediaItem], by mode: PlaylistSortMode) -> [MediaItem] {
        guard mode != .currentOrder else { return playlist }
        return playlist.sorted { lhs, rhs in
            comparator(lhs, rhs, mode: mode)
        }
    }

    static func sort(_ playlist: inout [MediaItem], by mode: PlaylistSortMode) {
        guard mode != .currentOrder else { return }
        playlist.sort { lhs, rhs in
            comparator(lhs, rhs, mode: mode)
        }
    }

    static func reordered(_ playlist: [MediaItem], movingIndexes: [Int], to proposedRow: Int) -> [MediaItem] {
        let indexes = Array(Set(movingIndexes)).sorted()
        guard !indexes.isEmpty, indexes.allSatisfy({ playlist.indices.contains($0) }) else {
            return playlist
        }

        let movingItems = indexes.map { playlist[$0] }
        let movingIndexSet = Set(indexes)
        var remainingItems = playlist.enumerated()
            .filter { !movingIndexSet.contains($0.offset) }
            .map(\.element)

        let targetRow = max(0, min(proposedRow, playlist.count))
        let removedBeforeTarget = indexes.filter { $0 < targetRow }.count
        let insertionIndex = max(0, min(targetRow - removedBeforeTarget, remainingItems.count))
        remainingItems.insert(contentsOf: movingItems, at: insertionIndex)
        return remainingItems
    }

    static func removing(_ playlist: [MediaItem], indexes: [Int]) -> [MediaItem] {
        let removedIndexes = Set(indexes.filter { playlist.indices.contains($0) })
        guard !removedIndexes.isEmpty else { return playlist }

        return playlist.enumerated()
            .filter { !removedIndexes.contains($0.offset) }
            .map(\.element)
    }

    static func fileURL(fromPlaylistEntry entry: String, baseDirectory: URL) -> URL {
        let expandedPath = (entry as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        }
        return baseDirectory.appendingPathComponent(entry)
    }

    static func exportedM3U8Text(for playlist: [MediaItem]) -> String {
        var lines = ["#EXTM3U", "#PLAYLIST:Video Player"]
        for item in playlist {
            lines.append("#EXTINF:-1,\(item.title)")
            lines.append(item.url.isFileURL ? item.url.path : item.url.absoluteString)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func comparator(_ lhs: MediaItem, _ rhs: MediaItem, mode: PlaylistSortMode) -> Bool {
        switch mode {
        case .currentOrder:
            return false
        case .title:
            let result = lhs.title.localizedStandardCompare(rhs.title)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        case .mediaType:
            let leftType = lhs.isNetworkStream ? "stream" : lhs.fileExtension
            let rightType = rhs.isNetworkStream ? "stream" : rhs.fileExtension
            let result = leftType.localizedStandardCompare(rightType)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        case .location:
            let result = lhs.subtitle.localizedStandardCompare(rhs.subtitle)
            if result != .orderedSame {
                return result == .orderedAscending
            }
        }

        return lhs.subtitle.localizedStandardCompare(rhs.subtitle) == .orderedAscending
    }
}
