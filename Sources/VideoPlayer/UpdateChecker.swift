import AppKit
import Foundation

final class UpdateChecker {
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/jaysonguglietta/videplayer/releases/latest")!
    private var activeTask: URLSessionTask?

    func checkForUpdates(presentingWindow: NSWindow?) {
        guard activeTask == nil else { return }

        var request = URLRequest(url: latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("VideoPlayer/\(OpenSourceNotices.appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.activeTask = nil
            }

            if let error {
                self?.showError("Could not check for updates.", detail: error.localizedDescription, presentingWindow: presentingWindow)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self?.showError("Could not check for updates.", detail: "GitHub did not return a valid response.", presentingWindow: presentingWindow)
                return
            }

            guard httpResponse.statusCode != 404 else {
                self?.showError(
                    "No releases are published yet.",
                    detail: "Create a GitHub Release with a .dmg asset to enable update downloads.",
                    presentingWindow: presentingWindow
                )
                return
            }

            guard (200..<300).contains(httpResponse.statusCode), let data else {
                self?.showError(
                    "Could not check for updates.",
                    detail: "GitHub returned HTTP \(httpResponse.statusCode).",
                    presentingWindow: presentingWindow
                )
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self?.handle(release: release, presentingWindow: presentingWindow)
            } catch {
                self?.showError("Could not read update information.", detail: error.localizedDescription, presentingWindow: presentingWindow)
            }
        }

        activeTask = task
        task.resume()
    }

    private func handle(release: GitHubRelease, presentingWindow: NSWindow?) {
        let currentVersion = OpenSourceNotices.appVersion
        guard isVersion(release.normalizedTag, newerThan: currentVersion) else {
            showStatus(
                "Video Player is up to date.",
                detail: "Installed version: \(currentVersion)\nLatest release: \(release.tagName)",
                presentingWindow: presentingWindow
            )
            return
        }

        guard let asset = release.assets.first(where: { $0.isDiskImage }) ?? release.assets.first else {
            showReleaseOnly(release, presentingWindow: presentingWindow)
            return
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = """
            Version \(release.tagName) is available.

            Installed version: \(currentVersion)
            Download: \(asset.name)
            """
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                self.download(asset: asset, release: release, presentingWindow: presentingWindow)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(release.htmlURL)
            default:
                break
            }
        }
    }

    private func showReleaseOnly(_ release: GitHubRelease, presentingWindow: NSWindow?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = "Version \(release.tagName) is available, but no downloadable asset was attached. Open the GitHub release page to get it."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private func download(asset: GitHubAsset, release: GitHubRelease, presentingWindow: NSWindow?) {
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("VideoPlayer/\(OpenSourceNotices.appVersion)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.downloadTask(with: request) { [weak self] temporaryURL, _, error in
            DispatchQueue.main.async {
                self?.activeTask = nil
            }

            if let error {
                self?.showError("Download failed.", detail: error.localizedDescription, presentingWindow: presentingWindow)
                return
            }
            guard let temporaryURL else {
                self?.showError("Download failed.", detail: "No file was returned by GitHub.", presentingWindow: presentingWindow)
                return
            }

            do {
                let destination = try self?.moveDownloadedFile(from: temporaryURL, fileName: asset.name)
                guard let destination else { return }
                self?.showDownloadedUpdate(destination, release: release, presentingWindow: presentingWindow)
            } catch {
                self?.showError("Download failed.", detail: error.localizedDescription, presentingWindow: presentingWindow)
            }
        }

        activeTask = task
        task.resume()
    }

    private func moveDownloadedFile(from temporaryURL: URL, fileName: String) throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        var destination = downloads.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            let baseName = destination.deletingPathExtension().lastPathComponent
            let pathExtension = destination.pathExtension
            let stamp = Self.fileNameDateFormatter.string(from: Date())
            destination = downloads
                .appendingPathComponent("\(baseName)-\(stamp)")
                .appendingPathExtension(pathExtension)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func showDownloadedUpdate(_ destination: URL, release: GitHubRelease, presentingWindow: NSWindow?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Downloaded"
            alert.informativeText = """
            \(release.tagName) was downloaded to:

            \(destination.path)
            """
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Reveal in Finder")
            alert.addButton(withTitle: "OK")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                NSWorkspace.shared.open(destination)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            default:
                break
            }
        }
    }

    private func showStatus(_ message: String, detail: String = "", presentingWindow: NSWindow?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = detail
            alert.addButton(withTitle: "OK")
            if let presentingWindow {
                alert.beginSheetModal(for: presentingWindow)
            } else {
                alert.runModal()
            }
        }
    }

    private func showError(_ message: String, detail: String, presentingWindow: NSWindow?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = message
            alert.informativeText = detail
            alert.addButton(withTitle: "OK")
            if let presentingWindow {
                alert.beginSheetModal(for: presentingWindow)
            } else {
                alert.runModal()
            }
        }
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidate = normalizedVersion(candidate)
        let current = normalizedVersion(current)
        return candidate.compare(current, options: .numeric) == .orderedDescending
    }

    private func normalizedVersion(_ version: String) -> String {
        version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [GitHubAsset]

    var normalizedTag: String {
        tagName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let contentType: String?
    let downloadURL: URL

    var isDiskImage: Bool {
        let lowercaseName = name.lowercased()
        return lowercaseName.hasSuffix(".dmg")
            || contentType == "application/x-apple-diskimage"
            || contentType == "application/octet-stream"
    }

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case downloadURL = "browser_download_url"
    }
}
