import Foundation

enum MDMProfileBuilder {
    static func mobileconfig(policy: EnterprisePolicySnapshot, organization: String? = nil) -> String {
        let identifier = "com.jaysonguglietta.videoplayer.enterprise.\(UUID().uuidString)"
        let organizationName = organization ?? policy.organizationName ?? "Video Player Enterprise"
        let keys: [(String, String)] = [
            (EnterprisePolicy.Key.organizationName, stringValue(policy.organizationName ?? organizationName)),
            (EnterprisePolicy.Key.forceDisableExternalMediaEngines, boolValue(policy.forceDisableExternalMediaEngines)),
            (EnterprisePolicy.Key.forceBlockPrivateNetworkStreams, boolValue(policy.forceBlockPrivateNetworkStreams)),
            (EnterprisePolicy.Key.forceDisablePlaybackHistory, boolValue(policy.forceDisablePlaybackHistory)),
            (EnterprisePolicy.Key.forceClearHistoryOnQuit, boolValue(policy.forceClearHistoryOnQuit)),
            (EnterprisePolicy.Key.disableUpdateChecks, boolValue(policy.disableUpdateChecks)),
            (EnterprisePolicy.Key.disableSupportBundleLogExport, boolValue(policy.disableSupportBundleLogExport)),
            (EnterprisePolicy.Key.redactSupportBundlePaths, boolValue(policy.redactSupportBundlePaths)),
            (EnterprisePolicy.Key.requireLicense, boolValue(policy.requireLicense)),
            (EnterprisePolicy.Key.kioskModeEnabled, boolValue(policy.kioskModeEnabled)),
            (EnterprisePolicy.Key.kioskPlaylistURL, stringValue(policy.kioskPlaylistURLString ?? "")),
            (EnterprisePolicy.Key.supportUploadURL, stringValue(policy.supportUploadURLString ?? "")),
            (EnterprisePolicy.Key.supportUploadHostSuffixes, arrayValue(policy.supportUploadHostSuffixes)),
            (EnterprisePolicy.Key.supportUploadTokenKeychainService, stringValue(policy.supportUploadTokenKeychainService ?? "")),
            (EnterprisePolicy.Key.updateChannel, stringValue(policy.updateChannel)),
            (EnterprisePolicy.Key.sparkleAppcastURL, stringValue(policy.sparkleAppcastURLString ?? "")),
            (EnterprisePolicy.Key.allowedStreamHostSuffixes, arrayValue(policy.allowedStreamHostSuffixes))
        ]

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>PayloadContent</key>
            <array>
                <dict>
                    <key>PayloadType</key>
                    <string>com.apple.ManagedClient.preferences</string>
                    <key>PayloadVersion</key>
                    <integer>1</integer>
                    <key>PayloadIdentifier</key>
                    <string>\(xml(identifier)).preferences</string>
                    <key>PayloadUUID</key>
                    <string>\(UUID().uuidString)</string>
                    <key>PayloadDisplayName</key>
                    <string>Video Player Managed Preferences</string>
                    <key>PayloadContent</key>
                    <dict>
                        <key>com.jaysonguglietta.videoplayer</key>
                        <dict>
                            <key>Forced</key>
                            <array>
                                <dict>
                                    <key>mcx_preference_settings</key>
                                    <dict>
        \(keys.map { "                                <key>\(xml($0.0))</key>\n                                \($0.1)" }.joined(separator: "\n"))
                                    </dict>
                                </dict>
                            </array>
                        </dict>
                    </dict>
                </dict>
            </array>
            <key>PayloadDisplayName</key>
            <string>Video Player Enterprise Policy</string>
            <key>PayloadIdentifier</key>
            <string>\(xml(identifier))</string>
            <key>PayloadOrganization</key>
            <string>\(xml(organizationName))</string>
            <key>PayloadRemovalDisallowed</key>
            <false/>
            <key>PayloadType</key>
            <string>Configuration</string>
            <key>PayloadUUID</key>
            <string>\(UUID().uuidString)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
        </plist>
        """
    }

    private static func boolValue(_ value: Bool) -> String {
        value ? "<true/>" : "<false/>"
    }

    private static func stringValue(_ value: String) -> String {
        "<string>\(xml(value))</string>"
    }

    private static func arrayValue(_ values: [String]) -> String {
        if values.isEmpty {
            return "<array/>"
        }
        return "<array>\n\(values.map { "                                    <string>\(xml($0))</string>" }.joined(separator: "\n"))\n                                </array>"
    }

    private static func xml(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
