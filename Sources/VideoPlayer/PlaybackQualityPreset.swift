import Foundation

enum PlaybackQualityPreset: String, CaseIterable {
    case neutral = "Neutral"
    case cinema = "Cinema"
    case brightRoom = "Bright Room"
    case vivid = "Vivid"
    case lowLight = "Low Light"

    var videoAdjustments: VideoAdjustments {
        switch self {
        case .neutral:
            VideoAdjustments()
        case .cinema:
            VideoAdjustments(brightness: 0.98, contrast: 1.12, saturation: 1.08, hue: 0, gamma: 1.04)
        case .brightRoom:
            VideoAdjustments(brightness: 1.16, contrast: 1.10, saturation: 1.05, hue: 0, gamma: 0.94)
        case .vivid:
            VideoAdjustments(brightness: 1.04, contrast: 1.22, saturation: 1.35, hue: 0, gamma: 1.0)
        case .lowLight:
            VideoAdjustments(brightness: 0.88, contrast: 1.08, saturation: 0.95, hue: 0, gamma: 1.18)
        }
    }

    var audioPreset: AudioPreset {
        switch self {
        case .neutral:
            .flat
        case .cinema, .vivid:
            .bassBoost
        case .brightRoom:
            .speechBoost
        case .lowLight:
            .nightMode
        }
    }
}
