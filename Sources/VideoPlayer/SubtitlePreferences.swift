import Foundation

struct SubtitlePreferences: Codable, Equatable {
    enum SelectionMode: String, Codable, CaseIterable {
        case off = "Off"
        case automatic = "Automatic"
        case preferredLanguage = "Preferred Language"
        case forcedOnly = "Forced Only"
    }

    enum StylePreset: String, Codable, CaseIterable {
        case system = "System"
        case large = "Large"
        case highContrast = "High Contrast"
        case theater = "Theater"
    }

    var selectionMode: SelectionMode
    var preferredLanguage: String
    var stylePreset: StylePreset

    static let `default` = SubtitlePreferences(
        selectionMode: .automatic,
        preferredLanguage: Locale.current.language.languageCode?.identifier ?? "en",
        stylePreset: .system
    )

    var normalizedPreferredLanguage: String {
        preferredLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var summaryLines: [String] {
        [
            "Subtitle mode: \(selectionMode.rawValue)",
            "Preferred language: \(normalizedPreferredLanguage.isEmpty ? "System" : normalizedPreferredLanguage)",
            "Style preset: \(stylePreset.rawValue)"
        ]
    }
}

extension SubtitlePreferences.StylePreset {
    var vlcArguments: [String] {
        switch self {
        case .system:
            []
        case .large:
            [
                "--freetype-rel-fontsize=18",
                "--freetype-outline-thickness=4"
            ]
        case .highContrast:
            [
                "--freetype-rel-fontsize=16",
                "--freetype-color=16777215",
                "--freetype-background-opacity=180",
                "--freetype-outline-thickness=5"
            ]
        case .theater:
            [
                "--freetype-rel-fontsize=14",
                "--freetype-color=16777215",
                "--freetype-background-opacity=90",
                "--freetype-outline-thickness=3"
            ]
        }
    }
}

enum SubtitleTrackSelector {
    static func preferredTrackID(options: [TrackOption], preferences: SubtitlePreferences) -> Int32? {
        switch preferences.selectionMode {
        case .off:
            return options.first(where: { $0.id == -1 })?.id
        case .automatic:
            return options.first(where: { $0.id != -1 })?.id
        case .preferredLanguage:
            let language = preferences.normalizedPreferredLanguage
            guard !language.isEmpty else {
                return options.first(where: { $0.id != -1 })?.id
            }
            return options.first {
                $0.id != -1 && subtitleName($0.name, matchesLanguage: language)
            }?.id ?? options.first(where: { $0.id != -1 })?.id
        case .forcedOnly:
            return options.first {
                $0.id != -1 && $0.name.localizedCaseInsensitiveContains("forced")
            }?.id
        }
    }

    private static func subtitleName(_ name: String, matchesLanguage language: String) -> Bool {
        let normalizedName = name.lowercased()
        if normalizedName.contains(language) {
            return true
        }

        let localizedName = Locale.current.localizedString(forLanguageCode: language)?.lowercased()
        if let localizedName, normalizedName.contains(localizedName) {
            return true
        }

        return false
    }
}
