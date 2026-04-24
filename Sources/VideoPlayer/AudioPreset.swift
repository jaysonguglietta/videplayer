import Foundation

enum AudioPreset: String, CaseIterable {
    case flat = "Flat"
    case speechBoost = "Speech Boost"
    case bassBoost = "Bass Boost"
    case nightMode = "Night Mode"

    var preamp: Float {
        switch self {
        case .flat:
            0
        case .speechBoost:
            2
        case .bassBoost:
            1
        case .nightMode:
            -3
        }
    }

    var bandAdjustments: [Float] {
        switch self {
        case .flat:
            Array(repeating: 0, count: 10)
        case .speechBoost:
            [-4, -3, -2, 1, 3, 4, 3, 1, -1, -2]
        case .bassBoost:
            [6, 5, 4, 2, 0, -1, -1, 0, 1, 1]
        case .nightMode:
            [-2, -1, 0, 1, 2, 2, 1, 0, -1, -2]
        }
    }
}
