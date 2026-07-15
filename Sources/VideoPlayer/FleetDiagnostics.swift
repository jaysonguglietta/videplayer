import Foundation

struct FleetDiagnosticDocument: Codable, Equatable {
    let generatedAt: Date
    let appVersion: String
    let operatingSystem: String
    let selectedMediaTitle: String?
    let selectedMediaLocation: String?
    let playlistCount: Int
    let currentEngine: String
    let externalEngineBuild: Bool
    let externalEnginesEnabled: Bool
    let trustedExternalEngineTeamIDs: [String]
    let vlcTrustedRuntimeAvailable: Bool
    let mpvTrustedRuntimeAvailable: Bool
    let policy: FleetPolicySnapshot
    let licenseStatus: String
    let releaseReadiness: [FleetReadinessItem]
    let library: FleetLibrarySummary
    let recovery: FleetRecoverySummary
    let subtitlePreferences: SubtitlePreferences
}

struct FleetPolicySnapshot: Codable, Equatable {
    let organizationName: String?
    let hasManagedRestrictions: Bool
    let summaryLines: [String]

    init(policy: EnterprisePolicySnapshot) {
        let name = policy.organizationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationName = name?.isEmpty == false ? name : nil
        hasManagedRestrictions = policy.hasManagedRestrictions
        summaryLines = policy.summaryLines
    }
}

struct FleetReadinessItem: Codable, Equatable {
    let title: String
    let status: String
    let detail: String
}

struct FleetLibrarySummary: Codable, Equatable {
    let totalItems: Int
    let localItems: Int
    let streamItems: Int
    let missingLocalFiles: Int
    let favorites: Int
    let watched: Int
    let duplicateOrVersionGroups: Int
    let tvEpisodeGroups: Int
}

struct FleetRecoverySummary: Codable, Equatable {
    let previousSessionEndedCleanly: Bool
    let lastPlaybackTitle: String?
    let lastPlaybackURL: String?
    let lastHangWarningAt: Date?
}

enum FleetDiagnostics {
    static func document(
        selectedItem: MediaItem?,
        playlist: [MediaItem],
        currentEngine: String,
        vlcAvailable: Bool,
        mpvAvailable: Bool,
        policy: EnterprisePolicySnapshot,
        licenseStatus: EnterpriseLicenseStatus,
        releaseReadiness: ReleaseReadinessReport,
        libraryReport: LibraryCatalogReport,
        recoveryState: PlaybackRecoveryState,
        subtitlePreferences: SubtitlePreferences,
        now: Date = Date()
    ) -> FleetDiagnosticDocument {
        FleetDiagnosticDocument(
            generatedAt: now,
            appVersion: OpenSourceNotices.appVersion,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            selectedMediaTitle: selectedItem?.title,
            selectedMediaLocation: selectedItem.map { MediaPersistence.storageString(for: $0.url) },
            playlistCount: playlist.count,
            currentEngine: currentEngine,
            externalEngineBuild: AppSecurityPolicy.externalMediaEnginesAvailable,
            externalEnginesEnabled: PrivacySettings.externalMediaEnginesEnabled(),
            trustedExternalEngineTeamIDs: AppSecurityPolicy.trustedExternalEngineTeamIDs.sorted(),
            vlcTrustedRuntimeAvailable: vlcAvailable,
            mpvTrustedRuntimeAvailable: mpvAvailable,
            policy: FleetPolicySnapshot(policy: policy),
            licenseStatus: licenseStatus.title,
            releaseReadiness: releaseReadiness.checks.map {
                FleetReadinessItem(title: $0.title, status: $0.status.rawValue, detail: $0.detail)
            },
            library: FleetLibrarySummary(
                totalItems: libraryReport.totalItems,
                localItems: libraryReport.localItems,
                streamItems: libraryReport.streamItems,
                missingLocalFiles: libraryReport.missingLocalFiles,
                favorites: libraryReport.favorites,
                watched: libraryReport.watched,
                duplicateOrVersionGroups: libraryReport.duplicateOrVersionGroups,
                tvEpisodeGroups: libraryReport.tvEpisodeGroups
            ),
            recovery: FleetRecoverySummary(
                previousSessionEndedCleanly: recoveryState.previousSessionEndedCleanly,
                lastPlaybackTitle: recoveryState.lastPlaybackTitle,
                lastPlaybackURL: recoveryState.lastPlaybackURL,
                lastHangWarningAt: recoveryState.lastHangWarningAt
            ),
            subtitlePreferences: subtitlePreferences
        )
    }

    static func jsonData(from document: FleetDiagnosticDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }
}
