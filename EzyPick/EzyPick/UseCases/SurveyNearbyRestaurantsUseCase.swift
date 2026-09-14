import Foundation

/// Looks up what is around the diner and describes it, without ruling anything out.
///
/// Separate from `ShortlistRestaurantsUseCase` on purpose. That one answers "where could I eat?"
/// and enforces every limit the diner has set; this one answers the question that comes first,
/// "what is even out here?", and enforces nothing. Keeping them apart is what lets the app show a
/// diner the size of the problem before it starts solving it, which is the difference between an
/// app that asks for trust and one that earns it.
///
/// - Important: No business rule lives here. Nothing is excluded, so nothing can be wrongly
///   excluded, and a diner reading this screen is reading the search rather than the filter.
struct SurveyNearbyRestaurantsUseCase {
    /// - Parameters:
    ///   - found: everything the search returned, unfiltered.
    ///   - origin: where that search ran from, so the screen can say where it looked.
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

    /// The nearest few by name.
    ///
    /// The closest rather than a sample, because the diner is most likely to recognise what is on
    /// their own doorstep, and recognition is the whole job of this list.
    static func closest(_ many: Int, of restaurants: [Restaurant]) -> [String] {
        restaurants
            .sorted { ($0.walkingMinutes, $0.name) < ($1.walkingMinutes, $1.name) }
            .prefix(many)
            .map(\.name)
    }

    /// What the middle restaurant costs.
    ///
    /// The median rather than the mean, because one steakhouse among a street of sandwich shops
    /// drags an average somewhere no actual restaurant sits. The lower of the two middles is taken
    /// when the count is even, so the figure is always a price some real venue charges rather than
    /// a number arrived at by dividing.
    static func typicalPrice(of restaurants: [Restaurant]) -> Int {
        let prices = restaurants.map(\.pricePerHead).sorted()
        guard !prices.isEmpty else { return 0 }
        return prices[(prices.count - 1) / 2]
    }

    /// The three kinds of food that come up most often, which is what a person scanning a street
    /// would notice first.
    ///
    /// Ties are broken by name so the same search always reads the same way. A summary that
    /// reshuffles itself between looks reads as unreliable even when the numbers are identical.
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
