import Foundation

enum UserUpdateChannel: String, CaseIterable, Codable {
    case stable = "Stable"
    case beta = "Beta"
}

enum AppPreferences {
    private enum Key {
        static let updateChannel = "updateChannel"
    }

    static func updateChannel(defaults: UserDefaults = .standard) -> UserUpdateChannel {
        guard let rawValue = defaults.string(forKey: Key.updateChannel),
              let channel = UserUpdateChannel(rawValue: rawValue)
        else {
            return .stable
        }
        return channel
    }

    static func setUpdateChannel(_ channel: UserUpdateChannel, defaults: UserDefaults = .standard) {
        defaults.set(channel.rawValue, forKey: Key.updateChannel)
    }

    static func effectiveUpdateChannel(
        policy: EnterprisePolicySnapshot = EnterprisePolicy.snapshot(),
        defaults: UserDefaults = .standard
    ) -> UserUpdateChannel {
        switch policy.updateChannel {
        case "github-beta", "beta":
            return .beta
        case "github-stable", "stable":
            return .stable
        default:
            return updateChannel(defaults: defaults)
        }
    }
}
