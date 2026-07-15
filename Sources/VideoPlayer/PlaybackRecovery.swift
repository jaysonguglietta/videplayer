import Foundation

struct PlaybackRecoveryState: Equatable {
    let previousSessionEndedCleanly: Bool
    let lastPlaybackTitle: String?
    let lastPlaybackURL: String?
    let lastPlaybackAt: Date?
    let lastHangWarningAt: Date?

    var text: String {
        [
            "Playback Recovery Report",
            "========================",
            "Previous session ended cleanly: \(previousSessionEndedCleanly ? "Yes" : "No")",
            "Last playback title: \(lastPlaybackTitle ?? "--")",
            "Last playback URL: \(lastPlaybackURL ?? "--")",
            "Last playback at: \(lastPlaybackAt.map(Self.dateFormatter.string(from:)) ?? "--")",
            "Last hang warning at: \(lastHangWarningAt.map(Self.dateFormatter.string(from:)) ?? "--")",
            "",
            previousSessionEndedCleanly
                ? "No crash or force-quit indicator was recorded for the previous app session."
                : "The previous app session did not record a clean shutdown. If playback locked up, export a support bundle and include the log."
        ].joined(separator: "\n")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum PlaybackRecovery {
    private enum Key {
        static let cleanShutdown = "recovery.cleanShutdown"
        static let previousCleanShutdown = "recovery.previousCleanShutdown"
        static let lastPlaybackTitle = "recovery.lastPlaybackTitle"
        static let lastPlaybackURL = "recovery.lastPlaybackURL"
        static let lastPlaybackAt = "recovery.lastPlaybackAt"
        static let lastHangWarningAt = "recovery.lastHangWarningAt"
    }

    static func markLaunch(defaults: UserDefaults = .standard) {
        let previousValue = defaults.object(forKey: Key.cleanShutdown) as? Bool ?? true
        defaults.set(previousValue, forKey: Key.previousCleanShutdown)
        defaults.set(false, forKey: Key.cleanShutdown)
    }

    static func markCleanShutdown(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Key.cleanShutdown)
    }

    static func recordPlayback(item: MediaItem, defaults: UserDefaults = .standard, date: Date = Date()) {
        defaults.set(item.title, forKey: Key.lastPlaybackTitle)
        defaults.set(MediaPersistence.storageString(for: item.url), forKey: Key.lastPlaybackURL)
        defaults.set(date, forKey: Key.lastPlaybackAt)
    }

    static func recordHangWarning(defaults: UserDefaults = .standard, date: Date = Date()) {
        defaults.set(date, forKey: Key.lastHangWarningAt)
    }

    static func state(defaults: UserDefaults = .standard) -> PlaybackRecoveryState {
        PlaybackRecoveryState(
            previousSessionEndedCleanly: defaults.object(forKey: Key.previousCleanShutdown) as? Bool ?? true,
            lastPlaybackTitle: defaults.string(forKey: Key.lastPlaybackTitle),
            lastPlaybackURL: defaults.string(forKey: Key.lastPlaybackURL),
            lastPlaybackAt: defaults.object(forKey: Key.lastPlaybackAt) as? Date,
            lastHangWarningAt: defaults.object(forKey: Key.lastHangWarningAt) as? Date
        )
    }
}
