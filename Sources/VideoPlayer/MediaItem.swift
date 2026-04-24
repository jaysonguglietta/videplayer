import Foundation

struct MediaItem: Hashable {
    let url: URL

    var title: String {
        if url.isFileURL {
            return url.deletingPathExtension().lastPathComponent
        }

        if let host = url.host, !host.isEmpty {
            let lastComponent = url.pathComponents.last?.isEmpty == false ? url.lastPathComponent : host
            return lastComponent == "/" ? host : lastComponent
        }

        return url.absoluteString
    }

    var subtitle: String {
        url.isFileURL ? url.path : url.absoluteString
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var persistenceKey: String {
        url.absoluteString
    }

    var isNetworkStream: Bool {
        !url.isFileURL
    }
}
