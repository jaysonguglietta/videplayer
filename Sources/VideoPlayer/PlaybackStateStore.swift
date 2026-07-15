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
        static let libraryFolderBookmarks = "libraryFolderBookmarks"
        static let audioPreset = "audioPreset"
        static let playlistSortMode = "playlistSortMode"
        static let mediaLibraryRecords = "mediaLibraryRecords"
        static let streamBookmarks = "streamBookmarks"
        static let subtitlePreferences = "subtitlePreferences"
        static let playbackProfiles = "playbackProfiles"
        static let libraryDatabaseMigrationVersion = "libraryDatabaseMigrationVersion"
    }

    private let defaults: UserDefaults
    private let libraryDatabase: LibraryDatabase?

    init(defaults: UserDefaults = .standard, libraryDatabase: LibraryDatabase? = nil) {
        self.defaults = defaults
        self.libraryDatabase = libraryDatabase
        migrateLegacyLibraryDataIfNeeded()
    }

    func savePlaylist(_ playlist: [MediaItem], currentIndex: Int?) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else {
            defaults.removeObject(forKey: Key.playlist)
            defaults.removeObject(forKey: Key.currentIndex)
            return
        }
        defaults.set(playlist.map { MediaPersistence.storageString(for: $0.url) }, forKey: Key.playlist)
        defaults.set(currentIndex, forKey: Key.currentIndex)
    }

    func loadPlaylist() -> ([MediaItem], Int?) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else {
            return ([], nil)
        }
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

    func saveSubtitlePreferences(_ preferences: SubtitlePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Key.subtitlePreferences)
    }

    func loadSubtitlePreferences() -> SubtitlePreferences {
        guard let data = defaults.data(forKey: Key.subtitlePreferences),
              let preferences = try? JSONDecoder().decode(SubtitlePreferences.self, from: data)
        else {
            return .default
        }
        return preferences
    }

    func savePlaylistSortMode(_ mode: String) {
        defaults.set(mode, forKey: Key.playlistSortMode)
    }

    func loadPlaylistSortMode() -> String? {
        defaults.string(forKey: Key.playlistSortMode)
    }

    func addRecentMedia(_ item: MediaItem) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return }
        var values = defaults.stringArray(forKey: Key.recentMedia) ?? []
        let storageString = MediaPersistence.storageString(for: item.url)
        values.removeAll { $0 == storageString || $0 == item.url.absoluteString }
        values.insert(storageString, at: 0)
        defaults.set(Array(values.prefix(12)), forKey: Key.recentMedia)
    }

    func loadRecentMedia() -> [MediaItem] {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else {
            return []
        }
        return sanitizedURLStrings(forKey: Key.recentMedia).compactMap { value in
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

    func addStreamBookmark(_ item: MediaItem) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults), item.isNetworkStream else { return }
        var values = defaults.stringArray(forKey: Key.streamBookmarks) ?? []
        let storageString = MediaPersistence.storageString(for: item.url)
        values.removeAll { $0 == storageString || $0 == item.url.absoluteString }
        values.insert(storageString, at: 0)
        defaults.set(Array(values.prefix(50)), forKey: Key.streamBookmarks)
    }

    func removeStreamBookmark(_ item: MediaItem) {
        var values = defaults.stringArray(forKey: Key.streamBookmarks) ?? []
        let storageString = MediaPersistence.storageString(for: item.url)
        values.removeAll { $0 == storageString || $0 == item.url.absoluteString }
        defaults.set(values, forKey: Key.streamBookmarks)
    }

    func loadStreamBookmarks() -> [MediaItem] {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return [] }
        return sanitizedURLStrings(forKey: Key.streamBookmarks).compactMap { value in
            guard let url = URL(string: value), !url.isFileURL else { return nil }
            return MediaItem(url: url)
        }
    }

    func clearStreamBookmarks() {
        defaults.removeObject(forKey: Key.streamBookmarks)
    }

    func addLibraryFolder(_ url: URL) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return }
        let standardizedURL = url.standardizedFileURL
        let storageValue = standardizedURL.absoluteString
        var values = defaults.stringArray(forKey: Key.libraryFolders) ?? []
        values.removeAll { $0 == storageValue || URL(string: $0)?.standardizedFileURL == standardizedURL }
        values.insert(storageValue, at: 0)
        defaults.set(Array(values.prefix(8)), forKey: Key.libraryFolders)

        do {
            var bookmarks = libraryFolderBookmarks()
            bookmarks[storageValue] = try SecurityScopedBookmarks.data(for: standardizedURL)
            defaults.set(bookmarks, forKey: Key.libraryFolderBookmarks)
        } catch {
            AppLogger.warning("Library folder bookmark creation failed path=\(standardizedURL.path) error=\(error.localizedDescription)")
        }
    }

    func removeLibraryFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        var values = defaults.stringArray(forKey: Key.libraryFolders) ?? []
        let removedValues = values.filter { value in
            value == standardizedURL.absoluteString || URL(string: value)?.standardizedFileURL == standardizedURL
        }
        values.removeAll { removedValues.contains($0) }
        defaults.set(values, forKey: Key.libraryFolders)

        var bookmarks = libraryFolderBookmarks()
        for key in removedValues + [standardizedURL.absoluteString] {
            bookmarks.removeValue(forKey: key)
        }
        defaults.set(bookmarks, forKey: Key.libraryFolderBookmarks)
    }

    func clearLibraryFolders() {
        defaults.removeObject(forKey: Key.libraryFolders)
        defaults.removeObject(forKey: Key.libraryFolderBookmarks)
    }

    func mediaLibraryRecord(for item: MediaItem) -> MediaLibraryRecord {
        let storageKey = MediaPersistence.storageString(for: item.url)
        if let libraryDatabase, let record = libraryDatabase.mediaRecord(for: storageKey) {
            return record
        }
        return mediaLibraryRecords()[storageKey] ?? .empty
    }

    func indexLibraryItems(_ items: [MediaItem]) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return }
        libraryDatabase?.indexMediaItems(items)
    }

    func indexedLibraryItems() -> [MediaItem] {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return [] }
        return libraryDatabase?.indexedMediaItems() ?? []
    }

    func saveMediaLibraryRecord(_ record: MediaLibraryRecord, for item: MediaItem) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return }
        let storageKey = MediaPersistence.storageString(for: item.url)
        if let libraryDatabase, libraryDatabase.saveMediaRecord(record, for: storageKey) {
            return
        }
        var records = mediaLibraryRecords()
        records[storageKey] = record
        saveMediaLibraryRecords(records)
    }

    func mediaLibraryRecords() -> [String: MediaLibraryRecord] {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return [:] }
        if let libraryDatabase {
            return libraryDatabase.allMediaRecords()
        }
        guard let data = defaults.data(forKey: Key.mediaLibraryRecords),
              let records = try? JSONDecoder().decode([String: MediaLibraryRecord].self, from: data)
        else {
            return [:]
        }
        return records
    }

    func loadLibraryFolders() -> [URL] {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else {
            return []
        }

        var values = defaults.stringArray(forKey: Key.libraryFolders) ?? []
        var bookmarks = libraryFolderBookmarks()
        if values.isEmpty, !bookmarks.isEmpty {
            values = bookmarks.keys.sorted()
        }

        var bookmarksChanged = false
        let resolvedURLs = values.compactMap { value -> URL? in
            let fallbackURL = URL(string: value)?.standardizedFileURL
            var resolvedURL = fallbackURL

            if let bookmarkData = bookmarks[value] {
                do {
                    let resolution = try SecurityScopedBookmarks.resolve(bookmarkData)
                    resolvedURL = resolution.url.standardizedFileURL
                    if resolution.isStale, let resolvedURL {
                        bookmarks[value] = try SecurityScopedBookmarks.data(for: resolvedURL)
                        bookmarksChanged = true
                    }
                } catch {
                    AppLogger.warning("Library folder bookmark resolution failed error=\(error.localizedDescription)")
                }
            } else if let fallbackURL {
                do {
                    bookmarks[value] = try SecurityScopedBookmarks.data(for: fallbackURL)
                    bookmarksChanged = true
                } catch {
                    AppLogger.warning("Library folder bookmark migration failed path=\(fallbackURL.path) error=\(error.localizedDescription)")
                }
            }

            guard let url = resolvedURL, url.isFileURL else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return url
        }

        if bookmarksChanged {
            defaults.set(bookmarks, forKey: Key.libraryFolderBookmarks)
        }
        return resolvedURLs
    }

    func position(for item: MediaItem) -> Double {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return 0 }
        let storageKey = MediaPersistence.storageString(for: item.url)
        if let libraryDatabase, let position = libraryDatabase.position(for: storageKey) {
            return position
        }
        return positions()[storageKey] ?? 0
    }

    func savePosition(_ seconds: Double, for item: MediaItem) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return }
        let key = MediaPersistence.storageString(for: item.url)
        if let libraryDatabase {
            if seconds > 5 {
                _ = libraryDatabase.savePosition(seconds, for: key)
            } else {
                libraryDatabase.removePosition(for: key)
            }
            return
        }
        var positions = positions()
        if seconds > 5 {
            positions[key] = seconds
        } else {
            positions.removeValue(forKey: key)
        }
        positions.removeValue(forKey: item.url.absoluteString)
        defaults.set(positions, forKey: Key.positions)
    }

    func clearPosition(for item: MediaItem) {
        let storageKey = MediaPersistence.storageString(for: item.url)
        libraryDatabase?.removePosition(for: storageKey)
        var positions = positions()
        positions.removeValue(forKey: storageKey)
        positions.removeValue(forKey: item.url.absoluteString)
        defaults.set(positions, forKey: Key.positions)
    }

    func playbackProfile(for item: MediaItem) -> MediaPlaybackProfile? {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults) else { return nil }
        let storageKey = MediaPersistence.storageString(for: item.url)
        if let data = libraryDatabase?.playbackProfileData(for: storageKey) {
            return try? JSONDecoder().decode(MediaPlaybackProfile.self, from: data)
        }
        guard let profiles = defaults.dictionary(forKey: Key.playbackProfiles) as? [String: Data],
              let data = profiles[storageKey]
        else {
            return nil
        }
        return try? JSONDecoder().decode(MediaPlaybackProfile.self, from: data)
    }

    func savePlaybackProfile(_ profile: MediaPlaybackProfile, for item: MediaItem) {
        guard PrivacySettings.savePlaybackHistory(defaults: defaults),
              let data = try? JSONEncoder().encode(profile)
        else {
            return
        }
        let storageKey = MediaPersistence.storageString(for: item.url)
        if let libraryDatabase, libraryDatabase.savePlaybackProfileData(data, for: storageKey) {
            return
        }
        var profiles = defaults.dictionary(forKey: Key.playbackProfiles) as? [String: Data] ?? [:]
        profiles[storageKey] = data
        defaults.set(profiles, forKey: Key.playbackProfiles)
    }

    func removePlaybackProfile(for item: MediaItem) {
        let storageKey = MediaPersistence.storageString(for: item.url)
        libraryDatabase?.removePlaybackProfile(for: storageKey)
        var profiles = defaults.dictionary(forKey: Key.playbackProfiles) as? [String: Data] ?? [:]
        profiles.removeValue(forKey: storageKey)
        defaults.set(profiles, forKey: Key.playbackProfiles)
    }

    func savePlaybackHistoryEnabled() -> Bool {
        PrivacySettings.savePlaybackHistory(defaults: defaults)
    }

    func setSavePlaybackHistoryEnabled(_ enabled: Bool) {
        PrivacySettings.setSavePlaybackHistory(enabled, defaults: defaults)
        if !enabled {
            clearPlaybackHistory()
        } else {
            migrateLegacyLibraryDataIfNeeded()
        }
    }

    func clearHistoryOnQuitEnabled() -> Bool {
        PrivacySettings.clearHistoryOnQuit(defaults: defaults)
    }

    func setClearHistoryOnQuitEnabled(_ enabled: Bool) {
        PrivacySettings.setClearHistoryOnQuit(enabled, defaults: defaults)
    }

    func privateNetworkStreamsEnabled() -> Bool {
        PrivacySettings.allowPrivateNetworkStreams(defaults: defaults)
    }

    func setPrivateNetworkStreamsEnabled(_ enabled: Bool) {
        PrivacySettings.setAllowPrivateNetworkStreams(enabled, defaults: defaults)
    }

    func externalMediaEnginesEnabled() -> Bool {
        PrivacySettings.externalMediaEnginesEnabled(defaults: defaults)
    }

    func setExternalMediaEnginesEnabled(_ enabled: Bool) {
        PrivacySettings.setExternalMediaEnginesEnabled(enabled, defaults: defaults)
    }

    func clearPlaybackHistory() {
        defaults.removeObject(forKey: Key.playlist)
        defaults.removeObject(forKey: Key.currentIndex)
        defaults.removeObject(forKey: Key.positions)
        defaults.removeObject(forKey: Key.recentMedia)
        defaults.removeObject(forKey: Key.libraryFolders)
        defaults.removeObject(forKey: Key.libraryFolderBookmarks)
        defaults.removeObject(forKey: Key.mediaLibraryRecords)
        defaults.removeObject(forKey: Key.streamBookmarks)
        defaults.removeObject(forKey: Key.playbackProfiles)
        libraryDatabase?.clearPrivateLibraryData()
    }

    private func saveMediaLibraryRecords(_ records: [String: MediaLibraryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.mediaLibraryRecords)
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

    private func libraryFolderBookmarks() -> [String: Data] {
        defaults.dictionary(forKey: Key.libraryFolderBookmarks) as? [String: Data] ?? [:]
    }

    private func migrateLegacyLibraryDataIfNeeded() {
        guard let libraryDatabase,
              PrivacySettings.savePlaybackHistory(defaults: defaults),
              defaults.integer(forKey: Key.libraryDatabaseMigrationVersion) < 1
        else {
            return
        }

        if let data = defaults.data(forKey: Key.mediaLibraryRecords),
           let records = try? JSONDecoder().decode([String: MediaLibraryRecord].self, from: data) {
            for (storageKey, record) in records {
                _ = libraryDatabase.saveMediaRecord(record, for: storageKey)
            }
        }

        for (storageKey, seconds) in positions() where seconds > 5 {
            _ = libraryDatabase.savePosition(seconds, for: storageKey)
        }

        defaults.removeObject(forKey: Key.mediaLibraryRecords)
        defaults.removeObject(forKey: Key.positions)
        defaults.set(1, forKey: Key.libraryDatabaseMigrationVersion)
        AppLogger.info("Legacy library records migrated to SQLite", flush: true)
    }
}
