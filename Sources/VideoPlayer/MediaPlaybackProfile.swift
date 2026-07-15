import Foundation

struct MediaPlaybackProfile: Codable, Equatable {
    let speedTitle: String
    let audioPresetName: String
    let qualityPresetName: String
    let audioDelaySeconds: Double
    let subtitleDelaySeconds: Double
    let updatedAt: Date

    static let `default` = MediaPlaybackProfile(
        speedTitle: "1x",
        audioPresetName: AudioPreset.flat.rawValue,
        qualityPresetName: PlaybackQualityPreset.neutral.rawValue,
        audioDelaySeconds: 0,
        subtitleDelaySeconds: 0,
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    var audioPreset: AudioPreset {
        AudioPreset(rawValue: audioPresetName) ?? .flat
    }

    var qualityPreset: PlaybackQualityPreset {
        PlaybackQualityPreset(rawValue: qualityPresetName) ?? .neutral
    }
}
