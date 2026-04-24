import Foundation

struct VideoAdjustments: Equatable {
    var brightness = 1.0
    var contrast = 1.0
    var saturation = 1.0
    var hue = 0.0
    var gamma = 1.0

    var isDefault: Bool {
        self == VideoAdjustments()
    }
}

enum VideoAdjustmentKey: String, CaseIterable {
    case brightness
    case contrast
    case saturation
    case hue
    case gamma

    var title: String {
        switch self {
        case .brightness:
            "Brightness"
        case .contrast:
            "Contrast"
        case .saturation:
            "Saturation"
        case .hue:
            "Hue"
        case .gamma:
            "Gamma"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness, .contrast:
            0.0...2.0
        case .saturation:
            0.0...3.0
        case .hue:
            -180.0...180.0
        case .gamma:
            0.1...3.0
        }
    }

    var defaultValue: Double {
        switch self {
        case .hue:
            0.0
        case .brightness, .contrast, .saturation, .gamma:
            1.0
        }
    }
}
