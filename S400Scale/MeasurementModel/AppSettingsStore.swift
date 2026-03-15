import Foundation

struct AppSettingsStore {
    private let defaults: UserDefaults
    private let profileKey = "s400.user-profile"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadProfile() -> UserProfile {
        guard
            let data = defaults.data(forKey: profileKey),
            let profile = try? JSONDecoder().decode(UserProfile.self, from: data)
        else {
            return UserProfile()
        }
        return profile.applyingDeviceDefaults()
    }

    func saveProfile(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }
        defaults.set(data, forKey: profileKey)
    }
}
