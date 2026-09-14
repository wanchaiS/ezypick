import Foundation

/// What a diner has told the app about the practical limits of a working lunch break.
///
/// Declared once and reused for every lunch, which is what lets the app stay quiet day to day.
/// Nothing here is inferred from behaviour — a preference the diner did not state does not exist,
/// because a wrong guess is invisible to them and impossible to correct.
///
/// Two things, and no more. Dietary requirements used to live here and were the app's hardest rule.
/// They went because no data source underwrites them: halal is a venue category almost nobody
/// publishes, vegetarian is a single flag that is asserted or absent but never denied, and in live
/// searches ticking either one returned nothing at all. A filter that always empties the list is
/// not a strict filter, it is a broken one, and a control that cannot change the answer is a tap
/// the diner paid for and got nothing back.
///
/// - Important: Business rules carried here — `budgetPerHead` excludes anything dearer unless the
///   diner deliberately lifts it for today, and `willingToWalkMinutes` bounds what can be suggested
///   at all. When the diner intends to eat is not stored: the app searches against the clock.
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
/// Distinct from `Restaurant` on purpose: a restaurant is a fact about the world, a candidate is a
/// judgement about this particular lunch, and only candidates are ever narrowed by questions.
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

/// A count of why restaurants were ruled out, kept so that a failure can name its own cause.
///
/// Without this the app could only say "nothing matched", which tells a hungry person nothing they
/// can act on. With it, the app can say which limit did the damage and what to relax.
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
