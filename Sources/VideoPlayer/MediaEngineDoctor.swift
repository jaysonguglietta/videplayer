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
        let teamID = (try? CodeSignatureVerifier.teamIdentifier(forCodeAt: target)) ?? nil
        let trusted = ExternalMediaEngineTrust.isEngineAllowed(at: url)
        return MediaEngineDiagnostic(
            name: name,
            path: path,
            exists: exists,
            executableOrReadable: accessible,
            trusted: trusted,
            teamID: teamID,
            detail: trusted
                ? "Code signature, Gatekeeper, user opt-in, and configured Team ID checks passed."
                : "Trust checks failed or this build/user setting does not allow external engines."
        )
    }
}
