import Foundation

/// Somewhere restaurants come from.
///
/// The business rules never learn whether that is a file in the app bundle, a places API or a
/// stub in a test. Today it is a seeded catalogue shaped like Google Places API (New); swapping in
/// live data changes the implementation of this protocol and nothing above it.
protocol RestaurantRepository: Sendable {
    /// Every restaurant the app could consider, before any of the diner's limits are applied.
    func nearbyRestaurants() async throws -> [Restaurant]
}

/// Somewhere the diner's saved preferences live between lunches.
protocol DiningPreferencesStore: Sendable {
    func load() -> DiningPreferences?
    func save(_ preferences: DiningPreferences) throws
}
