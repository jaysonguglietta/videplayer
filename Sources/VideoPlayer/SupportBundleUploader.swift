import Foundation
import Security

struct SupportUploadResult: Equatable {
    let statusCode: Int
    let responseText: String

    var succeeded: Bool {
        (200..<300).contains(statusCode)
    }
}

enum SupportBundleUploader {
    static func upload(
        bundleDirectory: URL,
        endpoint: URL,
        allowedHostSuffixes: [String] = [],
        bearerToken: String? = nil,
        resolvedAddressesForHost: @escaping (String) async -> [String]? = SystemNetworkAddressResolver.resolvedAddresses
    ) async throws -> SupportUploadResult {
        let endpoint = try await validatedEndpoint(
            endpoint,
            allowedHostSuffixes: allowedHostSuffixes,
            resolvedAddressesForHost: resolvedAddressesForHost
        )
        let files = try supportFiles(in: bundleDirectory)
        let boundary = "VideoPlayerBoundary-\(UUID().uuidString)"
        let body = try multipartBody(files: files, boundary: boundary)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("VideoPlayer/\(OpenSourceNotices.appVersion)", forHTTPHeaderField: "User-Agent")
        if let authorization = authorizationHeaderValue(forBearerToken: bearerToken) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let responseText = String(data: data.prefix(4_096), encoding: .utf8) ?? ""
        return SupportUploadResult(statusCode: statusCode, responseText: responseText)
    }

    static func validatedEndpoint(
        _ endpoint: URL,
        allowedHostSuffixes: [String] = [],
        resolvedAddressesForHost: @escaping (String) async -> [String]? = SystemNetworkAddressResolver.resolvedAddresses
    ) async throws -> URL {
        guard endpoint.scheme?.lowercased() == "https",
              let host = endpoint.host,
              !host.isEmpty
        else {
            throw SupportUploadError.invalidEndpoint("Support uploads require an HTTPS endpoint with a host.")
        }

        let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        guard components?.user == nil, components?.password == nil else {
            throw SupportUploadError.invalidEndpoint("Support upload endpoints cannot include embedded credentials.")
        }

        guard !NetworkStreamValidator.isPrivateOrLocalHost(host) else {
            throw SupportUploadError.invalidEndpoint("Support upload endpoints cannot target private or local hosts.")
        }

        guard EnterprisePolicySnapshot.host(host, matchesAllowedSuffixes: allowedHostSuffixes) else {
            throw SupportUploadError.invalidEndpoint("Support upload endpoint host is not in the configured allow-list.")
        }

        guard let resolvedAddresses = await resolvedAddressesForHost(host),
              !resolvedAddresses.isEmpty,
              !resolvedAddresses.contains(where: NetworkStreamValidator.isPrivateOrLocalHost)
        else {
            throw SupportUploadError.invalidEndpoint("Support upload endpoint DNS must resolve to public addresses.")
        }

        return endpoint
    }

    static func authorizationHeaderValue(forBearerToken token: String?) -> String? {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            return nil
        }
        return "Bearer \(token)"
    }

    static func bearerToken(keychainService: String?) throws -> String? {
        guard let keychainService = keychainService?.trimmingCharacters(in: .whitespacesAndNewlines),
              !keychainService.isEmpty
        else {
            return nil
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let bundleID = Bundle.main.bundleIdentifier {
            query[kSecAttrAccount as String] = bundleID
        }

        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound, query[kSecAttrAccount as String] != nil {
            query.removeValue(forKey: kSecAttrAccount as String)
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }

        guard status != errSecItemNotFound else {
            throw SupportUploadError.missingBearerToken(keychainService)
        }
        guard status == errSecSuccess else {
            throw SupportUploadError.keychainLookupFailed(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw SupportUploadError.missingBearerToken(keychainService)
        }
        return token
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
    case invalidEndpoint(String)
    case missingBearerToken(String)
    case keychainLookupFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "The support bundle does not contain uploadable files."
        case .fileTooLarge(let fileName):
            return "\(fileName) is larger than the support upload limit."
        case .invalidEndpoint(let reason):
            return reason
        case .missingBearerToken(let service):
            return "The support upload bearer token was not found in Keychain service '\(service)'."
        case .keychainLookupFailed(let status):
            return "The support upload bearer token could not be read from Keychain. OSStatus: \(status)."
        }
    }
}
