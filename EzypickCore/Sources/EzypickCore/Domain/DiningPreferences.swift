import Foundation

/// What a diner has told the app about how they eat: the things they cannot do, the things they
/// would rather not do, and the practical limits of a working lunch break.
///
/// Declared once and reused for every lunch, which is what lets the app stay quiet day to day.
/// Nothing here is inferred from behaviour — a preference the diner did not state does not exist,
/// because a wrong guess is invisible to them and impossible to correct.
///
/// - Important: Business rules carried here — dietary requirements are absolute;
///   \`budgetPerHead\` excludes anything dearer unless deliberately lifted;
///   \`willingToWalkMinutes\` and \`usualMealTime\` bound what can be suggested at all.
public struct DiningPreferences: Equatable, Codable, Sendable {
    /// What the diner cannot eat. Never traded off.
    public let dietaryRequirements: Set<DietaryConstraint>
    /// What the diner would rather avoid. May be traded off when little else fits.
    public let avoidedCuisines: Set<Cuisine>
    /// The most the diner will spend on one lunch, in whole dollars.
    public let budgetPerHead: Int
    /// How far the diner will walk, one way, in minutes.
    public let willingToWalkMinutes: Int
    /// When the diner usually eats, used to check a restaurant is actually open.
    public let usualMealTime: TimeOfDay

    public init(dietaryRequirements: Set<DietaryConstraint> = [], avoidedCuisines: Set<Cuisine> = [],
                budgetPerHead: Int, willingToWalkMinutes: Int, usualMealTime: TimeOfDay) {
        self.dietaryRequirements = dietaryRequirements
        self.avoidedCuisines = avoidedCuisines
        self.budgetPerHead = budgetPerHead
        self.willingToWalkMinutes = willingToWalkMinutes
        self.usualMealTime = usualMealTime
    }
}

/// A restaurant that has survived every hard limit and is still a real possibility for this lunch.
///
/// Distinct from \`Restaurant\` on purpose: a restaurant is a fact about the world, a candidate is a
/// judgement about this particular lunch, and only candidates are ever narrowed by questions.
public struct CandidateRestaurant: Equatable, Identifiable, Sendable {
    public let restaurant: Restaurant
    public var id: Restaurant.ID { restaurant.id }

    public init(_ restaurant: Restaurant) { self.restaurant = restaurant }

    public func has(_ attribute: RestaurantAttribute) -> Bool {
        restaurant.attributes.contains(attribute)
    }

    /// Why this candidate is worth suggesting, in words the diner can act on.
    public var recommendationReason: String {
        let diet = restaurant.dietary.isEmpty ? nil
            : restaurant.dietary.map(\.spokenName).sorted().joined(separator: " and ") + " options \(restaurant.dietaryProvenance.caveat)"
        let walk = "\(restaurant.walkingMinutes) min walk"
        let price = "about $\(restaurant.pricePerHead) a head"
        return [walk, price, diet].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A count of why restaurants were ruled out, kept so that a failure can name its own cause.
///
/// Without this the app could only say "nothing matched", which tells a hungry person nothing they
/// can act on. With it, the app can say which limit did the damage and what to relax.
public struct ExclusionTally: Equatable, Sendable {
    public var consideredCount = 0
    public var byDietary = 0
    public var byBudget = 0
    public var byDistance = 0
    public var byOpeningHours = 0
    public var byPreviousDecline = 0
    public var byAvoidedCuisine = 0

    public init() {}

    /// The limit responsible for excluding the most restaurants, which is the one worth relaxing first.
    public var dominantCause: Cause? {
        let counts: [(Cause, Int)] = [
            (.dietary, byDietary), (.budget, byBudget), (.distance, byDistance),
            (.openingHours, byOpeningHours), (.avoidedCuisine, byAvoidedCuisine),
            (.previouslyDeclined, byPreviousDecline)
        ]
        guard let top = counts.filter({ $0.1 > 0 }).max(by: { $0.1 < $1.1 }) else { return nil }
        return top.0
    }

    public enum Cause: Equatable, Sendable {
        case dietary, budget, distance, openingHours, avoidedCuisine, previouslyDeclined
    }
}
