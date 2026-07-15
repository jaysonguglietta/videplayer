import Foundation

enum PlaybackEngineKind: String, Codable, Equatable {
    case none
    case native
    case vlc
    case mpv

    var displayName: String {
        switch self {
        case .none: "None"
        case .native: "AVFoundation"
        case .vlc: "VLC"
        case .mpv: "mpv"
        }
    }
}

struct PlaybackRouteContext: Equatable {
    let item: MediaItem
    let nativeAssessment: NativePlaybackAssessment
    let nativeExtensions: Set<String>
    let vlcAvailable: Bool
    let mpvAvailable: Bool
}

enum PlaybackRoutePlanner {
    static func route(for context: PlaybackRouteContext) -> PlaybackEngineKind {
        if context.vlcAvailable {
            return .vlc
        }

        let shouldUseMPV = context.item.isNetworkStream
            || !context.nativeExtensions.contains(context.item.fileExtension)
            || context.nativeAssessment.prefersExternalEngine
        if shouldUseMPV, context.mpvAvailable {
            return .mpv
        }

        return context.nativeAssessment.requiresExternalEngine ? .none : .native
    }
}
