import Darwin
import Foundation

enum NetworkStreamValidator {
    private static let allowedSchemes: Set<String> = ["http", "https", "rtsp", "rtsps"]

    static func validatedURL(
        from value: String,
        allowPrivateNetworkHosts: Bool = PrivacySettings.allowPrivateNetworkStreams()
    ) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmedValue),
            let scheme = url.scheme?.lowercased(),
            allowedSchemes.contains(scheme),
            let host = url.host,
            !host.isEmpty,
            allowPrivateNetworkHosts || !isPrivateOrLocalHost(host)
        else {
            return nil
        }

        return url
    }

    static func isPrivateOrLocalHost(_ host: String) -> Bool {
        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        if normalizedHost == "localhost"
            || normalizedHost.hasSuffix(".localhost")
            || normalizedHost.hasSuffix(".local")
            || !normalizedHost.contains(".") && !normalizedHost.contains(":") {
            return true
        }

        if let ipv4 = IPv4Address(normalizedHost) {
            return ipv4.isPrivateOrLocal
        }
        if let ipv6 = IPv6Address(normalizedHost) {
            return ipv6.isPrivateOrLocal
        }
        return false
    }
}

enum MediaPersistence {
    static func storageString(for url: URL) -> String {
        guard !url.isFileURL else { return url.absoluteString }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    static func storageString(forStoredValue value: String) -> String {
        guard let url = URL(string: value) else { return value }
        return storageString(for: url)
    }
}

private struct IPv4Address {
    private let value: UInt32

    init?(_ host: String) {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }

        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(byte)
        }
        self.value = value
    }

    var isPrivateOrLocal: Bool {
        inRange(0x00000000, mask: 0xff000000)      // 0.0.0.0/8
            || inRange(0x0a000000, mask: 0xff000000) // 10.0.0.0/8
            || inRange(0x7f000000, mask: 0xff000000) // 127.0.0.0/8
            || inRange(0xa9fe0000, mask: 0xffff0000) // 169.254.0.0/16
            || inRange(0xac100000, mask: 0xfff00000) // 172.16.0.0/12
            || inRange(0xc0a80000, mask: 0xffff0000) // 192.168.0.0/16
            || inRange(0x64400000, mask: 0xffc00000) // 100.64.0.0/10
            || inRange(0xc6120000, mask: 0xfffe0000) // 198.18.0.0/15
            || inRange(0xe0000000, mask: 0xf0000000) // 224.0.0.0/4
    }

    private func inRange(_ network: UInt32, mask: UInt32) -> Bool {
        (value & mask) == network
    }
}

private struct IPv6Address {
    private let bytes: [UInt8]

    init?(_ host: String) {
        var raw = in6_addr()
        guard inet_pton(AF_INET6, host, &raw) == 1 else { return nil }
        self.bytes = withUnsafeBytes(of: raw) { Array($0) }
    }

    var isPrivateOrLocal: Bool {
        isLoopback || isUniqueLocal || isLinkLocal || isMulticast
    }

    private var isLoopback: Bool {
        bytes.prefix(15).allSatisfy { $0 == 0 } && bytes.last == 1
    }

    private var isUniqueLocal: Bool {
        (bytes[0] & 0xfe) == 0xfc
    }

    private var isLinkLocal: Bool {
        bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
    }

    private var isMulticast: Bool {
        bytes[0] == 0xff
    }
}
