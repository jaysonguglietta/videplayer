import Foundation

struct ResolvedSecurityScopedBookmark {
    let url: URL
    let isStale: Bool
}

enum SecurityScopedBookmarks {
    static func data(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) throws -> ResolvedSecurityScopedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedSecurityScopedBookmark(url: url, isStale: isStale)
    }

    static func withAccess<T>(to url: URL, operation: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
