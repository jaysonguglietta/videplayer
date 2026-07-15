import Foundation

struct MediaEngineDiagnostic: Equatable {
    let name: String
    let path: String
    let exists: Bool
    let executableOrReadable: Bool
    let trusted: Bool
    let teamID: String?
    let detail: String
}

struct MediaEngineDoctorReport: Equatable {
    let diagnostics: [MediaEngineDiagnostic]

    var text: String {
        var lines = [
            "Playback Engine Doctor",
            "======================",
            "External engine build: \(AppSecurityPolicy.externalMediaEnginesAvailable ? "Available" : "Unavailable")",
            "External engines enabled: \(PrivacySettings.externalMediaEnginesEnabled() ? "Yes" : "No")",
            "Trusted Team IDs: \(AppSecurityPolicy.trustedExternalEngineTeamIDs.isEmpty ? "None configured" : AppSecurityPolicy.trustedExternalEngineTeamIDs.sorted().joined(separator: ", "))",
            ""
        ]

        for diagnostic in diagnostics {
            lines.append("\(diagnostic.name)")
            lines.append("- Path: \(diagnostic.path)")
            lines.append("- Exists: \(diagnostic.exists ? "Yes" : "No")")
            lines.append("- Readable/executable: \(diagnostic.executableOrReadable ? "Yes" : "No")")
            lines.append("- Trusted: \(diagnostic.trusted ? "Yes" : "No")")
            lines.append("- Team ID: \(diagnostic.teamID ?? "Unknown")")
            lines.append("- Detail: \(diagnostic.detail)")
            lines.append("")
        }

        if diagnostics.allSatisfy({ !$0.trusted }) {
            lines.append("Recommended action: Install or repair VLC/mpv, then confirm the app build trusts that engine Team ID. Use the default native-only build for customers who do not need advanced codecs.")
        } else {
            lines.append("Recommended action: At least one external engine is trusted. Enable external engines from Playback when a file needs broader codec support.")
        }

        return lines.joined(separator: "\n")
    }
}

enum MediaEngineDoctor {
    static func report() -> MediaEngineDoctorReport {
        let vlcDiagnostics = VLCBridge.candidateLibraryPaths().map {
            inspect(name: "VLC/libVLC", path: $0, requiresExecutable: false)
        }
        let mpvDiagnostics = MPVBridge.candidateExecutablePaths().map {
            inspect(name: "mpv", path: $0, requiresExecutable: true)
        }
        return MediaEngineDoctorReport(diagnostics: vlcDiagnostics + mpvDiagnostics)
    }

    private static func inspect(name: String, path: String, requiresExecutable: Bool) -> MediaEngineDiagnostic {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: path)
        let accessible = requiresExecutable
            ? fileManager.isExecutableFile(atPath: path)
            : fileManager.isReadableFile(atPath: path)

        guard exists, accessible else {
            return MediaEngineDiagnostic(
                name: name,
                path: path,
                exists: exists,
                executableOrReadable: accessible,
                trusted: false,
                teamID: nil,
                detail: exists ? "File exists but is not accessible." : "Candidate is not installed at this path."
            )
        }

        let target = ExternalMediaEngineTrust.verificationTarget(for: url)
        let teamID = try? CodeSignatureVerifier.displayedTeamIdentifier(forCodeAt: target)
        let trust = trustAssessment(for: target, teamID: teamID)
        return MediaEngineDiagnostic(
            name: name,
            path: path,
            exists: exists,
            executableOrReadable: accessible,
            trusted: trust.trusted,
            teamID: teamID,
            detail: trust.detail
        )
    }

    private static func trustAssessment(for target: URL, teamID: String?) -> (trusted: Bool, detail: String) {
        guard AppSecurityPolicy.externalMediaEnginesAvailable else {
            return (false, "This app build does not allow external engines.")
        }
        guard PrivacySettings.externalMediaEnginesEnabled() else {
            return (false, "External engines are installed but disabled. Enable them from the Playback menu.")
        }
        if AppSecurityPolicy.allowsUnverifiedExternalEnginesForDevelopment {
            return (true, "Debug-only unverified engine override is enabled.")
        }

        let trustedTeamIDs = AppSecurityPolicy.trustedExternalEngineTeamIDs
        guard !trustedTeamIDs.isEmpty else {
            return (false, "No trusted external engine Team IDs are configured for this build.")
        }

        guard let teamID else {
            return (false, "Code signature validation failed before a Team ID could be read.")
        }
        guard trustedTeamIDs.contains(teamID) else {
            return (false, "Engine Team ID \(teamID) is not in the configured trusted list: \(trustedTeamIDs.sorted().joined(separator: ", ")).")
        }

        do {
            try CodeSignatureVerifier.verifyStrictCodeSignature(forCodeAt: target)
            try CodeSignatureVerifier.assessGatekeeperExecute(for: target)
            return (true, "Code signature, Gatekeeper, user opt-in, and configured Team ID checks passed.")
        } catch {
            return (false, "Code signature or Gatekeeper validation failed: \(error.localizedDescription)")
        }
    }
}
