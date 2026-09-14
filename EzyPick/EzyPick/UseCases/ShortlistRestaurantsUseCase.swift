import Foundation
import os

/// Works out which restaurants the diner could actually eat at right now.
///
/// This is the app doing the legwork a person would otherwise do themselves: prices against a
/// budget, how far each place is, and whether it is actually open. None of it is asked about,
/// because all of it is already known.
///
/// A fourth limit used to come first and was the app's hardest rule: dietary requirements, vetoed
/// absolutely. It was removed once live data showed what it did. Halal is a venue category almost
/// nobody publishes and vegetarian is a flag that is asserted or absent but never denied, so
/// ticking either emptied the list wherever the diner stood. A veto over data that does not exist
/// does not protect anyone; it just refuses everything, and it taught the diner to turn it off.
///
/// - Important: Business rules enforced here, in this order — budget per head, walking distance,
///   open at the time given, and anything already turned down in this session.
struct ShortlistRestaurantsUseCase {
    private let restaurants: RestaurantRepository

    init(restaurants: RestaurantRepository) { self.restaurants = restaurants }

    /// - Parameters:
    ///   - preferences: the diner's saved limits.
    ///   - now: the time to judge "open" against. Passed in rather than read here so a test never
    ///     depends on the hour it runs at.
    ///   - declined: restaurants they have already turned down this session, which are never re-offered.
    ///   - allowingOverBudget: set only when the diner has deliberately lifted their own budget.
    /// - Throws: `ShortlistRestaurantsError.nothingWithinReach` carrying the tally, so the message
    ///   can name the limit that did the damage.
    func execute(for preferences: DiningPreferences,
                        at now: TimeOfDay,
                        declining declined: Set<Restaurant.ID> = [],
                        allowingOverBudget: Bool = false) async throws -> Shortlist {
        let all = try await restaurants.nearbyRestaurants()

        var tally = ExclusionTally()
        tally.consideredCount = all.count
        var survivors: [CandidateRestaurant] = []

        for restaurant in all {
            if !allowingOverBudget && restaurant.pricePerHead > preferences.budgetPerHead { tally.byBudget += 1; continue }
            if restaurant.walkingMinutes > preferences.willingToWalkMinutes { tally.byDistance += 1; continue }
            if !restaurant.isOpen(at: now) { tally.byOpeningHours += 1; continue }
            if declined.contains(restaurant.id) { tally.byPreviousDecline += 1; continue }
            survivors.append(CandidateRestaurant(restaurant))
        }

        // The fence is silent to the diner by design, which also makes it invisible to whoever is
        // trying to work out why a shortlist came back the size it did.
        Diagnostics.fence.info("""
            \(tally.consideredCount, privacy: .public) considered, \
            \(survivors.count, privacy: .public) fit \
            (budget \(tally.byBudget, privacy: .public), \
            walk \(tally.byDistance, privacy: .public), shut \(tally.byOpeningHours, privacy: .public), \
            declined \(tally.byPreviousDecline, privacy: .public))
            """)

        guard !survivors.isEmpty else { throw ShortlistRestaurantsError.nothingWithinReach(tally) }
        return Shortlist(candidates: survivors, excluded: tally)
    }
}

/// The restaurants that survived every limit, and a record of what the limits cost.
struct Shortlist: Equatable, Sendable {
    let candidates: [CandidateRestaurant]
    let excluded: ExclusionTally

    init(candidates: [CandidateRestaurant], excluded: ExclusionTally) {
        self.candidates = candidates
        self.excluded = excluded
    }
}

/// What the diner is told when the app cannot find anywhere for them to eat.
enum ShortlistRestaurantsError: LocalizedError, Equatable {
    /// Nothing survived the diner's own limits. Carries the tally so the message can say which one.
    case nothingWithinReach(ExclusionTally)

    var errorDescription: String? {
        guard case .nothingWithinReach(let tally) = self else { return nil }
        switch tally.dominantCause {
        case .budget:
            return "Everywhere nearby that fits is over your budget today."
        case .distance:
            return "The places that fit are all further than you said you'd walk."
        case .openingHours:
            return "The places that fit aren't open right now."
        case .previouslyDeclined:
            return "You've turned down everything nearby that fits today."
        case nil:
            return "There are no restaurants to search right now."
        }
    }

    var recoverySuggestion: String? {
        guard case .nothingWithinReach(let tally) = self else { return nil }
        switch tally.dominantCause {
        case .budget: return "Raise your budget for today, or walk a little further."
        case .distance: return "Widen your walk to twenty minutes and try again."
        case .openingHours: return "Try again a bit later, or widen how far you'll walk."
        case .previouslyDeclined: return "Start again to see the places you turned down."
        case nil: return "Check your connection and try again."
        }
    }
}
