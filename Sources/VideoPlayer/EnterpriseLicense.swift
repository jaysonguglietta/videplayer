import CryptoKit
import Foundation

struct EnterpriseLicense: Codable, Equatable {
    let customerName: String
    let licenseID: String
    let seatLimit: Int
    let expiresAt: String?
    let supportLevel: String
    let features: [String]
    let contactEmail: String?

    var signedPayload: String {
        [
            "customerName=\(customerName)",
            "licenseID=\(licenseID)",
            "seatLimit=\(seatLimit)",
            "expiresAt=\(expiresAt ?? "")",
            "supportLevel=\(supportLevel)",
            "features=\(features.sorted().joined(separator: ","))",
            "contactEmail=\(contactEmail ?? "")"
        ].joined(separator: "\n") + "\n"
    }

    var expirationDate: Date? {
        guard let expiresAt, !expiresAt.isEmpty else { return nil }
        return Self.dateFormatter.date(from: expiresAt)
            ?? Self.dateOnlyFormatter.date(from: expiresAt)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateOnlyFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

struct EnterpriseLicenseEnvelope: Codable, Equatable {
    let license: EnterpriseLicense
    let signature: String?
}

enum EnterpriseLicenseStatus: Equatable {
    case notInstalled
    case valid(EnterpriseLicense)
    case expired(EnterpriseLicense)
    case unverified(EnterpriseLicense)
    case invalid(String)

    var title: String {
        switch self {
        case .notInstalled:
            "No enterprise license installed"
        case .valid:
            "Enterprise license active"
        case .expired:
            "Enterprise license expired"
        case .unverified:
            "Enterprise license installed, signature not enforced"
        case .invalid:
            "Enterprise license invalid"
        }
    }

    var isOperationallyUsable: Bool {
        switch self {
        case .valid, .unverified:
            true
        case .notInstalled, .expired, .invalid:
            false
        }
    }

    var detailLines: [String] {
        switch self {
        case .notInstalled:
            return [
                "Status: Not installed",
                "Install a signed license JSON when enterprise licensing is required by policy."
            ]
        case .valid(let license):
            return licenseLines(license, status: "Valid and signature verified")
        case .expired(let license):
            return licenseLines(license, status: "Expired")
        case .unverified(let license):
            return licenseLines(
                license,
                status: "Installed but no app license public key is configured; use this as an operational record only."
            )
        case .invalid(let reason):
            return [
                "Status: Invalid",
                "Reason: \(reason)"
            ]
        }
    }

    var reportText: String {
        ([title] + detailLines).joined(separator: "\n")
    }

    private func licenseLines(_ license: EnterpriseLicense, status: String) -> [String] {
        [
            "Status: \(status)",
            "Customer: \(license.customerName)",
            "License ID: \(license.licenseID)",
            "Seats: \(license.seatLimit)",
            "Expires: \(license.expiresAt ?? "Never")",
            "Support: \(license.supportLevel)",
            "Features: \(license.features.isEmpty ? "None" : license.features.sorted().joined(separator: ", "))",
            "Contact: \(license.contactEmail ?? "Not configured")"
        ]
    }
}

enum EnterpriseLicenseManager {
    static var licensePublicKeyBase64: String? {
        clean(Bundle.main.object(forInfoDictionaryKey: "VPEnterpriseLicensePublicKey") as? String)
    }

    static var defaultLicenseURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("license.json", isDirectory: false)
    }

    static var applicationSupportDirectory: URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseDirectory.appendingPathComponent("Video Player", isDirectory: true)
    }

    static func status(
        licenseURL: URL = defaultLicenseURL,
        publicKeyBase64: String? = licensePublicKeyBase64,
        now: Date = Date()
    ) -> EnterpriseLicenseStatus {
        guard FileManager.default.fileExists(atPath: licenseURL.path) else {
            return .notInstalled
        }

        do {
            let data = try Data(contentsOf: licenseURL)
            let envelope = try JSONDecoder().decode(EnterpriseLicenseEnvelope.self, from: data)

            if let expirationDate = envelope.license.expirationDate, expirationDate < now {
                return .expired(envelope.license)
            }

            guard let publicKeyBase64 = clean(publicKeyBase64) else {
                return .unverified(envelope.license)
            }

            guard let signature = clean(envelope.signature) else {
                return .invalid("The license file is missing a signature.")
            }

            return verify(envelope.license, signatureBase64: signature, publicKeyBase64: publicKeyBase64)
                ? .valid(envelope.license)
                : .invalid("The license signature does not match this app.")
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    static func installLicense(from sourceURL: URL, destinationURL: URL = defaultLicenseURL) throws {
        let data = try Data(contentsOf: sourceURL)
        _ = try JSONDecoder().decode(EnterpriseLicenseEnvelope.self, from: data)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try data.write(to: destinationURL, options: [.atomic])
    }

    static func verify(_ license: EnterpriseLicense, signatureBase64: String, publicKeyBase64: String) -> Bool {
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              let signatureData = Data(base64Encoded: signatureBase64)
        else {
            return false
        }

        do {
            let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
            return publicKey.isValidSignature(signature, for: Data(license.signedPayload.utf8))
        } catch {
            return false
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
