import Foundation

/// What a diner has told the app about the practical limits of a working lunch break, declared
/// once and reused for every lunch.
///
/// - Important: Business rules — `budgetPerHead` excludes anything dearer unless the diner lifts
///   it for today, and `willingToWalkMinutes` bounds what can be suggested at all. Nothing is
///   inferred from behaviour, and when the diner intends to eat is not stored: the app searches
///   against the clock.
struct DiningPreferences: Equatable, Codable, Sendable {
    /// The most the diner will spend on one lunch, in whole dollars.
    let budgetPerHead: Int
    /// How far the diner will walk, one way, in minutes.
    let willingToWalkMinutes: Int

    init(budgetPerHead: Int, willingToWalkMinutes: Int) {
        self.budgetPerHead = budgetPerHead
        self.willingToWalkMinutes = willingToWalkMinutes
    }
}

/// A restaurant that has survived every hard limit and is still a real possibility for this lunch.
///
/// - Note: A `Restaurant` is a fact about the world; a candidate is a judgement about this lunch.
///   Only candidates are narrowed by questions.
struct CandidateRestaurant: Equatable, Identifiable, Sendable {
    let restaurant: Restaurant
    var id: Restaurant.ID { restaurant.id }

    init(_ restaurant: Restaurant) { self.restaurant = restaurant }

    func has(_ attribute: RestaurantAttribute) -> Bool {
        restaurant.attributes.contains(attribute)
    }

    /// Why this candidate is worth suggesting, in words the diner can act on.
    var recommendationReason: String {
        "\(restaurant.walkingMinutes) min walk · about $\(restaurant.pricePerHead) a head"
    }
}

/// A count of why restaurants were ruled out, so a failure can name the limit that did the damage
/// instead of only saying "nothing matched".
struct ExclusionTally: Equatable, Sendable {
    var consideredCount = 0
    var byBudget = 0
    var byDistance = 0
    var byOpeningHours = 0
    var byPreviousDecline = 0

    init() {}

    /// The limit responsible for excluding the most restaurants, which is the one worth relaxing first.
    var dominantCause: Cause? {
        let counts: [(Cause, Int)] = [
            (.budget, byBudget), (.distance, byDistance),
            (.openingHours, byOpeningHours), (.previouslyDeclined, byPreviousDecline)
        ]
        guard let top = counts.filter({ $0.1 > 0 }).max(by: { $0.1 < $1.1 }) else { return nil }
        return top.0
    }

    enum Cause: Equatable, Sendable {
        case budget, distance, openingHours, previouslyDeclined
    }
}
