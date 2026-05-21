import Foundation

struct EnterprisePolicySnapshot: Equatable {
    let organizationName: String?
    let forceDisableExternalMediaEngines: Bool
    let forceBlockPrivateNetworkStreams: Bool
    let forceDisablePlaybackHistory: Bool
    let forceClearHistoryOnQuit: Bool
    let disableUpdateChecks: Bool
    let disableSupportBundleLogExport: Bool
    let redactSupportBundlePaths: Bool
    let requireLicense: Bool
    let allowedStreamHostSuffixes: [String]
    let kioskModeEnabled: Bool
    let kioskPlaylistURLString: String?
    let supportUploadURLString: String?
    let updateChannel: String
    let sparkleAppcastURLString: String?

    var hasManagedRestrictions: Bool {
        forceDisableExternalMediaEngines
            || forceBlockPrivateNetworkStreams
            || forceDisablePlaybackHistory
            || forceClearHistoryOnQuit
            || disableUpdateChecks
            || disableSupportBundleLogExport
            || !allowedStreamHostSuffixes.isEmpty
            || requireLicense
            || kioskModeEnabled
            || supportUploadURLString != nil
            || updateChannel != "github"
            || sparkleAppcastURLString != nil
    }

    var kioskPlaylistURL: URL? {
        guard let kioskPlaylistURLString else { return nil }
        return URL(string: kioskPlaylistURLString)
            ?? URL(fileURLWithPath: (kioskPlaylistURLString as NSString).expandingTildeInPath)
    }

    var supportUploadURL: URL? {
        guard let supportUploadURLString else { return nil }
        return URL(string: supportUploadURLString)
    }

    var sparkleAppcastURL: URL? {
        guard let sparkleAppcastURLString else { return nil }
        return URL(string: sparkleAppcastURLString)
    }

    func allowsStreamHost(_ host: String) -> Bool {
        Self.host(host, matchesAllowedSuffixes: allowedStreamHostSuffixes)
    }

    static func host(_ host: String, matchesAllowedSuffixes suffixes: [String]) -> Bool {
        let normalizedHost = normalizeHost(host)
        let normalizedSuffixes = suffixes.map(normalizeHost).filter { !$0.isEmpty }
        guard !normalizedSuffixes.isEmpty else { return true }

        return normalizedSuffixes.contains { suffix in
            normalizedHost == suffix || normalizedHost.hasSuffix(".\(suffix)")
        }
    }

    var summaryLines: [String] {
        [
            "Organization: \(organizationName ?? "Not configured")",
            "Managed restrictions: \(hasManagedRestrictions ? "Yes" : "No")",
            "External engines disabled by policy: \(forceDisableExternalMediaEngines ? "Yes" : "No")",
            "Private/local streams blocked by policy: \(forceBlockPrivateNetworkStreams ? "Yes" : "No")",
            "Playback history disabled by policy: \(forceDisablePlaybackHistory ? "Yes" : "No")",
            "Clear history on quit forced: \(forceClearHistoryOnQuit ? "Yes" : "No")",
            "Update checks disabled by policy: \(disableUpdateChecks ? "Yes" : "No")",
            "Support bundle logs disabled by policy: \(disableSupportBundleLogExport ? "Yes" : "No")",
            "Support bundles redact paths: \(redactSupportBundlePaths ? "Yes" : "No")",
            "License required by policy: \(requireLicense ? "Yes" : "No")",
            "Kiosk mode: \(kioskModeEnabled ? "Yes" : "No")",
            "Kiosk playlist: \(kioskPlaylistURLString ?? "Not configured")",
            "Support upload endpoint: \(supportUploadURLString ?? "Not configured")",
            "Update channel: \(updateChannel)",
            "Sparkle appcast URL: \(sparkleAppcastURLString ?? "Not configured")",
            "Allowed stream host suffixes: \(allowedStreamHostSuffixes.isEmpty ? "Any public host" : allowedStreamHostSuffixes.joined(separator: ", "))"
        ]
    }

    private static func normalizeHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum EnterprisePolicy {
    enum Key {
        static let organizationName = "EnterpriseOrganizationName"
        static let forceDisableExternalMediaEngines = "EnterpriseForceDisableExternalMediaEngines"
        static let forceBlockPrivateNetworkStreams = "EnterpriseForceBlockPrivateNetworkStreams"
        static let forceDisablePlaybackHistory = "EnterpriseForceDisablePlaybackHistory"
        static let forceClearHistoryOnQuit = "EnterpriseForceClearHistoryOnQuit"
        static let disableUpdateChecks = "EnterpriseDisableUpdateChecks"
        static let disableSupportBundleLogExport = "EnterpriseDisableSupportBundleLogExport"
        static let redactSupportBundlePaths = "EnterpriseRedactSupportBundles"
        static let requireLicense = "EnterpriseRequireLicense"
        static let allowedStreamHostSuffixes = "EnterpriseAllowedStreamHostSuffixes"
        static let kioskModeEnabled = "EnterpriseKioskModeEnabled"
        static let kioskPlaylistURL = "EnterpriseKioskPlaylistURL"
        static let supportUploadURL = "EnterpriseSupportUploadURL"
        static let updateChannel = "EnterpriseUpdateChannel"
        static let sparkleAppcastURL = "EnterpriseSparkleAppcastURL"
    }

    static func snapshot(defaults: UserDefaults = .standard) -> EnterprisePolicySnapshot {
        EnterprisePolicySnapshot(
            organizationName: clean(defaults.string(forKey: Key.organizationName)),
            forceDisableExternalMediaEngines: bool(forKey: Key.forceDisableExternalMediaEngines, defaults: defaults),
            forceBlockPrivateNetworkStreams: bool(forKey: Key.forceBlockPrivateNetworkStreams, defaults: defaults),
            forceDisablePlaybackHistory: bool(forKey: Key.forceDisablePlaybackHistory, defaults: defaults),
            forceClearHistoryOnQuit: bool(forKey: Key.forceClearHistoryOnQuit, defaults: defaults),
            disableUpdateChecks: bool(forKey: Key.disableUpdateChecks, defaults: defaults),
            disableSupportBundleLogExport: bool(forKey: Key.disableSupportBundleLogExport, defaults: defaults),
            redactSupportBundlePaths: bool(forKey: Key.redactSupportBundlePaths, defaults: defaults, defaultValue: true),
            requireLicense: bool(forKey: Key.requireLicense, defaults: defaults),
            allowedStreamHostSuffixes: stringList(forKey: Key.allowedStreamHostSuffixes, defaults: defaults),
            kioskModeEnabled: bool(forKey: Key.kioskModeEnabled, defaults: defaults),
            kioskPlaylistURLString: clean(defaults.string(forKey: Key.kioskPlaylistURL)),
            supportUploadURLString: clean(defaults.string(forKey: Key.supportUploadURL)),
            updateChannel: clean(defaults.string(forKey: Key.updateChannel))?.lowercased() ?? "github",
            sparkleAppcastURLString: clean(defaults.string(forKey: Key.sparkleAppcastURL))
        )
    }

    static func bool(forKey key: String, defaults: UserDefaults = .standard, defaultValue: Bool = false) -> Bool {
        guard let value = defaults.object(forKey: key) else { return defaultValue }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        if let stringValue = value as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return defaultValue
            }
        }
        return defaultValue
    }

    static func stringList(forKey key: String, defaults: UserDefaults = .standard) -> [String] {
        if let arrayValue = defaults.stringArray(forKey: key) {
            return normalizedList(arrayValue)
        }

        if let stringValue = defaults.string(forKey: key) {
            return normalizedList(stringValue.components(separatedBy: ","))
        }

        return []
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        values
            .compactMap(clean)
            .map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    .lowercased()
            }
            .filter { !$0.isEmpty }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
