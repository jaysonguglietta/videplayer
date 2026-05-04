import Foundation

enum AppSecurityPolicy {
    static var expectedDeveloperTeamID: String? {
        clean(
            Bundle.main.object(forInfoDictionaryKey: "VPExpectedDeveloperTeamID") as? String
                ?? ProcessInfo.processInfo.environment["VIDEOPLAYER_EXPECTED_TEAM_ID"]
        )
    }

    static var trustedExternalEngineTeamIDs: Set<String> {
        let plistValue = Bundle.main.object(forInfoDictionaryKey: "VPTrustedExternalEngineTeamIDs")
        let rawValues: [String]
        if let array = plistValue as? [String] {
            rawValues = array
        } else if let string = plistValue as? String {
            rawValues = string.components(separatedBy: ",")
        } else {
            rawValues = []
        }

        let envValues = ProcessInfo.processInfo.environment["VIDEOPLAYER_TRUSTED_ENGINE_TEAM_IDS"]?
            .components(separatedBy: ",") ?? []

        return Set((rawValues + envValues).compactMap(clean))
    }

    static var allowsUnverifiedExternalEnginesForDevelopment: Bool {
        ProcessInfo.processInfo.environment["VIDEOPLAYER_ALLOW_UNVERIFIED_ENGINES"] == "1"
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum PrivacySettings {
    private enum Key {
        static let savePlaybackHistory = "savePlaybackHistory"
        static let clearHistoryOnQuit = "clearHistoryOnQuit"
        static let allowPrivateNetworkStreams = "allowPrivateNetworkStreams"
        static let externalMediaEnginesEnabled = "externalMediaEnginesEnabled"
    }

    static func savePlaybackHistory(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.savePlaybackHistory) as? Bool ?? true
    }

    static func setSavePlaybackHistory(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.savePlaybackHistory)
    }

    static func clearHistoryOnQuit(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.clearHistoryOnQuit) as? Bool ?? false
    }

    static func setClearHistoryOnQuit(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.clearHistoryOnQuit)
    }

    static func allowPrivateNetworkStreams(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.allowPrivateNetworkStreams) as? Bool ?? false
    }

    static func setAllowPrivateNetworkStreams(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.allowPrivateNetworkStreams)
    }

    static func externalMediaEnginesEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.externalMediaEnginesEnabled) as? Bool ?? false
    }

    static func setExternalMediaEnginesEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Key.externalMediaEnginesEnabled)
    }
}

enum ExternalMediaEngineTrust {
    static func isEngineAllowed(at url: URL, defaults: UserDefaults = .standard) -> Bool {
        guard PrivacySettings.externalMediaEnginesEnabled(defaults: defaults) else {
            return false
        }

        if AppSecurityPolicy.allowsUnverifiedExternalEnginesForDevelopment {
            return true
        }

        let trustedTeamIDs = AppSecurityPolicy.trustedExternalEngineTeamIDs
        guard !trustedTeamIDs.isEmpty else {
            return false
        }

        do {
            guard let teamID = try CodeSignatureVerifier.teamIdentifier(forCodeAt: verificationTarget(for: url)) else {
                return false
            }
            return trustedTeamIDs.contains(teamID)
        } catch {
            return false
        }
    }

    static func verificationTarget(for url: URL) -> URL {
        let path = url.path
        if let range = path.range(of: ".app/") {
            let appEnd = path.index(before: range.upperBound)
            let appPath = String(path[..<appEnd])
            return URL(fileURLWithPath: appPath)
        }
        return url
    }
}

enum CodeSignatureVerifier {
    static func teamIdentifier(forCodeAt url: URL) throws -> String? {
        let result = try run("/usr/bin/codesign", arguments: ["-dv", "--verbose=4", url.path])
        guard result.status == 0 else {
            throw CodeSignatureVerificationError.commandFailed(result.combinedOutput)
        }
        return teamIdentifier(from: result.combinedOutput)
    }

    static func verifyTeamIdentifier(forCodeAt url: URL, expectedTeamID: String) throws {
        let actualTeamID = try teamIdentifier(forCodeAt: url)
        guard actualTeamID == expectedTeamID else {
            throw CodeSignatureVerificationError.teamIdentifierMismatch(
                expected: expectedTeamID,
                actual: actualTeamID ?? "none"
            )
        }
    }

    static func assessGatekeeperOpen(for url: URL) throws {
        let result = try run(
            "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "open", "--context", "context:primary-signature", "-vv", url.path]
        )
        guard result.status == 0 else {
            throw CodeSignatureVerificationError.gatekeeperAssessmentFailed(result.combinedOutput)
        }
    }

    static func teamIdentifier(from diagnosticOutput: String) -> String? {
        diagnosticOutput
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.hasPrefix("TeamIdentifier=") else { return nil }
                let value = line.replacingOccurrences(of: "TeamIdentifier=", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty || value == "not set" ? nil : value
            }
            .first
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(status: process.terminationStatus, output: stdout, error: stderr)
    }
}

struct CommandResult {
    let status: Int32
    let output: String
    let error: String

    var combinedOutput: String {
        [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum CodeSignatureVerificationError: LocalizedError, Equatable {
    case commandFailed(String)
    case teamIdentifierMismatch(expected: String, actual: String)
    case gatekeeperAssessmentFailed(String)
    case expectedTeamIDMissing

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            "Code signature verification failed: \(detail)"
        case .teamIdentifierMismatch(let expected, let actual):
            "The downloaded update was signed by team \(actual), but this app only trusts team \(expected)."
        case .gatekeeperAssessmentFailed(let detail):
            "Gatekeeper rejected the downloaded update: \(detail)"
        case .expectedTeamIDMissing:
            "This app build does not declare a trusted Developer ID Team ID for updates."
        }
    }
}

enum UpdatePackageVerifier {
    static func verifyDownloadedDiskImage(at url: URL) throws {
        guard let expectedTeamID = AppSecurityPolicy.expectedDeveloperTeamID else {
            throw CodeSignatureVerificationError.expectedTeamIDMissing
        }

        try CodeSignatureVerifier.verifyTeamIdentifier(forCodeAt: url, expectedTeamID: expectedTeamID)
        try CodeSignatureVerifier.assessGatekeeperOpen(for: url)
    }
}
