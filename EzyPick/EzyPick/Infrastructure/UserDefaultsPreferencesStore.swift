import Foundation

/// Keeps the diner's preferences between launches.
///
/// `UserDefaults` rather than a database: a single small record, written rarely, read once per
/// lunch, with nothing to query or relate. Week 6's storage guidance puts exactly this shape here.
///
/// `UserDefaults` is documented as thread-safe but is not marked `Sendable`, so the conformance is
/// stated explicitly rather than designed around.
struct UserDefaultsPreferencesStore: DiningPreferencesStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "ezypick.diningPreferences"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> DiningPreferences? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DiningPreferences.self, from: data)
    }

    func save(_ preferences: DiningPreferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}
