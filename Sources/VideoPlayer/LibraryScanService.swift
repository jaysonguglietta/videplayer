import Foundation

struct LibraryScanProgress: Sendable, Equatable {
    let enumeratedItems: Int
    let mediaFilesFound: Int
    let currentName: String
}

struct LibraryScanResult: Sendable, Equatable {
    let mediaURLs: [URL]
    let enumeratedItems: Int
    let wasLimited: Bool
    let wasCancelled: Bool
}

enum LibraryScanService {
    static func scan(
        urls: [URL],
        mediaExtensions: Set<String>,
        maximumMediaFiles: Int,
        maximumEnumeratedItems: Int,
        progress: @escaping @Sendable (LibraryScanProgress) -> Void = { _ in }
    ) async -> LibraryScanResult {
        await Task.detached(priority: .utility) {
            let operation = OperationTimeline.begin("library.scan", detail: "sources=\(urls.count)")
            defer { OperationTimeline.end(operation) }

            var found: [URL] = []
            var seenPaths = Set<String>()
            var enumeratedItems = 0
            var wasLimited = false
            var wasCancelled = false

            func appendIfSupported(_ url: URL) {
                guard mediaExtensions.contains(url.pathExtension.lowercased()) else { return }
                let standardized = url.standardizedFileURL
                guard seenPaths.insert(standardized.path).inserted else { return }
                found.append(standardized)
            }

            for sourceURL in urls {
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }

                SecurityScopedBookmarks.withAccess(to: sourceURL) {
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
                        return
                    }

                    guard isDirectory.boolValue else {
                        enumeratedItems += 1
                        appendIfSupported(sourceURL)
                        progress(LibraryScanProgress(
                            enumeratedItems: enumeratedItems,
                            mediaFilesFound: found.count,
                            currentName: sourceURL.lastPathComponent
                        ))
                        return
                    }

                    guard let enumerator = FileManager.default.enumerator(
                        at: sourceURL,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else {
                        return
                    }

                    while let object = enumerator.nextObject() {
                        if Task.isCancelled {
                            wasCancelled = true
                            break
                        }
                        enumeratedItems += 1
                        if enumeratedItems > maximumEnumeratedItems || found.count >= maximumMediaFiles {
                            wasLimited = true
                            break
                        }
                        guard let fileURL = object as? URL else { continue }
                        appendIfSupported(fileURL)
                        if enumeratedItems == 1 || enumeratedItems.isMultiple(of: 200) {
                            progress(LibraryScanProgress(
                                enumeratedItems: enumeratedItems,
                                mediaFilesFound: found.count,
                                currentName: fileURL.lastPathComponent
                            ))
                        }
                    }
                }

                if wasLimited || wasCancelled { break }
            }

            let sorted = found.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            progress(LibraryScanProgress(
                enumeratedItems: enumeratedItems,
                mediaFilesFound: sorted.count,
                currentName: "Complete"
            ))
            return LibraryScanResult(
                mediaURLs: sorted,
                enumeratedItems: enumeratedItems,
                wasLimited: wasLimited,
                wasCancelled: wasCancelled
            )
        }.value
    }
}
