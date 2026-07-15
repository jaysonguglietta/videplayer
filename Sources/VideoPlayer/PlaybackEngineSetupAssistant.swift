import Foundation

struct PlaybackEngineSetupReport: Equatable {
    let lines: [String]

    var text: String {
        ([
            "Playback Engine Setup Assistant",
            "==============================="
        ] + lines).joined(separator: "\n")
    }
}

enum PlaybackEngineSetupAssistant {
    static func report(doctorReport: MediaEngineDoctorReport = MediaEngineDoctor.report()) -> PlaybackEngineSetupReport {
        let trustedDiagnostics = doctorReport.diagnostics.filter(\.trusted)
        let installedDiagnostics = doctorReport.diagnostics.filter { $0.exists && $0.executableOrReadable }
        let discoveredTeamIDs = Array(Set(installedDiagnostics.compactMap(\.teamID))).sorted()

        var lines: [String] = [
            "Goal: play MKV, WebM, AVI, FLV, HEVC, Dolby Vision, and other non-Apple-native media through a separately installed VLC or mpv runtime.",
            "",
            "Current Build",
            "- External engine build: \(AppSecurityPolicy.externalMediaEnginesAvailable ? "Yes" : "No")",
            "- External engines enabled: \(PrivacySettings.externalMediaEnginesEnabled() ? "Yes" : "No")",
            "- Configured trusted Team IDs: \(AppSecurityPolicy.trustedExternalEngineTeamIDs.isEmpty ? "None" : AppSecurityPolicy.trustedExternalEngineTeamIDs.sorted().joined(separator: ", "))",
            "- Debug unverified override: \(AppSecurityPolicy.allowsUnverifiedExternalEnginesForDevelopment ? "Enabled" : "Disabled")",
            "",
            "Detected Engines"
        ]

        if installedDiagnostics.isEmpty {
            lines.append("- No readable VLC/libVLC or executable mpv candidates were found.")
        } else {
            for diagnostic in installedDiagnostics {
                lines.append("- \(diagnostic.name): \(diagnostic.trusted ? "Trusted" : "Rejected")")
                lines.append("  Path: \(diagnostic.path)")
                lines.append("  Team ID: \(diagnostic.teamID ?? "Unknown")")
                lines.append("  Detail: \(diagnostic.detail)")
            }
        }

        lines.append("")
        lines.append("Recommended Next Step")
        lines.append(recommendation(
            trustedDiagnostics: trustedDiagnostics,
            installedDiagnostics: installedDiagnostics,
            discoveredTeamIDs: discoveredTeamIDs
        ))

        if !discoveredTeamIDs.isEmpty {
            lines.append("")
            lines.append("Advanced Build Command")
            lines.append("DEVELOPMENT_BUILD=1 ENABLE_EXTERNAL_ENGINES=1 TRUSTED_EXTERNAL_ENGINE_TEAM_IDS=\(discoveredTeamIDs.joined(separator: ",")) ./Scripts/build_app.sh")
        }

        lines.append("")
        lines.append("Release Rule")
        lines.append("Do not ship builds that use ALLOW_UNVERIFIED_EXTERNAL_ENGINES. Customer builds must require strict code-signature, Team ID, and Gatekeeper validation.")

        return PlaybackEngineSetupReport(lines: lines)
    }

    private static func recommendation(
        trustedDiagnostics: [MediaEngineDiagnostic],
        installedDiagnostics: [MediaEngineDiagnostic],
        discoveredTeamIDs: [String]
    ) -> String {
        if !trustedDiagnostics.isEmpty {
            return "At least one external engine is trusted. Enable Playback > Enable External VLC/mpv Engines, then retry the file."
        }
        if !AppSecurityPolicy.externalMediaEnginesAvailable {
            return "Build the advanced external-engine variant with ENABLE_EXTERNAL_ENGINES=1. The default app is intentionally native-only."
        }
        if !PrivacySettings.externalMediaEnginesEnabled() {
            return "Enable Playback > Enable External VLC/mpv Engines, then run this assistant again."
        }
        if AppSecurityPolicy.trustedExternalEngineTeamIDs.isEmpty, !discoveredTeamIDs.isEmpty {
            return "Rebuild with TRUSTED_EXTERNAL_ENGINE_TEAM_IDS=\(discoveredTeamIDs.joined(separator: ",")) so the app can trust the installed engine identity."
        }
        if installedDiagnostics.isEmpty {
            return "Install VLC from VideoLAN or install mpv, then run Playback Engine Doctor again."
        }
        return "Repair or reinstall the rejected engine. A Team ID alone is not enough; the installed app/binary must also pass strict Apple code-signature and Gatekeeper checks."
    }
}
