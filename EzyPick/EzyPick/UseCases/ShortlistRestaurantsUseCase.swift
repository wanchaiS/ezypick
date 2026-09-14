import Foundation

/// Works out which restaurants the diner could actually eat at right now.
///
/// This is the app doing the legwork a person would otherwise do themselves: prices against a
/// budget, how far each place is, and whether it is actually open. None of it is asked about,
/// because all of it is already known.
///
/// A fourth limit used to come first and was the app's hardest rule: dietary requirements, vetoed
/// absolutely. Live data removed it by failing three different ways at once. Gluten-free had no
/// field anywhere in the API, so it was never answerable. Halal is a venue category almost nobody
/// publishes, one venue across the inner city, so it returned an empty list. Vegetarian is the
/// subtle one: the flag exists and almost never says no, two venues in fifty-seven, and an absent
/// flag never means no either. Empty, unanswerable, or true of nearly everything. A veto that
/// looks like a safety check and removes two places in fifty-seven protects nobody, so the rule
/// went rather than got hedged.
///
/// - Important: Business rules enforced here, in this order — budget per head, walking distance,
///   open at the time given, and anything already turned down in this session.
struct ShortlistRestaurantsUseCase {
    /// - Parameters:
    ///   - all: everything the search returned, before any limit is applied.
    ///   - preferences: the diner's saved limits.
    ///   - now: the time to judge "open" against. Passed in rather than read here so a test never
    ///     depends on the hour it runs at.
    ///   - declined: restaurants they have already turned down this session, which are never re-offered.
    ///   - allowingOverBudget: set only when the diner has deliberately lifted their own budget.
    /// - Throws: `ShortlistRestaurantsError.nothingWithinReach` carrying the tally, so the message
    ///   can name the limit that did the damage.
    func execute(from all: [Restaurant],
                 for preferences: DiningPreferences,
                 at now: TimeOfDay,
                 declining declined: Set<Restaurant.ID> = [],
                 allowingOverBudget: Bool = false) throws -> Shortlist {
        var tally = ExclusionTally()
        tally.consideredCount = all.count
        var survivors: [CandidateRestaurant] = []

        // Stops at the first limit a venue fails, so the counts are disjoint and the line the diner
        // reads adds up: every excluded venue is counted once, against the limit that cost it.
        for restaurant in all {
            if !allowingOverBudget && restaurant.pricePerHead > preferences.budgetPerHead { tally.byBudget += 1; continue }
            if restaurant.walkingMinutes > preferences.willingToWalkMinutes { tally.byDistance += 1; continue }
            if !restaurant.isOpen(at: now) { tally.byOpeningHours += 1; continue }
            if declined.contains(restaurant.id) { tally.byPreviousDecline += 1; continue }
            survivors.append(CandidateRestaurant(restaurant))
        }

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
