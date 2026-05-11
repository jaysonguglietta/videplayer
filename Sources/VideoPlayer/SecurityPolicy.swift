import Foundation

enum AppSecurityPolicy {
    static var expectedDeveloperTeamID: String? {
        clean(
            Bundle.main.object(forInfoDictionaryKey: "VPExpectedDeveloperTeamID") as? String
                ?? developmentEnvironmentValue("VIDEOPLAYER_EXPECTED_TEAM_ID")
        )
    }

    static var externalMediaEnginesAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "VPExternalMediaEnginesAvailable") as? Bool ?? false
    }

    static var trustedExternalEngineTeamIDs: Set<String> {
        trustedExternalEngineTeamIDs(
            from: Bundle.main.object(forInfoDictionaryKey: "VPTrustedExternalEngineTeamIDs"),
            environment: ProcessInfo.processInfo.environment,
            includeDevelopmentOverrides: developmentEnvironmentOverridesEnabled
        )
    }

    static func trustedExternalEngineTeamIDs(
        from plistValue: Any?,
        environment: [String: String],
        includeDevelopmentOverrides: Bool
    ) -> Set<String> {
        let rawValues: [String]
        if let array = plistValue as? [String] {
            rawValues = array
        } else if let string = plistValue as? String {
            rawValues = string.components(separatedBy: ",")
        } else {
            rawValues = []
        }

        let envValues = includeDevelopmentOverrides
            ? environment["VIDEOPLAYER_TRUSTED_ENGINE_TEAM_IDS"]?.components(separatedBy: ",") ?? []
            : []

        return Set((rawValues + envValues).compactMap(clean))
    }

    static var allowsUnverifiedExternalEnginesForDevelopment: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["VIDEOPLAYER_ALLOW_UNVERIFIED_ENGINES"] == "1"
            || (Bundle.main.object(forInfoDictionaryKey: "VPAllowUnverifiedExternalEnginesForDevelopment") as? Bool ?? false)
        #else
        false
        #endif
    }

    private static var developmentEnvironmentOverridesEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func developmentEnvironmentValue(_ key: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[key]
        #else
        nil
        #endif
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
        defaults.object(forKey: Key.savePlaybackHistory) as? Bool ?? false
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
        guard AppSecurityPolicy.externalMediaEnginesAvailable else { return false }
        return defaults.object(forKey: Key.externalMediaEnginesEnabled) as? Bool ?? false
    }

    static func setExternalMediaEnginesEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        guard AppSecurityPolicy.externalMediaEnginesAvailable else {
            defaults.set(false, forKey: Key.externalMediaEnginesEnabled)
            return
        }
        defaults.set(enabled, forKey: Key.externalMediaEnginesEnabled)
    }
}

enum ExternalMediaEngineTrust {
    static func isEngineAllowed(at url: URL, defaults: UserDefaults = .standard) -> Bool {
        guard AppSecurityPolicy.externalMediaEnginesAvailable else {
            AppLogger.debug("External engine rejected because this build does not allow external engines: \(url.path)")
            return false
        }
        guard PrivacySettings.externalMediaEnginesEnabled(defaults: defaults) else {
            AppLogger.debug("External engine rejected because user opt-in is disabled: \(url.path)")
            return false
        }

        if AppSecurityPolicy.allowsUnverifiedExternalEnginesForDevelopment {
            AppLogger.warning("External engine allowed by debug-only unverified override: \(url.path)", flush: true)
            return true
        }

        let trustedTeamIDs = AppSecurityPolicy.trustedExternalEngineTeamIDs
        guard !trustedTeamIDs.isEmpty else {
            AppLogger.warning("External engine rejected because no trusted Team IDs are configured: \(url.path)", flush: true)
            return false
        }

        do {
            let target = verificationTarget(for: url)
            AppLogger.info("Validating external engine target=\(target.path) requestedPath=\(url.path)", flush: true)
            guard let teamID = try CodeSignatureVerifier.teamIdentifier(forCodeAt: target) else {
                AppLogger.warning("External engine rejected because no Team ID was found: \(target.path)", flush: true)
                return false
            }
            try CodeSignatureVerifier.assessGatekeeperExecute(for: target)
            let allowed = trustedTeamIDs.contains(teamID)
            if allowed {
                AppLogger.info("External engine trusted target=\(target.path) teamID=\(teamID)", flush: true)
            } else {
                AppLogger.warning("External engine rejected target=\(target.path) teamID=\(teamID) trusted=\(trustedTeamIDs.sorted().joined(separator: ","))", flush: true)
            }
            return allowed
        } catch {
            AppLogger.error("External engine validation failed path=\(url.path) error=\(error.localizedDescription)", flush: true)
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
        try verifyStrictCodeSignature(forCodeAt: url)
        let result = try run("/usr/bin/codesign", arguments: ["-dv", "--verbose=4", url.path])
        guard result.status == 0 else {
            throw CodeSignatureVerificationError.commandFailed(result.combinedOutput)
        }
        return teamIdentifier(from: result.combinedOutput)
    }

    static func verifyStrictCodeSignature(forCodeAt url: URL) throws {
        let verifyArguments: [String]
        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            verifyArguments = ["--verify", "--deep", "--strict", "--verbose=2", url.path]
        } else {
            verifyArguments = ["--verify", "--strict", "--verbose=2", url.path]
        }

        let result = try run("/usr/bin/codesign", arguments: verifyArguments)
        guard result.status == 0 else {
            throw CodeSignatureVerificationError.invalidCodeSignature(result.combinedOutput)
        }
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

    static func assessGatekeeperExecute(for url: URL) throws {
        let result = try run(
            "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "execute", "-vv", url.path]
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
        let commandDescription = ([executable] + arguments).joined(separator: " ")
        let startedAt = Date()
        AppLogger.info("Starting security command: \(commandDescription)", flush: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in
            group.leave()
        }

        try process.run()
        let timeout: DispatchTime = .now() + .seconds(10)
        guard group.wait(timeout: timeout) == .success else {
            process.terminate()
            if group.wait(timeout: .now() + .seconds(2)) != .success {
                process.interrupt()
            }
            AppLogger.error("Security command timed out after 10s: \(commandDescription)", flush: true)
            throw CodeSignatureVerificationError.commandTimedOut(commandDescription)
        }

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let elapsed = Date().timeIntervalSince(startedAt)
        AppLogger.info(String(format: "Security command finished status=%d elapsed=%.2fs command=%@", process.terminationStatus, elapsed, commandDescription), flush: true)
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
    case commandTimedOut(String)
    case invalidCodeSignature(String)
    case teamIdentifierMismatch(expected: String, actual: String)
    case gatekeeperAssessmentFailed(String)
    case expectedTeamIDMissing

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            "Code signature verification failed: \(detail)"
        case .commandTimedOut(let command):
            "Code signature verification timed out while running: \(command)"
        case .invalidCodeSignature(let detail):
            "Code signature validation failed: \(detail)"
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
