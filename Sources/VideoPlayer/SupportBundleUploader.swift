import Foundation

struct SupportUploadResult: Equatable {
    let statusCode: Int
    let responseText: String

    var succeeded: Bool {
        (200..<300).contains(statusCode)
    }
}

enum SupportBundleUploader {
    static func upload(bundleDirectory: URL, endpoint: URL) async throws -> SupportUploadResult {
        let files = try supportFiles(in: bundleDirectory)
        let boundary = "VideoPlayerBoundary-\(UUID().uuidString)"
        let body = try multipartBody(files: files, boundary: boundary)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("VideoPlayer/\(OpenSourceNotices.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let responseText = String(data: data.prefix(4_096), encoding: .utf8) ?? ""
        return SupportUploadResult(statusCode: statusCode, responseText: responseText)
    }

    static func multipartBody(files: [URL], boundary: String) throws -> Data {
        var body = Data()
        for file in files {
            let data = try Data(contentsOf: file)
            guard data.count <= maximumFileBytes else {
                throw SupportUploadError.fileTooLarge(file.lastPathComponent)
            }

            append("--\(boundary)\r\n", to: &body)
            append("Content-Disposition: form-data; name=\"files\"; filename=\"\(safeFileName(file.lastPathComponent))\"\r\n", to: &body)
            append("Content-Type: text/plain; charset=utf-8\r\n\r\n", to: &body)
            body.append(data)
            append("\r\n", to: &body)
        }
        append("--\(boundary)--\r\n", to: &body)
        return body
    }

    private static func supportFiles(in bundleDirectory: URL) throws -> [URL] {
        let fileNames = ["support-report.txt", "playback-diagnostics.txt", "README.txt", "video-player.log"]
        let files = fileNames
            .map { bundleDirectory.appendingPathComponent($0) }
            .filter { FileManager.default.isReadableFile(atPath: $0.path) }

        guard !files.isEmpty else {
            throw SupportUploadError.noFiles
        }
        return files
    }

    private static func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }

    private static func safeFileName(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
    }

    private static let maximumFileBytes = 5_000_000
}

enum SupportUploadError: LocalizedError, Equatable {
    case noFiles
    case fileTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "The support bundle does not contain uploadable files."
        case .fileTooLarge(let fileName):
            return "\(fileName) is larger than the support upload limit."
        }
    }
}
