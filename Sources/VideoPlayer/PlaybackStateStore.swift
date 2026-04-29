import Foundation

final class PlaybackStateStore {
    private enum Key {
        static let playlist = "playlist"
        static let currentIndex = "currentIndex"
        static let positions = "positions"
        static let volume = "volume"
        static let speed = "speed"
        static let recentMedia = "recentMedia"
        static let libraryFolders = "libraryFolders"
        static let audioPreset = "audioPreset"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savePlaylist(_ playlist: [MediaItem], currentIndex: Int?) {
        defaults.set(playlist.map { MediaPersistence.storageString(for: $0.url) }, forKey: Key.playlist)
        defaults.set(currentIndex, forKey: Key.currentIndex)
    }

    func loadPlaylist() -> ([MediaItem], Int?) {
        let urls = sanitizedURLStrings(forKey: Key.playlist)
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

    func saveAudioPreset(_ preset: String) {
        defaults.set(preset, forKey: Key.audioPreset)
    }

    func loadAudioPreset() -> String? {
        defaults.string(forKey: Key.audioPreset)
    }

    func addRecentMedia(_ item: MediaItem) {
        var values = defaults.stringArray(forKey: Key.recentMedia) ?? []
        let storageString = MediaPersistence.storageString(for: item.url)
        values.removeAll { $0 == storageString || $0 == item.url.absoluteString }
        values.insert(storageString, at: 0)
        defaults.set(Array(values.prefix(12)), forKey: Key.recentMedia)
    }

    func loadRecentMedia() -> [MediaItem] {
        sanitizedURLStrings(forKey: Key.recentMedia).compactMap { value in
            guard let url = URL(string: value) else { return nil }
            if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
                return nil
            }
            return MediaItem(url: url)
        }
    }

    func clearRecentMedia() {
        defaults.removeObject(forKey: Key.recentMedia)
    }

    func addLibraryFolder(_ url: URL) {
        var values = defaults.stringArray(forKey: Key.libraryFolders) ?? []
        values.removeAll { $0 == url.absoluteString }
        values.insert(url.absoluteString, at: 0)
        defaults.set(Array(values.prefix(8)), forKey: Key.libraryFolders)
    }

    func loadLibraryFolders() -> [URL] {
        (defaults.stringArray(forKey: Key.libraryFolders) ?? []).compactMap { value in
            guard let url = URL(string: value), url.isFileURL else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return url
        }
    }

    func position(for item: MediaItem) -> Double {
        positions()[MediaPersistence.storageString(for: item.url)] ?? 0
    }

    func savePosition(_ seconds: Double, for item: MediaItem) {
        var positions = positions()
        let key = MediaPersistence.storageString(for: item.url)
        if seconds > 5 {
            positions[key] = seconds
        } else {
            positions.removeValue(forKey: key)
        }
        positions.removeValue(forKey: item.url.absoluteString)
        defaults.set(positions, forKey: Key.positions)
    }

    func clearPosition(for item: MediaItem) {
        var positions = positions()
        positions.removeValue(forKey: MediaPersistence.storageString(for: item.url))
        positions.removeValue(forKey: item.url.absoluteString)
        defaults.set(positions, forKey: Key.positions)
    }

    private func sanitizedURLStrings(forKey key: String) -> [String] {
        let values = defaults.stringArray(forKey: key) ?? []
        let sanitizedValues = values.map(MediaPersistence.storageString(forStoredValue:))
        if sanitizedValues != values {
            defaults.set(sanitizedValues, forKey: key)
        }
        return sanitizedValues
    }

    private func positions() -> [String: Double] {
        let storedPositions = defaults.dictionary(forKey: Key.positions) as? [String: Double] ?? [:]
        var sanitizedPositions: [String: Double] = [:]
        var didSanitize = false

        for (key, value) in storedPositions {
            let sanitizedKey = MediaPersistence.storageString(forStoredValue: key)
            didSanitize = didSanitize || sanitizedKey != key
            sanitizedPositions[sanitizedKey] = value
        }

        if didSanitize {
            defaults.set(sanitizedPositions, forKey: Key.positions)
        }
        return sanitizedPositions
    }
}
