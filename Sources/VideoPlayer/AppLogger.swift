import Foundation

enum AppLogger {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static var logFileURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Video Player", isDirectory: true)
            .appendingPathComponent("video-player.log", isDirectory: false)
    }

    @discardableResult
    static func ensureLogFile() -> URL {
        let url = logFileURL
        queue.sync {
            createLogFileIfNeeded(at: url)
        }
        return url
    }

    static func debug(_ message: @autoclosure () -> String, flush: Bool = false) {
        log(.debug, message(), flush: flush)
    }

    static func info(_ message: @autoclosure () -> String, flush: Bool = false) {
        log(.info, message(), flush: flush)
    }

    static func warning(_ message: @autoclosure () -> String, flush: Bool = false) {
        log(.warning, message(), flush: flush)
    }

    static func error(_ message: @autoclosure () -> String, flush: Bool = false) {
        log(.error, message(), flush: flush)
    }

    static func redactedURLString(_ url: URL) -> String {
        guard !url.isFileURL else {
            return redactedFilePath(url.path)
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        let hadQuery = components?.query?.isEmpty == false
        let hadFragment = components?.fragment?.isEmpty == false
        components?.query = nil
        components?.fragment = nil

        var redacted = components?.url?.absoluteString ?? url.absoluteString
        if hadQuery {
            redacted += "?[REDACTED]"
        }
        if hadFragment {
            redacted += "#[REDACTED]"
        }
        return redacted
    }

    static func redactedFilePath(_ path: String) -> String {
        var redacted = path
        let home = NSHomeDirectory()
        if !home.isEmpty {
            redacted = redacted.replacingOccurrences(of: home, with: "~")
        }
        redacted = redacted.replacingOccurrences(
            of: #"/Volumes/[^/\s]+/[^ \n\t]+"#,
            with: "/Volumes/[REDACTED]",
            options: .regularExpression
        )
        return redacted
    }

    private static let maximumLogSize = 2_000_000
    private static let queue = DispatchQueue(label: "com.jaysonguglietta.videoplayer.logger")
    private static let queueKey = DispatchSpecificKey<Bool>()
    private static let configureQueue: Void = {
        queue.setSpecific(key: queueKey, value: true)
    }()

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func log(_ level: Level, _ message: String, flush: Bool) {
        _ = configureQueue
        let write = {
            writeLine(level: level, message: message)
        }

        if flush {
            if DispatchQueue.getSpecific(key: queueKey) == true {
                write()
            } else {
                queue.sync(execute: write)
            }
        } else {
            queue.async(execute: write)
        }
    }

    private static func writeLine(level: Level, message: String) {
        let url = logFileURL
        createLogFileIfNeeded(at: url)
        rotateLogIfNeeded(at: url)

        let cleanedMessage = sanitizeForLog(message)
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] [pid:\(ProcessInfo.processInfo.processIdentifier)] \(cleanedMessage)\n"

        guard let data = line.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("Video Player log write failed: \(error.localizedDescription)")
        }
    }

    private static func createLogFileIfNeeded(at url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
        } catch {
            NSLog("Video Player log setup failed: \(error.localizedDescription)")
        }
    }

    private static func sanitizeForLog(_ message: String) -> String {
        var sanitized = redactURLs(in: message)
        sanitized = sanitized.replacingOccurrences(
            of: #"([?&](token|signature|sig|key|password|pass|auth|access_token|refresh_token)=)[^ \n\t&]+"#,
            with: "$1[REDACTED]",
            options: [.regularExpression, .caseInsensitive]
        )
        sanitized = redactedFilePath(sanitized)
        return sanitized
    }

    private static func redactURLs(in message: String) -> String {
        let pattern = #"(https?|rtsp|rtsps)://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return message
        }

        let original = message as NSString
        let result = NSMutableString(string: message)
        let matches = regex.matches(in: message, range: NSRange(location: 0, length: original.length))
        for match in matches.reversed() {
            let rawURL = original.substring(with: match.range)
            guard let url = URL(string: rawURL) else { continue }
            result.replaceCharacters(in: match.range, with: redactedURLString(url))
        }
        return result as String
    }

    private static func rotateLogIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maximumLogSize
        else {
            return
        }

        let rotatedURL = url.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: rotatedURL)
        do {
            try FileManager.default.moveItem(at: url, to: rotatedURL)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        } catch {
            NSLog("Video Player log rotation failed: \(error.localizedDescription)")
        }
    }
}
