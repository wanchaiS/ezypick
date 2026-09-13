import Foundation

/// Works out which restaurants the diner could actually eat at today.
///
/// This is the app doing the legwork a person would otherwise do themselves: checking menus for
/// dietary options, prices against a budget, opening hours against the clock, and how far each
/// place is. None of it is asked about, because all of it is already known.
///
/// - Important: Business rules enforced here, in this order — dietary requirements (absolute),
///   cuisines the diner avoids, budget per head, walking distance, open at the meal time, and
///   anything already turned down in this session.
public struct ShortlistRestaurantsUseCase {
    private let restaurants: RestaurantRepository

    public init(restaurants: RestaurantRepository) { self.restaurants = restaurants }

    /// - Parameters:
    ///   - preferences: the diner's saved limits.
    ///   - mealTime: when they intend to eat; defaults to their usual time.
    ///   - declined: restaurants they have already turned down this session, which are never re-offered.
    ///   - allowingOverBudget: set only when the diner has deliberately lifted their own budget.
    /// - Throws: `ShortlistRestaurantsError.nothingWithinReach` carrying the tally, so the message
    ///   can name the limit that did the damage.
    public func execute(for preferences: DiningPreferences,
                        at mealTime: TimeOfDay? = nil,
                        declining declined: Set<Restaurant.ID> = [],
                        allowingOverBudget: Bool = false) async throws -> Shortlist {
        let time = mealTime ?? preferences.usualMealTime
        let all = try await restaurants.nearbyRestaurants()

        var tally = ExclusionTally()
        tally.consideredCount = all.count
        var survivors: [CandidateRestaurant] = []

        for restaurant in all {
            if !restaurant.canCater(for: preferences.dietaryRequirements) { tally.byDietary += 1; continue }
            if preferences.avoidedCuisines.contains(restaurant.cuisine) { tally.byAvoidedCuisine += 1; continue }
            if !allowingOverBudget && restaurant.pricePerHead > preferences.budgetPerHead { tally.byBudget += 1; continue }
            if restaurant.walkingMinutes > preferences.willingToWalkMinutes { tally.byDistance += 1; continue }
            if !restaurant.isOpen(at: time) { tally.byOpeningHours += 1; continue }
            if declined.contains(restaurant.id) { tally.byPreviousDecline += 1; continue }
            survivors.append(CandidateRestaurant(restaurant))
        }

        guard !survivors.isEmpty else { throw ShortlistRestaurantsError.nothingWithinReach(tally) }
        return Shortlist(candidates: survivors, excluded: tally)
    }
}

/// The restaurants that survived every limit, and a record of what the limits cost.
public struct Shortlist: Equatable, Sendable {
    public let candidates: [CandidateRestaurant]
    public let excluded: ExclusionTally

    public init(candidates: [CandidateRestaurant], excluded: ExclusionTally) {
        self.candidates = candidates
        self.excluded = excluded
    }
}

/// What the diner is told when the app cannot find anywhere for them to eat.
public enum ShortlistRestaurantsError: LocalizedError, Equatable {
    /// Nothing survived the diner's own limits. Carries the tally so the message can say which one.
    case nothingWithinReach(ExclusionTally)

    public var errorDescription: String? {
        guard case .nothingWithinReach(let tally) = self else { return nil }
        switch tally.dominantCause {
        case .dietary:
            return "Nothing nearby lists the dietary options you need at this time."
        case .budget:
            return "Everywhere nearby that fits is over your budget today."
        case .distance:
            return "The places that fit are all further than you said you'd walk."
        case .openingHours:
            return "The places that fit aren't serving at that time."
        case .avoidedCuisine:
            return "What's left nearby is all food you've asked not to be shown."
        case .previouslyDeclined:
            return "You've turned down everything nearby that fits today."
        case nil:
            return "There are no restaurants to search right now."
        }
    }

    public var recoverySuggestion: String? {
        guard case .nothingWithinReach(let tally) = self else { return nil }
        switch tally.dominantCause {
        case .dietary: return "Try a later time, or widen how far you'll walk."
        case .budget: return "Raise your budget for today, or walk a little further."
        case .distance: return "Widen your walk to twenty minutes and try again."
        case .openingHours: return "Try eating half an hour earlier or later."
        case .avoidedCuisine: return "Put one kind of food back and try again."
        case .previouslyDeclined: return "Start again to see the places you turned down."
        case nil: return "Check your connection and try again."
        }
    }
}
