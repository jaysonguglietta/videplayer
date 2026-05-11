import AVFoundation
import CoreMedia
import Foundation

struct NativePlaybackAssessment: Equatable {
    enum Routing: Equatable {
        case native
        case preferExternal
        case requiresExternal
    }

    let routing: Routing
    let reason: String?
    let detectedVideoCodecs: Set<String>

    static let native = NativePlaybackAssessment(
        routing: .native,
        reason: nil,
        detectedVideoCodecs: []
    )

    var prefersExternalEngine: Bool {
        routing == .preferExternal || routing == .requiresExternal
    }

    var requiresExternalEngine: Bool {
        routing == .requiresExternal
    }
}

enum NativePlaybackPolicy {
    private static let dolbyVisionCodecs: Set<String> = ["dvh1", "dvhe"]
    private static let hevcCodecs: Set<String> = ["hvc1", "hev1"]

    static func assessment(
        for item: MediaItem,
        nativeExtensions: Set<String>
    ) async -> NativePlaybackAssessment {
        guard item.url.isFileURL else {
            return .native
        }

        let videoCodecs = await videoCodecs(for: item.url)
        return assessment(
            fileExtension: item.fileExtension,
            nativeExtensions: nativeExtensions,
            videoCodecs: videoCodecs
        )
    }

    static func assessment(
        fileExtension: String,
        nativeExtensions: Set<String>,
        videoCodecs: Set<String>
    ) -> NativePlaybackAssessment {
        let normalizedExtension = fileExtension.lowercased()
        let normalizedCodecs = Set(videoCodecs.map { $0.lowercased() })

        if !normalizedCodecs.isDisjoint(with: dolbyVisionCodecs) {
            return NativePlaybackAssessment(
                routing: .requiresExternal,
                reason: "This file uses Dolby Vision/HEVC video (\(codecSummary(normalizedCodecs))). AVFoundation can expose those files as audio-only, so playback needs a trusted VLC/mpv engine.",
                detectedVideoCodecs: normalizedCodecs
            )
        }

        if !normalizedCodecs.isDisjoint(with: hevcCodecs) {
            return NativePlaybackAssessment(
                routing: .preferExternal,
                reason: "This file uses HEVC/x265 video (\(codecSummary(normalizedCodecs))). A trusted VLC/mpv engine is preferred when available.",
                detectedVideoCodecs: normalizedCodecs
            )
        }

        if !normalizedExtension.isEmpty, !nativeExtensions.contains(normalizedExtension) {
            return NativePlaybackAssessment(
                routing: .requiresExternal,
                reason: "This file type is outside the Apple-native playback list. Playback needs a trusted VLC/mpv engine.",
                detectedVideoCodecs: normalizedCodecs
            )
        }

        return NativePlaybackAssessment(
            routing: .native,
            reason: nil,
            detectedVideoCodecs: normalizedCodecs
        )
    }

    static func hasVideoTrack(_ item: MediaItem) async -> Bool {
        guard item.url.isFileURL else {
            return true
        }

        let asset = AVURLAsset(url: item.url)
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        return !videoTracks.isEmpty
    }

    private static func videoCodecs(for url: URL) async -> Set<String> {
        AppLogger.debug("Reading AVFoundation video format descriptions for \(url.path)")
        let asset = AVURLAsset(url: url)
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        var codecs = Set<String>()

        for track in videoTracks {
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            for description in descriptions {
                let subtype = CMFormatDescriptionGetMediaSubType(description)
                let codec = fourCCString(from: subtype).lowercased()
                if !codec.isEmpty {
                    codecs.insert(codec)
                }
            }
        }

        AppLogger.debug("Detected video codecs for \(url.lastPathComponent): \(codecs.sorted().joined(separator: ","))")
        return codecs
    }

    private static func codecSummary(_ codecs: Set<String>) -> String {
        let sortedCodecs = codecs.sorted()
        return sortedCodecs.isEmpty ? "unknown codec" : sortedCodecs.joined(separator: ", ")
    }

    private static func fourCCString(from code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)) ?? ""
    }
}

enum NativePlaybackError: LocalizedError {
    case audioOnlyVideo

    var errorDescription: String? {
        switch self {
        case .audioOnlyVideo:
            "macOS started the audio track but did not produce a video frame. This file likely needs a trusted VLC/mpv engine for its video codec."
        }
    }
}
