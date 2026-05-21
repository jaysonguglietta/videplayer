import AppKit
import Foundation

final class UpdateChecker {
    private let releasesURL = URL(string: "https://api.github.com/repos/jaysonguglietta/videplayer/releases?per_page=20")!
    private var activeTask: URLSessionTask?

    func checkForUpdates(presentingWindow: NSWindow?) {
        guard activeTask == nil else { return }
        let policy = EnterprisePolicy.snapshot()
        guard !policy.disableUpdateChecks, policy.updateChannel != "mdm" else {
            AppLogger.info("Update check blocked by enterprise policy", flush: true)
            showStatus(
                "Updates are managed by your organization.",
                detail: "Update checks are disabled by enterprise policy.",
                presentingWindow: presentingWindow
            )
            return
        }

        if policy.updateChannel == "sparkle" {
            showStatus(
                "Sparkle update channel is configured.",
                detail: """
                Appcast: \(policy.sparkleAppcastURLString ?? "Not configured")

                This build is Sparkle-ready for admin reporting, but it does not bundle Sparkle 2 yet. The signed GitHub manifest updater remains active until the Sparkle framework and sandbox services are added to the app bundle.
                """,
                presentingWindow: presentingWindow
            )
            return
        }

        AppLogger.info("Update check started url=\(releasesURL.absoluteString)", flush: true)
        var request = URLRequest(url: releasesURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("VideoPlayer/\(OpenSourceNotices.appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.activeTask = nil
            }

            if let error {
                AppLogger.error("Update check request failed error=\(error.localizedDescription)", flush: true)
                self?.showError("Could not check for updates.", detail: error.localizedDescription, presentingWindow: presentingWindow)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.error("Update check failed because response was not HTTP", flush: true)
                self?.showError("Could not check for updates.", detail: "GitHub did not return a valid response.", presentingWindow: presentingWindow)
                return
            }

            guard (200..<300).contains(httpResponse.statusCode), let data else {
                AppLogger.error("Update check failed HTTP status=\(httpResponse.statusCode)", flush: true)
                self?.showError(
                    "Could not check for updates.",
                    detail: "GitHub returned HTTP \(httpResponse.statusCode).",
                    presentingWindow: presentingWindow
                )
                return
            }

            do {
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                AppLogger.info("Update check decoded releases count=\(releases.count)", flush: true)
                self?.handle(releases: releases, presentingWindow: presentingWindow)
            } catch {
                AppLogger.error("Update check decode failed error=\(error.localizedDescription)", flush: true)
                self?.showError("Could not read update information.", detail: error.localizedDescription, presentingWindow: presentingWindow)
            }
        }

        activeTask = task
        task.resume()
    }

    private func handle(releases: [GitHubRelease], presentingWindow: NSWindow?) {
        let availability = UpdateReleaseSelector.availability(
            from: releases,
            currentVersion: OpenSourceNotices.appVersion
        )

        switch availability {
        case .noPublishedReleases:
            AppLogger.info("Update check result=noPublishedReleases", flush: true)
            showError(
                "No releases are published yet.",
                detail: "Create a GitHub Release with a signed update manifest and .dmg asset to enable update downloads.",
                presentingWindow: presentingWindow
            )
        case .installedBuildIsNewer(let release):
            AppLogger.info("Update check result=installedBuildIsNewer installed=\(OpenSourceNotices.appVersion) newest=\(release.tagName)", flush: true)
            showStatus(
                "No newer update is available.",
                detail: """
                Installed version: \(OpenSourceNotices.appVersion)
                Newest published release: \(release.tagName)

                This installed build is newer than the newest GitHub release. Publish v\(OpenSourceNotices.appVersion) or later to make update checks line up.
                """,
                presentingWindow: presentingWindow
            )
        case .upToDate(let release):
            AppLogger.info("Update check result=upToDate installed=\(OpenSourceNotices.appVersion) newest=\(release.tagName)", flush: true)
            showStatus(
                "Video Player is up to date.",
                detail: """
                Installed version: \(OpenSourceNotices.appVersion)
                Newest published release: \(release.tagName)
                """,
                presentingWindow: presentingWindow
            )
        case .updateAvailable(let release):
            AppLogger.info("Update check result=updateAvailable installed=\(OpenSourceNotices.appVersion) newest=\(release.tagName)", flush: true)
            handle(release: release, presentingWindow: presentingWindow)
        }
    }

    private func handle(release: GitHubRelease, presentingWindow: NSWindow?) {
        let currentVersion = OpenSourceNotices.appVersion
        guard VersionComparator.isVersion(release.normalizedTag, newerThan: currentVersion) else { return }

        guard let manifestAsset = release.assets.first(where: { $0.isUpdateManifest }) else {
            AppLogger.error("Update release missing signed manifest tag=\(release.tagName)", flush: true)
            showError(
                "Update is missing a signed manifest.",
                detail: "Publish \(UpdateSecurity.updateManifestAssetName) with the release so the app can verify the download before opening it.",
                presentingWindow: presentingWindow
            )
            return
        }

        downloadManifest(from: manifestAsset.downloadURL, release: release, presentingWindow: presentingWindow)
    }

    private func downloadManifest(from url: URL, release: GitHubRelease, presentingWindow: NSWindow?) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("VideoPlayer/\(OpenSourceNotices.appVersion)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.activeTask = nil
            }

            if let error {
                AppLogger.error("Manifest download failed error=\(error.localizedDescription)", flush: true)
                self?.showError("Could not download update manifest.", detail: error.localizedDescription, presentingWindow: presentingWindow)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode), let data else {
                AppLogger.error("Manifest download failed invalid response", flush: true)
                self?.showError("Could not download update manifest.", detail: "GitHub did not return the signed manifest.", presentingWindow: presentingWindow)
                return
            }

            do {
                let manifest = try UpdateSecurity.verifiedManifest(from: data)
                try self?.validate(manifest: manifest, release: release)
                AppLogger.info("Update manifest verified tag=\(manifest.tagName) asset=\(manifest.assetName)", flush: true)
                self?.showUpdatePrompt(manifest: manifest, release: release, presentingWindow: presentingWindow)
            } catch {
                AppLogger.error("Update verification failed error=\(error.localizedDescription)", flush: true)
                self?.showError("Update verification failed.", detail: error.localizedDescription, presentingWindow: presentingWindow)
            }
        }

        activeTask = task
        task.resume()
    }

    private func validate(manifest: UpdateManifest, release: GitHubRelease) throws {
        guard manifest.normalizedTag == release.normalizedTag else {
            throw UpdateCheckerError.manifestTagMismatch
        }
        guard VersionComparator.isVersion(manifest.version, newerThan: OpenSourceNotices.appVersion) else {
            throw UpdateCheckerError.manifestIsNotNewer
        }
        guard UpdateSecurity.isDiskImageFileName(manifest.assetName) else {
            throw UpdateCheckerError.invalidDiskImageName
        }
        guard release.assets.contains(where: { $0.downloadURL == manifest.assetURL && $0.isStrictDiskImage }) else {
            throw UpdateCheckerError.manifestAssetMissing
        }
    }

    private func showUpdatePrompt(manifest: UpdateManifest, release: GitHubRelease, presentingWindow: NSWindow?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = """
            Version \(manifest.tagName) is available.

            Installed version: \(OpenSourceNotices.appVersion)
            Download: \(manifest.assetName)
            """
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                self.downloadUpdate(manifest: manifest, release: release, presentingWindow: presentingWindow)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(release.htmlURL)
            default:
                break
            }
        }
    }

    private func downloadUpdate(manifest: UpdateManifest, release: GitHubRelease, presentingWindow: NSWindow?) {
        AppLogger.info("Update download started tag=\(release.tagName) url=\(manifest.assetURL.absoluteString)", flush: true)
        var request = URLRequest(url: manifest.assetURL)
        request.setValue("VideoPlayer/\(OpenSourceNotices.appVersion)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.downloadTask(with: request) { [weak self] temporaryURL, _, error in
            DispatchQueue.main.async {
                self?.activeTask = nil
            }

            if let error {
                AppLogger.error("Update download failed error=\(error.localizedDescription)", flush: true)
                self?.showError("Download failed.", detail: error.localizedDescription, presentingWindow: presentingWindow)
                return
            }
            guard let temporaryURL else {
                AppLogger.error("Update download failed because no temporary file was returned", flush: true)
                self?.showError("Download failed.", detail: "No file was returned by GitHub.", presentingWindow: presentingWindow)
                return
            }

            do {
                try UpdateSecurity.validateChecksum(forFileAt: temporaryURL, expectedSHA256: manifest.sha256)
                let destination = try self?.moveDownloadedFile(from: temporaryURL, fileName: manifest.assetName)
                guard let destination else { return }
                do {
                    try UpdatePackageVerifier.verifyDownloadedDiskImage(at: destination)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
                AppLogger.info("Update download verified destination=\(destination.path)", flush: true)
                self?.showDownloadedUpdate(destination, release: release, presentingWindow: presentingWindow)
            } catch {
                AppLogger.error("Update download verification failed error=\(error.localizedDescription)", flush: true)
                self?.showError("Download verification failed.", detail: error.localizedDescription, presentingWindow: presentingWindow)
            }
        }

        activeTask = task
        task.resume()
    }

    private func moveDownloadedFile(from temporaryURL: URL, fileName: String) throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let safeFileName = UpdateSecurity.safeDownloadFileName(fileName)
        var destination = downloads.appendingPathComponent(safeFileName)
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
            \(release.tagName) was verified and downloaded to:

            \(destination.path)

            The disk image signature, Developer ID Team ID, notarization, manifest signature, and SHA-256 checksum were verified.
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

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private enum UpdateCheckerError: LocalizedError {
    case manifestTagMismatch
    case manifestIsNotNewer
    case invalidDiskImageName
    case manifestAssetMissing

    var errorDescription: String? {
        switch self {
        case .manifestTagMismatch:
            "The signed update manifest does not match the GitHub release tag."
        case .manifestIsNotNewer:
            "The signed update manifest is not newer than the installed app."
        case .invalidDiskImageName:
            "The signed update manifest does not point to a DMG file."
        case .manifestAssetMissing:
            "The signed update manifest does not match a DMG asset on this GitHub release."
        }
    }
}

enum UpdateAvailability: Equatable {
    case noPublishedReleases
    case installedBuildIsNewer(GitHubRelease)
    case upToDate(GitHubRelease)
    case updateAvailable(GitHubRelease)
}

enum UpdateReleaseSelector {
    static func availability(from releases: [GitHubRelease], currentVersion: String) -> UpdateAvailability {
        guard let newestRelease = newestPublishedRelease(from: releases) else {
            return .noPublishedReleases
        }

        switch VersionComparator.compare(newestRelease.normalizedTag, to: currentVersion) {
        case .orderedDescending:
            return .updateAvailable(newestRelease)
        case .orderedAscending:
            return .installedBuildIsNewer(newestRelease)
        default:
            return .upToDate(newestRelease)
        }
    }

    static func newestPublishedRelease(from releases: [GitHubRelease]) -> GitHubRelease? {
        releases
            .filter { !$0.isDraft && !$0.isPrerelease && !$0.normalizedTag.isEmpty }
            .max {
                VersionComparator.compare($0.normalizedTag, to: $1.normalizedTag) == .orderedAscending
            }
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]
    let isDraft: Bool
    let isPrerelease: Bool

    var normalizedTag: String {
        VersionComparator.normalizedVersion(tagName)
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }
}

struct GitHubAsset: Decodable, Equatable {
    let name: String
    let contentType: String?
    let downloadURL: URL

    var isUpdateManifest: Bool {
        name == UpdateSecurity.updateManifestAssetName
    }

    var isStrictDiskImage: Bool {
        let contentType = contentType?.lowercased()
        return UpdateSecurity.isDiskImageFileName(name)
            && (contentType == nil || contentType == "application/x-apple-diskimage")
    }

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case downloadURL = "browser_download_url"
    }
}
