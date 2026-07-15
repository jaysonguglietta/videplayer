import Foundation
import Security

struct StreamCredential: Codable, Equatable {
    let username: String
    let password: String
}

enum StreamCredentialStoreError: LocalizedError {
    case insecureScheme
    case invalidHost
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .insecureScheme:
            "Credentials can only be saved for HTTPS or RTSPS streams."
        case .invalidHost:
            "The stream host is invalid."
        case .keychain(let status):
            "The stream credential could not be stored in Keychain (status \(status))."
        }
    }
}

enum StreamCredentialStore {
    private static let service = "com.jaysonguglietta.videoplayer.stream-credentials"
    private static let hostsKey = "streamCredentialHosts"

    static func save(_ credential: StreamCredential, for url: URL) throws {
        guard let host = normalizedHost(for: url) else { throw StreamCredentialStoreError.invalidHost }
        guard isSecureCredentialScheme(url.scheme) else { throw StreamCredentialStoreError.insecureScheme }
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(host: host)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            rememberHost(host)
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw StreamCredentialStoreError.keychain(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw StreamCredentialStoreError.keychain(addStatus)
        }
        rememberHost(host)
    }

    static func credential(for url: URL) -> StreamCredential? {
        guard let host = normalizedHost(for: url), isSecureCredentialScheme(url.scheme) else { return nil }
        var query = baseQuery(host: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return try? JSONDecoder().decode(StreamCredential.self, from: data)
    }

    static func removeCredential(for url: URL) {
        guard let host = normalizedHost(for: url) else { return }
        SecItemDelete(baseQuery(host: host) as CFDictionary)
        var hosts = storedHosts()
        hosts.remove(host)
        UserDefaults.standard.set(hosts.sorted(), forKey: hostsKey)
    }

    static func removeAll() {
        for host in storedHosts() {
            SecItemDelete(baseQuery(host: host) as CFDictionary)
        }
        UserDefaults.standard.removeObject(forKey: hostsKey)
    }

    static func storedHosts(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: hostsKey) ?? [])
    }

    static func authenticatedURL(_ url: URL, credential: StreamCredential?) -> URL {
        guard let credential,
              isSecureCredentialScheme(url.scheme),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }
        components.user = credential.username
        components.password = credential.password
        return components.url ?? url
    }

    private static func normalizedHost(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    private static func isSecureCredentialScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "rtsps"
    }

    private static func baseQuery(host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
    }

    private static func rememberHost(_ host: String) {
        var hosts = storedHosts()
        hosts.insert(host)
        UserDefaults.standard.set(hosts.sorted(), forKey: hostsKey)
    }
}
