import Foundation

final class PlaybackStateStore {
    private enum Key {
        static let playlist = "playlist"
        static let currentIndex = "currentIndex"
        static let positions = "positions"
        static let volume = "volume"
        static let speed = "speed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savePlaylist(_ playlist: [MediaItem], currentIndex: Int?) {
        defaults.set(playlist.map(\.url.absoluteString), forKey: Key.playlist)
        defaults.set(currentIndex, forKey: Key.currentIndex)
    }

    func loadPlaylist() -> ([MediaItem], Int?) {
        let urls = defaults.stringArray(forKey: Key.playlist) ?? []
        let items = urls.compactMap { value -> MediaItem? in
            guard let url = URL(string: value) else { return nil }
            if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
                return nil
            }
            return MediaItem(url: url)
        }

        let index = defaults.object(forKey: Key.currentIndex) as? Int
        return (items, index)
    }

    func saveVolume(_ volume: Double) {
        defaults.set(volume, forKey: Key.volume)
    }

    func loadVolume(default defaultVolume: Double) -> Double {
        guard defaults.object(forKey: Key.volume) != nil else { return defaultVolume }
        return defaults.double(forKey: Key.volume)
    }

    func saveSpeedTitle(_ title: String) {
        defaults.set(title, forKey: Key.speed)
    }

    func loadSpeedTitle() -> String? {
        defaults.string(forKey: Key.speed)
    }

    func position(for item: MediaItem) -> Double {
        positions()[item.persistenceKey] ?? 0
    }

    func savePosition(_ seconds: Double, for item: MediaItem) {
        var positions = positions()
        if seconds > 5 {
            positions[item.persistenceKey] = seconds
        } else {
            positions.removeValue(forKey: item.persistenceKey)
        }
        defaults.set(positions, forKey: Key.positions)
    }

    func clearPosition(for item: MediaItem) {
        var positions = positions()
        positions.removeValue(forKey: item.persistenceKey)
        defaults.set(positions, forKey: Key.positions)
    }

    private func positions() -> [String: Double] {
        defaults.dictionary(forKey: Key.positions) as? [String: Double] ?? [:]
    }
}
