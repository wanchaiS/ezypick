import Foundation

/// Holds on to one search so a single trip through the app pays for one lookup.
///
/// A trip now reads the same set of restaurants at least twice: once to tell the diner what is
/// around them, once to fence it down, and again every time they say none of these and the
/// shortlist is rebuilt. Against a live places service each of those is a billed request, and worse
/// than the cost is the inconsistency: a second call can return a different twenty venues, so the
/// summary a diner just read would not describe the shortlist they end up with.
///
/// - Important: Deliberately not a general-purpose cache. It has no expiry and no invalidation
///   because it is meant to live exactly as long as one decision does. Anything longer would need
///   to answer when a restaurant's opening hours go stale, and the answer to that is to make a new
///   one rather than to teach this one about time.
actor OneShotRestaurantCache: RestaurantRepository {
    private let source: any RestaurantRepository
    private var remembered: [Restaurant]?

    init(_ source: any RestaurantRepository) {
        self.source = source
    }

    func nearbyRestaurants() async throws -> [Restaurant] {
        if let remembered { return remembered }
        let found = try await source.nearbyRestaurants()
        remembered = found
        return found
    }

    /// Forgets the search, so the next read looks again.
    func startAgain() {
        remembered = nil
    }
}
