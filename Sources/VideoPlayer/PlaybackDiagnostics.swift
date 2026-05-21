import Foundation

struct PlaybackDiagnosticInput: Equatable {
    let item: MediaItem?
    let nativeAssessment: NativePlaybackAssessment?
    let externalEnginesAvailable: Bool
    let externalEnginesEnabled: Bool
    let vlcAvailable: Bool
    let mpvAvailable: Bool
    let policy: EnterprisePolicySnapshot
    let licenseStatus: EnterpriseLicenseStatus
    let resolvedStreamAddresses: Set<String>
}

struct PlaybackDiagnosticReport: Equatable {
    let title: String
    let lines: [String]

    var text: String {
        ([title, String(repeating: "=", count: title.count)] + lines).joined(separator: "\n")
    }
}

enum PlaybackDiagnostics {
    static func report(input: PlaybackDiagnosticInput) -> PlaybackDiagnosticReport {
        var lines: [String] = [
            "App Version: \(OpenSourceNotices.appVersion)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "External engine build: \(input.externalEnginesAvailable ? "Available" : "Unavailable")",
            "External engines enabled: \(input.externalEnginesEnabled ? "Yes" : "No")",
            "VLC/libVLC trusted runtime available: \(input.vlcAvailable ? "Yes" : "No")",
            "mpv trusted runtime available: \(input.mpvAvailable ? "Yes" : "No")",
            "Enterprise license: \(input.licenseStatus.title)"
        ]

        if input.policy.hasManagedRestrictions {
            lines.append("")
            lines.append("Managed Policy")
            lines.append(contentsOf: input.policy.summaryLines.map { "- \($0)" })
        }

        guard let item = input.item else {
            lines.append("")
            lines.append("No media item is selected. Select a playlist row or open a file, then run Playback Diagnostics again.")
            return PlaybackDiagnosticReport(title: "Playback Diagnostics", lines: lines)
        }

        lines.append("")
        lines.append("Selected Media")
        lines.append("- Title: \(item.title)")
        lines.append("- Kind: \(item.isNetworkStream ? "Network stream" : item.fileExtension.uppercased())")
        lines.append("- Location: \(MediaPersistence.storageString(for: item.url))")

        if !input.resolvedStreamAddresses.isEmpty {
            lines.append("- Last validated DNS addresses: \(input.resolvedStreamAddresses.sorted().joined(separator: ", "))")
        }

        if let nativeAssessment = input.nativeAssessment {
            lines.append("")
            lines.append("Native Playback Assessment")
            lines.append("- Route: \(routeTitle(nativeAssessment.routing))")
            lines.append("- Reason: \(nativeAssessment.reason ?? "Apple-native playback should be attempted.")")
            lines.append("- Detected video codecs: \(nativeAssessment.detectedVideoCodecs.isEmpty ? "Unknown or not exposed by AVFoundation" : nativeAssessment.detectedVideoCodecs.sorted().joined(separator: ", "))")
        }

        lines.append("")
        lines.append("Recommended Action")
        lines.append(recommendation(for: input))

        return PlaybackDiagnosticReport(title: "Playback Diagnostics", lines: lines)
    }

    static func enterpriseStatusReport(
        policy: EnterprisePolicySnapshot,
        licenseStatus: EnterpriseLicenseStatus
    ) -> String {
        var lines = [
            "Video Player Enterprise Status",
            "==============================",
            "App Version: \(OpenSourceNotices.appVersion)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Expected Developer Team ID: \(AppSecurityPolicy.expectedDeveloperTeamID ?? "Not configured")",
            "External engine build: \(AppSecurityPolicy.externalMediaEnginesAvailable ? "Available" : "Unavailable")",
            "Trusted external engine Team IDs: \(AppSecurityPolicy.trustedExternalEngineTeamIDs.isEmpty ? "None configured" : AppSecurityPolicy.trustedExternalEngineTeamIDs.sorted().joined(separator: ", "))",
            "Update manifest asset: \(UpdateSecurity.updateManifestAssetName)",
            "",
            "License",
            "-------",
            licenseStatus.reportText,
            "",
            "Managed Policy",
            "--------------"
        ]

        lines.append(contentsOf: policy.summaryLines)
        return lines.joined(separator: "\n")
    }

    private static func routeTitle(_ routing: NativePlaybackAssessment.Routing) -> String {
        switch routing {
        case .native:
            return "Apple-native AVFoundation"
        case .preferExternal:
            return "Prefer trusted VLC/mpv when available"
        case .requiresExternal:
            return "Requires trusted VLC/mpv"
        }
    }

    private static func recommendation(for input: PlaybackDiagnosticInput) -> String {
        if input.policy.requireLicense, !input.licenseStatus.isOperationallyUsable {
            return "Install a valid enterprise license. Current managed policy requires licensing before deployment is considered compliant."
        }

        if input.policy.forceDisableExternalMediaEngines {
            return "External media engines are disabled by managed policy. Use Apple-native formats such as MP4/MOV with supported codecs, or change the managed policy."
        }

        if input.nativeAssessment?.requiresExternalEngine == true {
            if !input.externalEnginesAvailable {
                return "Build the advanced external-engine variant or transcode this media into an Apple-native codec/container."
            }
            if !input.externalEnginesEnabled {
                return "Enable trusted external VLC/mpv engines from Playback, then retry this file."
            }
            if !input.vlcAvailable && !input.mpvAvailable {
                return "Install or repair a trusted VLC/libVLC or mpv copy that passes code-signature, Team ID, and Gatekeeper validation."
            }
            return "Retry playback with the trusted external engine path. If it still fails, export a support bundle and include this diagnostic report."
        }

        if input.item?.isNetworkStream == true, input.policy.forceBlockPrivateNetworkStreams {
            return "Private/local stream targets are blocked by policy. Use a public stream host or change the managed policy for trusted internal networks."
        }

        return "The selected media should play with the current configuration. If playback hangs or shows audio-only behavior, export a support bundle after reproducing it."
    }
}
