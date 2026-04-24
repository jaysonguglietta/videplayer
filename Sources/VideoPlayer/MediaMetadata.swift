import AVFoundation
import Foundation

struct MediaMetadata {
    let title: String
    let location: String
    let kind: String
    let size: String
    let duration: String
    let dimensions: String
    let modified: String
    let savedPosition: String
    let extraDetails: [String]

    static func inspect(item: MediaItem, savedPosition: Double, vlcInspection: VLCMediaInspection? = nil) async -> MediaMetadata {
        let url = item.url
        let title = vlcInspection?.preferredTitle ?? item.title

        guard url.isFileURL else {
            return MediaMetadata(
                title: title,
                location: url.absoluteString,
                kind: "Network Stream",
                size: "--",
                duration: vlcInspection?.duration.map(formatTime) ?? "--",
                dimensions: "--",
                modified: "--",
                savedPosition: savedPosition > 0 ? formatTime(savedPosition) : "--",
                extraDetails: vlcInspection?.detailLines ?? []
            )
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = attributes?[.size] as? NSNumber
        let modifiedDate = attributes?[.modificationDate] as? Date
        let asset = AVURLAsset(url: url)
        let loadedDuration = try? await asset.load(.duration)
        let durationSeconds = loadedDuration?.seconds ?? 0
        let videoTrack = (try? await asset.loadTracks(withMediaType: .video))?.first
        let naturalSize: CGSize

        if let videoTrack {
            let size = (try? await videoTrack.load(.naturalSize)) ?? .zero
            let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
            naturalSize = size.applying(transform)
        } else {
            naturalSize = .zero
        }

        let width = Int(abs(naturalSize.width).rounded())
        let height = Int(abs(naturalSize.height).rounded())

        return MediaMetadata(
            title: title,
            location: url.path,
            kind: url.pathExtension.uppercased().isEmpty ? "File" : url.pathExtension.uppercased(),
            size: byteCount.map { byteFormatter.string(fromByteCount: $0.int64Value) } ?? "--",
            duration: durationSeconds.isFinite && durationSeconds > 0
                ? formatTime(durationSeconds)
                : (vlcInspection?.duration.map(formatTime) ?? "--"),
            dimensions: width > 0 && height > 0 ? "\(width)x\(height)" : "--",
            modified: modifiedDate.map { dateFormatter.string(from: $0) } ?? "--",
            savedPosition: savedPosition > 0 ? formatTime(savedPosition) : "--",
            extraDetails: vlcInspection?.detailLines ?? []
        )
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--" }
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
