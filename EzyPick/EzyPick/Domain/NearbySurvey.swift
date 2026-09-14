import Foundation

/// What is actually around the diner, before any of their limits are applied.
///
/// - Important: Deliberately not filtered. Every figure counts every venue the search returned,
///   including ones the diner's budget or walking limit is about to rule out.
struct NearbySurvey: Equatable, Sendable {
    /// Where the search was run from, carried so the diner can be shown it.
    let origin: Coordinate
    let count: Int
    let nearestWalkMinutes: Int
    /// What a diner would typically spend at the middle of this lot, in whole dollars.
    ///
    /// - Important: The middle, not a range. Every venue is reported as a price *band*, so a
    ///   cheapest-to-dearest range across all of them describes no real restaurant.
    let typicalPerHead: Int
    /// The kinds of food most of them serve, most common first, at most three.
    let commonCuisines: [Cuisine]
    /// A few of them by name, so the diner can recognise where the app is looking.
    let examples: [String]

    init(origin: Coordinate, count: Int, nearestWalkMinutes: Int,
                typicalPerHead: Int, commonCuisines: [Cuisine], examples: [String]) {
        self.origin = origin
        self.count = count
        self.nearestWalkMinutes = nearestWalkMinutes
        self.typicalPerHead = typicalPerHead
        self.commonCuisines = commonCuisines
        self.examples = examples
    }
}
