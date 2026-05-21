import Foundation

struct ReadinessCheck: Equatable {
    enum Status: String {
        case pass = "PASS"
        case warn = "WARN"
        case fail = "FAIL"
    }

    let title: String
    let status: Status
    let detail: String
}

struct ReleaseReadinessReport: Equatable {
    let checks: [ReadinessCheck]

    var text: String {
        var lines = [
            "Release Readiness",
            "=================",
            "App Version: \(OpenSourceNotices.appVersion)",
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")",
            ""
        ]

        lines.append(contentsOf: checks.map {
            "[\($0.status.rawValue)] \($0.title): \($0.detail)"
        })
        return lines.joined(separator: "\n")
    }
}

enum ReleaseReadiness {
    static func report(policy: EnterprisePolicySnapshot = EnterprisePolicy.snapshot()) -> ReleaseReadinessReport {
        var checks: [ReadinessCheck] = []

        checks.append(check(
            title: "Developer ID Team ID",
            condition: AppSecurityPolicy.expectedDeveloperTeamID != nil,
            failureStatus: .fail,
            passDetail: "Expected Developer ID Team ID is configured.",
            failDetail: "Set EXPECTED_DEVELOPER_TEAM_ID before packaging production builds."
        ))

        checks.append(check(
            title: "External Engine Build Mode",
            condition: !AppSecurityPolicy.externalMediaEnginesAvailable || !AppSecurityPolicy.trustedExternalEngineTeamIDs.isEmpty,
            failureStatus: .fail,
            passDetail: AppSecurityPolicy.externalMediaEnginesAvailable
                ? "Advanced build has trusted Team IDs configured."
                : "Default build is native-only and does not load external engines.",
            failDetail: "Advanced builds must configure TRUSTED_EXTERNAL_ENGINE_TEAM_IDS."
        ))

        checks.append(check(
            title: "Update Manifest",
            condition: !UpdateSecurity.updateManifestAssetName.isEmpty,
            failureStatus: .fail,
            passDetail: "Signed update manifest asset name is configured.",
            failDetail: "Update manifest asset name is missing."
        ))

        checks.append(check(
            title: "Enterprise License Public Key",
            condition: EnterpriseLicenseManager.licensePublicKeyBase64 != nil || !policy.requireLicense,
            failureStatus: .warn,
            passDetail: EnterpriseLicenseManager.licensePublicKeyBase64 == nil
                ? "License enforcement is not required by policy."
                : "Offline license public key is configured.",
            failDetail: "Policy requires licensing, but this build has no VPEnterpriseLicensePublicKey."
        ))

        checks.append(check(
            title: "Support Bundle Redaction",
            condition: policy.redactSupportBundlePaths,
            failureStatus: .warn,
            passDetail: "Support bundles redact paths and URL secrets by default.",
            failDetail: "Support bundle redaction is disabled by policy."
        ))

        checks.append(check(
            title: "Update Channel",
            condition: policy.updateChannel == "github" || policy.updateChannel == "sparkle" || policy.updateChannel == "mdm",
            failureStatus: .warn,
            passDetail: updateChannelDetail(policy),
            failDetail: "Unknown update channel '\(policy.updateChannel)'. Use github, sparkle, or mdm."
        ))

        checks.append(check(
            title: "Sparkle Readiness",
            condition: policy.updateChannel != "sparkle" || policy.sparkleAppcastURL != nil,
            failureStatus: .warn,
            passDetail: policy.updateChannel == "sparkle"
                ? "Sparkle appcast URL is configured for a future Sparkle framework migration."
                : "Sparkle is not selected for this build.",
            failDetail: "Sparkle update channel requires EnterpriseSparkleAppcastURL."
        ))

        checks.append(codeSignatureCheck())
        return ReleaseReadinessReport(checks: checks)
    }

    private static func check(
        title: String,
        condition: Bool,
        failureStatus: ReadinessCheck.Status,
        passDetail: String,
        failDetail: String
    ) -> ReadinessCheck {
        ReadinessCheck(
            title: title,
            status: condition ? .pass : failureStatus,
            detail: condition ? passDetail : failDetail
        )
    }

    private static func updateChannelDetail(_ policy: EnterprisePolicySnapshot) -> String {
        switch policy.updateChannel {
        case "github":
            return "Using the built-in signed GitHub release updater."
        case "sparkle":
            return "Sparkle-ready channel selected. Full Sparkle runtime integration still requires bundling Sparkle 2 and its sandbox services."
        case "mdm":
            return "Updates are expected to be deployed through MDM."
        default:
            return "Unknown update channel."
        }
    }

    private static func codeSignatureCheck() -> ReadinessCheck {
        let bundleURL = Bundle.main.bundleURL
        do {
            try CodeSignatureVerifier.verifyStrictCodeSignature(forCodeAt: bundleURL)
            return ReadinessCheck(
                title: "Code Signature",
                status: .pass,
                detail: "Current app bundle passes strict code-signature verification."
            )
        } catch {
            return ReadinessCheck(
                title: "Code Signature",
                status: .warn,
                detail: "Current app bundle does not pass production signature verification here: \(error.localizedDescription)"
            )
        }
    }
}
