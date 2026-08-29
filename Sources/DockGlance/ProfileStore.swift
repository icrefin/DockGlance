import Foundation
import Observation

/// Named settings profiles. A profile is a snapshot of the appearance and
/// layout settings; saving captures the current settings, applying a profile
/// restores them. Profiles are persisted as JSON in `UserDefaults`.
@MainActor
@Observable
final class ProfileStore {
    private static let profilesKey = "savedProfiles"
    private static let activeKey = "activeProfileName"

    private(set) var profiles: [Profile] = []
    /// The profile that was last applied or saved, shown in the picker.
    private(set) var activeProfileName: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let stored = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = stored
        }
        activeProfileName = UserDefaults.standard.string(forKey: Self.activeKey)
    }

    var activeProfile: Profile? {
        activeProfileName.flatMap(profile(named:))
    }

    func profile(named name: String) -> Profile? {
        profiles.first { $0.name == name }
    }

    /// Captures the current settings into a profile named `name`. An
    /// existing profile with the same name is overwritten. The saved profile
    /// becomes the active one.
    @discardableResult
    func saveCurrentAs(
        _ name: String, settings: AppSettings, cards: CardSettings
    ) -> Profile {
        let profile = Profile(
            name: name,
            appearance: settings.snapshot(),
            layout: cards.snapshot(),
            displayMode: DisplayMode.current()
        )
        if let index = profiles.firstIndex(where: { $0.name == name }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        activeProfileName = name
        persist()
        return profile
    }

    /// Restores `profile` into the active settings.
    func apply(_ profile: Profile, settings: AppSettings, cards: CardSettings) {
        settings.restore(profile.appearance)
        cards.restore(profile.layout)
        activeProfileName = profile.name
        persist()
    }

    /// Unlinks the active profile without touching the current settings.
    func clearActive() {
        activeProfileName = nil
        persist()
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.name == profile.name }
        if activeProfileName == profile.name {
            activeProfileName = nil
        }
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
        defaults.set(activeProfileName, forKey: Self.activeKey)
    }
}