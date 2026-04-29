import Foundation

enum NetworkStreamValidator {
    private static let allowedSchemes: Set<String> = ["http", "https", "rtsp", "rtsps"]

    static func validatedURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmedValue),
            let scheme = url.scheme?.lowercased(),
            allowedSchemes.contains(scheme),
            url.host?.isEmpty == false
        else {
            return nil
        }

        return url
    }
}

enum MediaPersistence {
    static func storageString(for url: URL) -> String {
        guard !url.isFileURL else { return url.absoluteString }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    static func storageString(forStoredValue value: String) -> String {
        guard let url = URL(string: value) else { return value }
        return storageString(for: url)
    }
}
