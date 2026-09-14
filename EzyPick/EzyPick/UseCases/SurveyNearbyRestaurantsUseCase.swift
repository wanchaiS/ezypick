import Foundation

/// Looks up what is around the diner and describes it. It answers "what is even out here?",
/// which comes before "where could I eat?".
///
/// - Important: No business rule lives here. Nothing is excluded, so nothing can be wrongly
///   excluded, and a diner reading this screen is reading the search rather than the filter.
struct SurveyNearbyRestaurantsUseCase {
    /// - Throws: `SurveyNearbyRestaurantsError.nothingNearby` when the search came back empty.
    func execute(from found: [Restaurant], at origin: Coordinate) throws -> NearbySurvey {
        guard !found.isEmpty else { throw SurveyNearbyRestaurantsError.nothingNearby }

        return NearbySurvey(
            origin: origin,
            count: found.count,
            nearestWalkMinutes: found.map(\.walkingMinutes).min() ?? 0,
            typicalPerHead: Self.typicalPrice(of: found),
            commonCuisines: Self.mostCommonCuisines(in: found),
            examples: Self.closest(3, of: found)
        )
    }

    /// The nearest few by name, closest first.
    static func closest(_ many: Int, of restaurants: [Restaurant]) -> [String] {
        restaurants
            .sorted { ($0.walkingMinutes, $0.name) < ($1.walkingMinutes, $1.name) }
            .prefix(many)
            .map(\.name)
    }

    /// What the middle restaurant costs.
    ///
    /// - Note: Median, not mean, so one steakhouse among sandwich shops cannot drag the figure
    ///   somewhere no real venue sits. Even counts take the lower of the two middles.
    static func typicalPrice(of restaurants: [Restaurant]) -> Int {
        let prices = restaurants.map(\.pricePerHead).sorted()
        guard !prices.isEmpty else { return 0 }
        return prices[(prices.count - 1) / 2]
    }

    /// The three kinds of food that come up most often.
    ///
    /// - Note: Ties break by name so the same search always reads the same way.
    static func mostCommonCuisines(in restaurants: [Restaurant]) -> [Cuisine] {
        var counts: [Cuisine: Int] = [:]
        for restaurant in restaurants { counts[restaurant.cuisine, default: 0] += 1 }

        return counts
            .sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
            .prefix(3)
            .map(\.key)
    }
}

/// What the diner is told when there is nothing to look at.
enum SurveyNearbyRestaurantsError: LocalizedError, Equatable {
    /// The search worked and came back empty.
    case nothingNearby

    var errorDescription: String? {
        "There are no restaurants around you right now."
    }

    var recoverySuggestion: String? {
        "Try again from somewhere closer to shops and cafes."
    }
}
