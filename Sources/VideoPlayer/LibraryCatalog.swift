import Foundation

struct MediaLibraryRecord: Codable, Equatable {
    var isFavorite: Bool
    var isWatched: Bool
    var tags: [String]
    var updatedAt: Date

    static let empty = MediaLibraryRecord(
        isFavorite: false,
        isWatched: false,
        tags: [],
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

struct LibraryCatalogReport: Equatable {
    let totalItems: Int
    let localItems: Int
    let streamItems: Int
    let missingLocalFiles: Int
    let favorites: Int
    let watched: Int
    let tags: [String: Int]

    var text: String {
        var lines = [
            "Library Report",
            "==============",
            "Playlist items: \(totalItems)",
            "Local files: \(localItems)",
            "Network streams: \(streamItems)",
            "Missing local files: \(missingLocalFiles)",
            "Favorites: \(favorites)",
            "Watched: \(watched)",
            "",
            "Tags"
        ]

        if tags.isEmpty {
            lines.append("No tags")
        } else {
            lines.append(contentsOf: tags.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })
        }

        return lines.joined(separator: "\n")
    }
}

enum LibraryCatalog {
    static func report(playlist: [MediaItem], records: [String: MediaLibraryRecord]) -> LibraryCatalogReport {
        var tagCounts: [String: Int] = [:]
        let localItems = playlist.filter { $0.url.isFileURL }.count
        let streamItems = playlist.count - localItems
        let missingLocalFiles = playlist.filter {
            $0.url.isFileURL && !FileManager.default.fileExists(atPath: $0.url.path)
        }.count

        let itemRecords = playlist.compactMap { records[MediaPersistence.storageString(for: $0.url)] }
        for record in itemRecords {
            for tag in record.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        return LibraryCatalogReport(
            totalItems: playlist.count,
            localItems: localItems,
            streamItems: streamItems,
            missingLocalFiles: missingLocalFiles,
            favorites: itemRecords.filter(\.isFavorite).count,
            watched: itemRecords.filter(\.isWatched).count,
            tags: tagCounts
        )
    }

    static func normalizedTags(from text: String) -> [String] {
        Array(Set(text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })).sorted()
    }
}
