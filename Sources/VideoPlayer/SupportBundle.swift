import Foundation

struct SupportBundleRequest {
    let destinationDirectory: URL
    let diagnosticReport: String
    let policy: EnterprisePolicySnapshot
    let licenseStatus: EnterpriseLicenseStatus
    let selectedItem: MediaItem?
    let includeLogs: Bool
    let redactPaths: Bool
    let now: Date
}

enum SupportBundleExporter {
    static func export(request: SupportBundleRequest) throws -> URL {
        let bundleDirectory = request.destinationDirectory.appendingPathComponent(
            "Video Player Support Bundle \(fileNameDateFormatter.string(from: request.now))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

        let reportURL = bundleDirectory.appendingPathComponent("support-report.txt")
        try supportReport(for: request).write(to: reportURL, atomically: true, encoding: .utf8)

        let diagnosticsURL = bundleDirectory.appendingPathComponent("playback-diagnostics.txt")
        try sanitize(request.diagnosticReport, redactPaths: request.redactPaths)
            .write(to: diagnosticsURL, atomically: true, encoding: .utf8)

        let timelineURL = bundleDirectory.appendingPathComponent("operation-timeline.txt")
        try sanitize(OperationTimeline.reportText(), redactPaths: request.redactPaths)
            .write(to: timelineURL, atomically: true, encoding: .utf8)

        let readmeURL = bundleDirectory.appendingPathComponent("README.txt")
        try """
        Video Player Support Bundle

        Share this folder with support when reporting playback, update, library, or enterprise deployment issues.
        Paths and stream credentials are redacted when the support bundle redaction policy is enabled.
        """.write(to: readmeURL, atomically: true, encoding: .utf8)

        if request.includeLogs && !request.policy.disableSupportBundleLogExport {
            let logURL = AppLogger.ensureLogFile()
            if let logText = try? String(contentsOf: logURL, encoding: .utf8) {
                let exportedLogURL = bundleDirectory.appendingPathComponent("video-player.log")
                try sanitize(logText, redactPaths: request.redactPaths)
                    .write(to: exportedLogURL, atomically: true, encoding: .utf8)
            }
        }

        return bundleDirectory
    }

    static func supportReport(for request: SupportBundleRequest) -> String {
        var lines = [
            "Video Player Support Report",
            "===========================",
            "Generated: \(reportDateFormatter.string(from: request.now))",
            "App Version: \(OpenSourceNotices.appVersion)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Sandboxed Container: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "Unknown")",
            "",
            "Selected Media",
            "--------------"
        ]

        if let selectedItem = request.selectedItem {
            lines.append("Title: \(selectedItem.title)")
            lines.append("Location: \(MediaPersistence.storageString(for: selectedItem.url))")
            lines.append("Type: \(selectedItem.isNetworkStream ? "Network stream" : selectedItem.fileExtension.uppercased())")
        } else {
            lines.append("No media selected")
        }

        lines.append("")
        lines.append("License")
        lines.append("-------")
        lines.append(request.licenseStatus.reportText)

        lines.append("")
        lines.append("Managed Policy")
        lines.append("--------------")
        lines.append(contentsOf: request.policy.summaryLines)

        lines.append("")
        lines.append("Included Files")
        lines.append("--------------")
        lines.append("support-report.txt")
        lines.append("playback-diagnostics.txt")
        lines.append("operation-timeline.txt")
        if request.includeLogs && !request.policy.disableSupportBundleLogExport {
            lines.append("video-player.log")
        } else {
            lines.append("video-player.log omitted by policy or user choice")
        }

        return sanitize(lines.joined(separator: "\n"), redactPaths: request.redactPaths)
    }

    static func sanitize(_ text: String, redactPaths: Bool) -> String {
        var sanitized = text
        sanitized = sanitized.replacingOccurrences(
            of: #"([?&](token|signature|sig|key|password|pass|auth|access_token|refresh_token)=)[^ \n\t&]+"#,
            with: "$1[REDACTED]",
            options: [.regularExpression, .caseInsensitive]
        )

        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)(https?://)([^:/\s]+):([^@\s]+)@"#,
            with: "$1[REDACTED]:[REDACTED]@",
            options: .regularExpression
        )

        guard redactPaths else { return sanitized }

        let home = NSHomeDirectory()
        if !home.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: home, with: "~")
        }
        sanitized = sanitized.replacingOccurrences(
            of: #"/Volumes/[^/\s]+/[^ \n\t]+"#,
            with: "/Volumes/[REDACTED]",
            options: .regularExpression
        )
        return sanitized
    }

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private static let reportDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
