import AppKit
import AVFoundation
import CryptoKit
import Foundation

struct SavedMediaMetadata: Codable, Equatable {
    struct Field: Codable, Equatable {
        let name: String
        let value: String
    }

    let schemaVersion: Int
    let sourceKey: String
    let sourceURL: String
    let title: String
    let kind: String
    let size: String
    let duration: String
    let dimensions: String
    let modified: String
    let savedPosition: String
    let location: String
    let fields: [Field]
    let posterFileName: String?
    let savedAt: Date
}

struct MediaMetadataSaveResult: Equatable {
    let metadataURL: URL
    let posterURL: URL?

    var summary: String {
        posterURL == nil ? "Metadata saved; poster unavailable" : "Metadata + poster saved"
    }
}

enum MediaMetadataCacheError: LocalizedError {
    case posterEncodingFailed
    case metadataNotSaved
    case posterTooLarge

    var errorDescription: String? {
        switch self {
        case .posterEncodingFailed:
            return "The poster image could not be encoded."
        case .metadataNotSaved:
            return "Save metadata for this item before replacing its poster."
        case .posterTooLarge:
            return "Poster images must be 20 MB or smaller."
        }
    }
}

struct MediaMetadataCache {
    let directory: URL
    private let fileManager: FileManager

    init(directory: URL = MediaMetadataCache.defaultDirectory(), fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    static func defaultDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Video Player", isDirectory: true)
            .appendingPathComponent("Saved Metadata", isDirectory: true)
    }

    func save(
        item: MediaItem,
        metadata: MediaMetadata,
        posterData: Data?,
        savedAt: Date = Date()
    ) throws -> MediaMetadataSaveResult {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let key = Self.key(for: item.url)
        var posterFileName: String?
        var posterURL: URL?

        if let posterData {
            let fileName = "\(key).png"
            let url = directory.appendingPathComponent(fileName, isDirectory: false)
            try posterData.write(to: url, options: .atomic)
            posterFileName = fileName
            posterURL = url
        }

        let saved = SavedMediaMetadata(
            schemaVersion: 1,
            sourceKey: key,
            sourceURL: MediaPersistence.storageString(for: item.url),
            title: metadata.title,
            kind: metadata.kind,
            size: metadata.size,
            duration: metadata.duration,
            dimensions: metadata.dimensions,
            modified: metadata.modified,
            savedPosition: metadata.savedPosition,
            location: metadata.location,
            fields: metadata.extraDetails.map { SavedMediaMetadata.Field(name: "Detail", value: $0) },
            posterFileName: posterFileName,
            savedAt: savedAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let metadataURL = directory.appendingPathComponent("\(key).json", isDirectory: false)
        try encoder.encode(saved).write(to: metadataURL, options: .atomic)

        return MediaMetadataSaveResult(metadataURL: metadataURL, posterURL: posterURL)
    }

    func load(item: MediaItem) throws -> SavedMediaMetadata? {
        let url = metadataURL(for: item)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SavedMediaMetadata.self, from: Data(contentsOf: url))
    }

    func metadataURL(for item: MediaItem) -> URL {
        directory.appendingPathComponent("\(Self.key(for: item.url)).json", isDirectory: false)
    }

    func posterURL(for item: MediaItem) -> URL {
        directory.appendingPathComponent("\(Self.key(for: item.url)).png", isDirectory: false)
    }

    func storedPosterURL(for item: MediaItem) -> URL? {
        guard let saved = try? load(item: item), saved.posterFileName != nil else { return nil }
        let url = posterURL(for: item)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func replacePoster(item: MediaItem, imageData: Data, savedAt: Date = Date()) throws -> URL {
        guard imageData.count <= 20_000_000 else {
            throw MediaMetadataCacheError.posterTooLarge
        }
        guard let saved = try load(item: item) else {
            throw MediaMetadataCacheError.metadataNotSaved
        }
        guard let pngData = Self.pngData(fromImageData: imageData) else {
            throw MediaMetadataCacheError.posterEncodingFailed
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let posterURL = posterURL(for: item)
        try pngData.write(to: posterURL, options: .atomic)
        try write(
            replacing(saved, posterFileName: posterURL.lastPathComponent, savedAt: savedAt),
            to: metadataURL(for: item)
        )
        return posterURL
    }

    func removePoster(item: MediaItem, savedAt: Date = Date()) throws {
        guard let saved = try load(item: item) else {
            throw MediaMetadataCacheError.metadataNotSaved
        }
        let posterURL = posterURL(for: item)
        if fileManager.fileExists(atPath: posterURL.path) {
            try fileManager.removeItem(at: posterURL)
        }
        try write(
            replacing(saved, posterFileName: nil, savedAt: savedAt),
            to: metadataURL(for: item)
        )
    }

    func clearAll() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    static func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(MediaPersistence.storageString(for: url).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func posterData(for item: MediaItem, preferredTimeSeconds: Double?) async -> Data? {
        guard item.url.isFileURL else { return nil }

        let asset = AVURLAsset(url: item.url)
        if let artwork = await embeddedArtworkData(from: asset) {
            return artwork
        }

        return await framePosterData(from: asset, preferredTimeSeconds: preferredTimeSeconds)
    }

    private static func embeddedArtworkData(from asset: AVURLAsset) async -> Data? {
        guard let commonMetadata = try? await asset.load(.commonMetadata) else { return nil }
        let artworkItems = AVMetadataItem.metadataItems(
            from: commonMetadata,
            filteredByIdentifier: .commonIdentifierArtwork
        )

        for artwork in artworkItems {
            guard let data = try? await artwork.load(.dataValue) else { continue }
            return pngData(fromImageData: data) ?? data
        }
        return nil
    }

    private static func framePosterData(from asset: AVURLAsset, preferredTimeSeconds: Double?) async -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
        let preferred = preferredTimeSeconds.flatMap { seconds -> Double? in
            guard seconds.isFinite, seconds > 0 else { return nil }
            if durationSeconds.isFinite, durationSeconds > 0 {
                return min(seconds, max(durationSeconds - 0.1, 0))
            }
            return seconds
        }

        let candidateSeconds = [preferred, 1.0, 0.0].compactMap(\.self)
        for seconds in candidateSeconds {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            let representation = NSBitmapImageRep(cgImage: cgImage)
            return representation.representation(using: .png, properties: [:])
        }
        return nil
    }

    private static func pngData(fromImageData data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    private func replacing(
        _ saved: SavedMediaMetadata,
        posterFileName: String?,
        savedAt: Date
    ) -> SavedMediaMetadata {
        SavedMediaMetadata(
            schemaVersion: saved.schemaVersion,
            sourceKey: saved.sourceKey,
            sourceURL: saved.sourceURL,
            title: saved.title,
            kind: saved.kind,
            size: saved.size,
            duration: saved.duration,
            dimensions: saved.dimensions,
            modified: saved.modified,
            savedPosition: saved.savedPosition,
            location: saved.location,
            fields: saved.fields,
            posterFileName: posterFileName,
            savedAt: savedAt
        )
    }

    private func write(_ saved: SavedMediaMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(saved).write(to: url, options: .atomic)
    }
}
