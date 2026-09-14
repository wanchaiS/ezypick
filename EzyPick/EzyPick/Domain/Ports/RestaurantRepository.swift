import Foundation

/// Somewhere restaurants come from.
///
/// - Note: The business rules never learn whether that is a bundled file, a places API or a test
///   stub. Swapping in live data changes this implementation and nothing above it.
protocol RestaurantRepository: Sendable {
    /// Every restaurant the app could consider, before any of the diner's limits are applied.
    func nearbyRestaurants() async throws -> [Restaurant]
}

/// Somewhere the diner's saved preferences live between lunches.
protocol DiningPreferencesStore: Sendable {
    func load() -> DiningPreferences?
    func save(_ preferences: DiningPreferences) throws
}
