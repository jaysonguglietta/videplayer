import Foundation
import SQLite3

enum LibraryDatabaseError: LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let detail):
            "The media library database could not be opened: \(detail)"
        case .statementFailed(let detail):
            "The media library database operation failed: \(detail)"
        }
    }
}

final class LibraryDatabase {
    static let shared: LibraryDatabase? = {
        do {
            return try LibraryDatabase()
        } catch {
            AppLogger.error("Library database initialization failed error=\(error.localizedDescription)", flush: true)
            return nil
        }
    }()

    private let queue = DispatchQueue(label: "com.jaysonguglietta.videoplayer.library-database")
    private var connection: OpaquePointer?

    init(url: URL = LibraryDatabase.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let status = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard status == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let database { sqlite3_close(database) }
            throw LibraryDatabaseError.openFailed(message)
        }

        connection = database
        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA foreign_keys=ON;")
            try execute("""
                CREATE TABLE IF NOT EXISTS media_records (
                    storage_key TEXT PRIMARY KEY NOT NULL,
                    is_favorite INTEGER NOT NULL,
                    is_watched INTEGER NOT NULL,
                    tags_json TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS media_items (
                    storage_key TEXT PRIMARY KEY NOT NULL,
                    source_url TEXT NOT NULL,
                    title TEXT NOT NULL,
                    media_type TEXT NOT NULL,
                    last_seen_at REAL NOT NULL
                );
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS playback_positions (
                    storage_key TEXT PRIMARY KEY NOT NULL,
                    seconds REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS playback_profiles (
                    storage_key TEXT PRIMARY KEY NOT NULL,
                    profile_json BLOB NOT NULL,
                    updated_at REAL NOT NULL
                );
                """)
            try execute("CREATE INDEX IF NOT EXISTS media_records_updated_idx ON media_records(updated_at DESC);")
            try execute("CREATE INDEX IF NOT EXISTS media_items_title_idx ON media_items(title COLLATE NOCASE);")
            try execute("PRAGMA user_version=1;")
        } catch {
            sqlite3_close(database)
            connection = nil
            throw error
        }
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    func mediaRecord(for storageKey: String) -> MediaLibraryRecord? {
        queue.sync {
            do {
                let statement = try prepare("""
                    SELECT is_favorite, is_watched, tags_json, updated_at
                    FROM media_records WHERE storage_key = ? LIMIT 1;
                    """)
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
                return decodeRecord(from: statement)
            } catch {
                AppLogger.error("Library database record lookup failed error=\(error.localizedDescription)")
                return nil
            }
        }
    }

    func indexMediaItems(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        queue.sync {
            do {
                try executeUnlocked("BEGIN IMMEDIATE TRANSACTION;")
                let statement = try prepare("""
                    INSERT INTO media_items(storage_key, source_url, title, media_type, last_seen_at)
                    VALUES(?, ?, ?, ?, ?)
                    ON CONFLICT(storage_key) DO UPDATE SET
                        source_url=excluded.source_url,
                        title=excluded.title,
                        media_type=excluded.media_type,
                        last_seen_at=excluded.last_seen_at;
                    """)
                defer { sqlite3_finalize(statement) }
                let timestamp = Date().timeIntervalSince1970
                for item in items {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    let source = MediaPersistence.storageString(for: item.url)
                    bind(source, to: statement, at: 1)
                    bind(source, to: statement, at: 2)
                    bind(item.title, to: statement, at: 3)
                    bind(item.isNetworkStream ? "stream" : item.fileExtension.lowercased(), to: statement, at: 4)
                    sqlite3_bind_double(statement, 5, timestamp)
                    try stepToCompletion(statement)
                }
                try executeUnlocked("COMMIT;")
            } catch {
                try? executeUnlocked("ROLLBACK;")
                AppLogger.error("Library media indexing failed error=\(error.localizedDescription)", flush: true)
            }
        }
    }

    func indexedMediaItems() -> [MediaItem] {
        queue.sync {
            do {
                let statement = try prepare("SELECT source_url FROM media_items ORDER BY title COLLATE NOCASE;")
                defer { sqlite3_finalize(statement) }
                var items: [MediaItem] = []
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let text = sqlite3_column_text(statement, 0),
                          let url = URL(string: String(cString: text))
                    else {
                        continue
                    }
                    items.append(MediaItem(url: url))
                }
                return items
            } catch {
                AppLogger.error("Library media enumeration failed error=\(error.localizedDescription)")
                return []
            }
        }
    }

    @discardableResult
    func saveMediaRecord(_ record: MediaLibraryRecord, for storageKey: String) -> Bool {
        queue.sync {
            do {
                let tagsData = try JSONEncoder().encode(record.tags)
                let tagsJSON = String(data: tagsData, encoding: .utf8) ?? "[]"
                let statement = try prepare("""
                    INSERT INTO media_records(storage_key, is_favorite, is_watched, tags_json, updated_at)
                    VALUES(?, ?, ?, ?, ?)
                    ON CONFLICT(storage_key) DO UPDATE SET
                        is_favorite=excluded.is_favorite,
                        is_watched=excluded.is_watched,
                        tags_json=excluded.tags_json,
                        updated_at=excluded.updated_at;
                    """)
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                sqlite3_bind_int(statement, 2, record.isFavorite ? 1 : 0)
                sqlite3_bind_int(statement, 3, record.isWatched ? 1 : 0)
                bind(tagsJSON, to: statement, at: 4)
                sqlite3_bind_double(statement, 5, record.updatedAt.timeIntervalSince1970)
                try stepToCompletion(statement)
                return true
            } catch {
                AppLogger.error("Library database record save failed error=\(error.localizedDescription)")
                return false
            }
        }
    }

    func allMediaRecords() -> [String: MediaLibraryRecord] {
        queue.sync {
            do {
                let statement = try prepare("""
                    SELECT storage_key, is_favorite, is_watched, tags_json, updated_at
                    FROM media_records;
                    """)
                defer { sqlite3_finalize(statement) }
                var records: [String: MediaLibraryRecord] = [:]
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let keyText = sqlite3_column_text(statement, 0) else { continue }
                    let key = String(cString: keyText)
                    records[key] = decodeRecord(from: statement, columnOffset: 1)
                }
                return records
            } catch {
                AppLogger.error("Library database record enumeration failed error=\(error.localizedDescription)")
                return [:]
            }
        }
    }

    func position(for storageKey: String) -> Double? {
        queue.sync {
            do {
                let statement = try prepare("SELECT seconds FROM playback_positions WHERE storage_key = ? LIMIT 1;")
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
                return sqlite3_column_double(statement, 0)
            } catch {
                AppLogger.error("Library database position lookup failed error=\(error.localizedDescription)")
                return nil
            }
        }
    }

    @discardableResult
    func savePosition(_ seconds: Double, for storageKey: String) -> Bool {
        queue.sync {
            do {
                let statement = try prepare("""
                    INSERT INTO playback_positions(storage_key, seconds, updated_at)
                    VALUES(?, ?, ?)
                    ON CONFLICT(storage_key) DO UPDATE SET
                        seconds=excluded.seconds,
                        updated_at=excluded.updated_at;
                    """)
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                sqlite3_bind_double(statement, 2, seconds)
                sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
                try stepToCompletion(statement)
                return true
            } catch {
                AppLogger.error("Library database position save failed error=\(error.localizedDescription)")
                return false
            }
        }
    }

    func removePosition(for storageKey: String) {
        queue.sync {
            do {
                let statement = try prepare("DELETE FROM playback_positions WHERE storage_key = ?;")
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                try stepToCompletion(statement)
            } catch {
                AppLogger.error("Library database position removal failed error=\(error.localizedDescription)")
            }
        }
    }

    func playbackProfileData(for storageKey: String) -> Data? {
        queue.sync {
            do {
                let statement = try prepare("SELECT profile_json FROM playback_profiles WHERE storage_key = ? LIMIT 1;")
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                guard sqlite3_step(statement) == SQLITE_ROW,
                      let bytes = sqlite3_column_blob(statement, 0)
                else {
                    return nil
                }
                return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            } catch {
                AppLogger.error("Library database profile lookup failed error=\(error.localizedDescription)")
                return nil
            }
        }
    }

    @discardableResult
    func savePlaybackProfileData(_ data: Data, for storageKey: String) -> Bool {
        queue.sync {
            do {
                let statement = try prepare("""
                    INSERT INTO playback_profiles(storage_key, profile_json, updated_at)
                    VALUES(?, ?, ?)
                    ON CONFLICT(storage_key) DO UPDATE SET
                        profile_json=excluded.profile_json,
                        updated_at=excluded.updated_at;
                    """)
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                _ = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(data.count), sqliteTransient)
                }
                sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
                try stepToCompletion(statement)
                return true
            } catch {
                AppLogger.error("Library database profile save failed error=\(error.localizedDescription)")
                return false
            }
        }
    }

    func removePlaybackProfile(for storageKey: String) {
        queue.sync {
            do {
                let statement = try prepare("DELETE FROM playback_profiles WHERE storage_key = ?;")
                defer { sqlite3_finalize(statement) }
                bind(storageKey, to: statement, at: 1)
                try stepToCompletion(statement)
            } catch {
                AppLogger.error("Library database profile removal failed error=\(error.localizedDescription)")
            }
        }
    }

    func clearPrivateLibraryData() {
        queue.sync {
            do {
                try executeUnlocked("BEGIN IMMEDIATE TRANSACTION;")
                try executeUnlocked("DELETE FROM media_records;")
                try executeUnlocked("DELETE FROM media_items;")
                try executeUnlocked("DELETE FROM playback_positions;")
                try executeUnlocked("DELETE FROM playback_profiles;")
                try executeUnlocked("COMMIT;")
            } catch {
                try? executeUnlocked("ROLLBACK;")
                AppLogger.error("Library database privacy clear failed error=\(error.localizedDescription)", flush: true)
            }
        }
    }

    static var defaultURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Video Player", isDirectory: true)
            .appendingPathComponent("Library.sqlite3", isDirectory: false)
    }

    private func execute(_ sql: String) throws {
        try queue.sync {
            try executeUnlocked(sql)
        }
    }

    private func executeUnlocked(_ sql: String) throws {
        guard let connection else { throw LibraryDatabaseError.openFailed("Database is closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(connection))
            sqlite3_free(errorMessage)
            throw LibraryDatabaseError.statementFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let connection else { throw LibraryDatabaseError.openFailed("Database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LibraryDatabaseError.statementFailed(String(cString: sqlite3_errmsg(connection)))
        }
        return statement
    }

    private func stepToCompletion(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            throw LibraryDatabaseError.statementFailed(message)
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
        }
    }

    private func decodeRecord(from statement: OpaquePointer, columnOffset: Int32 = 0) -> MediaLibraryRecord {
        let isFavorite = sqlite3_column_int(statement, columnOffset) != 0
        let isWatched = sqlite3_column_int(statement, columnOffset + 1) != 0
        let tagsJSON = sqlite3_column_text(statement, columnOffset + 2).map(String.init(cString:)) ?? "[]"
        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, columnOffset + 3))
        return MediaLibraryRecord(isFavorite: isFavorite, isWatched: isWatched, tags: tags, updatedAt: updatedAt)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
