import CryptoKit
import Foundation

struct EnterpriseActivationRequest: Codable, Equatable {
    let appVersion: String
    let bundleID: String
    let machineHash: String
    let requestedBy: String
    let licenseKey: String
    let generatedAt: String
}

enum EnterpriseActivationManager {
    static func activationRequest(licenseKey: String, requestedBy: String, date: Date = Date()) -> EnterpriseActivationRequest {
        EnterpriseActivationRequest(
            appVersion: OpenSourceNotices.appVersion,
            bundleID: Bundle.main.bundleIdentifier ?? "com.jaysonguglietta.videoplayer",
            machineHash: machineHash(),
            requestedBy: requestedBy.trimmingCharacters(in: .whitespacesAndNewlines),
            licenseKey: licenseKey.trimmingCharacters(in: .whitespacesAndNewlines),
            generatedAt: dateFormatter.string(from: date)
        )
    }

    static func writeActivationRequest(_ request: EnterpriseActivationRequest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(request).write(to: url, options: [.atomic])
    }

    static func deactivateLicense() throws {
        let licenseURL = EnterpriseLicenseManager.defaultLicenseURL
        if FileManager.default.fileExists(atPath: licenseURL.path) {
            try FileManager.default.removeItem(at: licenseURL)
        }
    }

    private static func machineHash() -> String {
        let raw = [
            Host.current().localizedName ?? "unknown-host",
            NSUserName(),
            Bundle.main.bundleIdentifier ?? "com.jaysonguglietta.videoplayer"
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
