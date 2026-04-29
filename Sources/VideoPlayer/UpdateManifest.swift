import CryptoKit
import Foundation

struct UpdateManifest: Codable, Equatable {
    let version: String
    let build: String
    let tagName: String
    let minimumSystemVersion: String
    let assetName: String
    let assetURL: URL
    let sha256: String
    let signature: String

    var normalizedTag: String {
        tagName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    var signedPayload: String {
        [
            "version=\(version)",
            "build=\(build)",
            "tagName=\(tagName)",
            "minimumSystemVersion=\(minimumSystemVersion)",
            "assetName=\(assetName)",
            "assetURL=\(assetURL.absoluteString)",
            "sha256=\(sha256.lowercased())"
        ].joined(separator: "\n")
    }
}

enum VersionComparator {
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        normalizedVersion(candidate).compare(normalizedVersion(current), options: .numeric) == .orderedDescending
    }

    static func normalizedVersion(_ version: String) -> String {
        version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

enum UpdateSecurity {
    static let updateManifestAssetName = "video-player-update.json"

    private static let pinnedPublicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEI9IP3SeedvdTMeH97tNdu0kfWuby
    XNlvgd0/gYfMHFe5xygFyJ/i15dX4QRQIxQZ7g66R7oIlv8bXMuRyjgqYg==
    -----END PUBLIC KEY-----
    """

    static func verifiedManifest(from data: Data) throws -> UpdateManifest {
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        try verifySignature(for: manifest)
        return manifest
    }

    static func verifySignature(for manifest: UpdateManifest) throws {
        guard let signatureData = Data(base64Encoded: manifest.signature) else {
            throw UpdateSecurityError.invalidSignatureEncoding
        }

        let publicKey = try P256.Signing.PublicKey(pemRepresentation: pinnedPublicKeyPEM)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        let payload = Data(manifest.signedPayload.utf8)

        guard publicKey.isValidSignature(signature, for: payload) else {
            throw UpdateSecurityError.signatureMismatch
        }
    }

    static func sha256Hex(forFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func validateChecksum(forFileAt url: URL, expectedSHA256: String) throws {
        let actual = try sha256Hex(forFileAt: url)
        guard actual.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw UpdateSecurityError.checksumMismatch(expected: expectedSHA256.lowercased(), actual: actual)
        }
    }

    static func isDiskImageFileName(_ fileName: String) -> Bool {
        (fileName as NSString).pathExtension.caseInsensitiveCompare("dmg") == .orderedSame
    }

    static func safeDownloadFileName(_ fileName: String) -> String {
        let lastPathComponent = (fileName as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let sanitizedScalars = lastPathComponent.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        var sanitized = String(sanitizedScalars).trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty || sanitized == "." || sanitized == ".." {
            sanitized = "Video Player.dmg"
        }
        if !isDiskImageFileName(sanitized) {
            sanitized += ".dmg"
        }
        return sanitized
    }
}

enum UpdateSecurityError: LocalizedError, Equatable {
    case invalidSignatureEncoding
    case signatureMismatch
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidSignatureEncoding:
            "The update manifest signature could not be decoded."
        case .signatureMismatch:
            "The update manifest signature did not match this app's trusted signing key."
        case .checksumMismatch(let expected, let actual):
            "The downloaded update checksum did not match.\nExpected: \(expected)\nActual: \(actual)"
        }
    }
}
