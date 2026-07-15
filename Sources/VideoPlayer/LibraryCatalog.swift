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
    let qualityCounts: [String: Int]
    let duplicateOrVersionGroups: Int
    let tvEpisodeGroups: Int
    let largestGroups: [String]

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
            "Duplicate/version groups: \(duplicateOrVersionGroups)",
            "TV episode groups: \(tvEpisodeGroups)",
            "",
            "Quality",
            qualityCounts.isEmpty
                ? "No quality tags detected"
                : qualityCounts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"),
            "",
            "Tags"
        ]

        if tags.isEmpty {
            lines.append("No tags")
        } else {
            lines.append(contentsOf: tags.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })
        }

        lines.append("")
        lines.append("Largest Groups")
        if largestGroups.isEmpty {
            lines.append("No grouped versions detected")
        } else {
            lines.append(contentsOf: largestGroups)
        }

        return lines.joined(separator: "\n")
    }
}

enum LibraryCatalog {
    static func report(playlist: [MediaItem], records: [String: MediaLibraryRecord]) -> LibraryCatalogReport {
        var tagCounts: [String: Int] = [:]
        var qualityCounts: [String: Int] = [:]
        var normalizedGroups: [String: Int] = [:]
        var tvGroups: [String: Int] = [:]
        let localItems = playlist.filter { $0.url.isFileURL }.count
        let streamItems = playlist.count - localItems
        let missingLocalFiles = playlist.filter {
            $0.url.isFileURL && !FileManager.default.fileExists(atPath: $0.url.path)
        }.count

        for item in playlist {
            qualityCounts[qualityBucket(for: item), default: 0] += 1
            let groupKey = normalizedGroupKey(for: item)
            normalizedGroups[groupKey, default: 0] += 1
            if let tvKey = tvEpisodeGroupKey(for: item) {
                tvGroups[tvKey, default: 0] += 1
            }
        }

        let itemRecords = playlist.compactMap { records[MediaPersistence.storageString(for: $0.url)] }
        for record in itemRecords {
            for tag in record.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        let largestGroups = normalizedGroups
            .filter { $0.value > 1 }
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(6)
            .map { "\($0.key): \($0.value) versions" }

        return LibraryCatalogReport(
            totalItems: playlist.count,
            localItems: localItems,
            streamItems: streamItems,
            missingLocalFiles: missingLocalFiles,
            favorites: itemRecords.filter(\.isFavorite).count,
            watched: itemRecords.filter(\.isWatched).count,
            tags: tagCounts,
            qualityCounts: qualityCounts,
            duplicateOrVersionGroups: normalizedGroups.values.filter { $0 > 1 }.count,
            tvEpisodeGroups: tvGroups.count,
            largestGroups: Array(largestGroups)
        )
    }

    static func normalizedTags(from text: String) -> [String] {
        Array(Set(text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })).sorted()
    }

    static func qualityBucket(for item: MediaItem) -> String {
        let name = item.title.lowercased()
        if name.contains("2160p") || name.contains("4k") || name.contains("uhd") {
            return "4K/UHD"
        }
        if name.contains("1080p") || name.contains("fhd") {
            return "1080p"
        }
        if name.contains("720p") || name.contains("hd") {
            return "720p"
        }
        if name.contains("480p") || name.contains("dvd") || name.contains("sd") {
            return "SD"
        }
        return "Unknown"
    }

    static func normalizedGroupKey(for item: MediaItem) -> String {
        let base = item.title
            .lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let tokensToRemove = [
            "2160p", "1080p", "720p", "480p", "4k", "uhd", "hdr", "dv", "bluray", "blu ray",
            "web", "webrip", "webdl", "web dl", "hdtv", "x264", "x265", "h264", "h265", "hevc",
            "aac", "dts", "truehd", "atmos", "remux", "proper", "repack"
        ]
        var normalized = base
        for token in tokensToRemove {
            normalized = normalized.replacingOccurrences(of: token, with: " ")
        }
        normalized = normalized.replacingOccurrences(
            of: #"\b(19|20)\d{2}\b"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tvEpisodeGroupKey(for item: MediaItem) -> String? {
        let normalized = item.title.lowercased()
        guard let range = normalized.range(
            of: #"s\d{1,2}e\d{1,3}"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let prefix = normalized[..<range.lowerBound]
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let seasonEpisode = String(normalized[range])
        let season = seasonEpisode.prefix { $0 != "e" }
        return "\(prefix) \(season)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
