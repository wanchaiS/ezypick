import Foundation
@testable import EzypickCore

/// A catalogue held in memory, so every test states exactly the restaurants it cares about.
struct StubCatalogue: RestaurantRepository {
    let restaurants: [Restaurant]
    func nearbyRestaurants() async throws -> [Restaurant] { restaurants }
}

/// A preferences store that keeps whatever it is given, for tests that care that saving happened.
final class InMemoryPreferencesStore: DiningPreferencesStore, @unchecked Sendable {
    private(set) var saved: DiningPreferences?
    func load() -> DiningPreferences? { saved }
    func save(_ preferences: DiningPreferences) throws { saved = preferences }
}

/// A generator that always fails, standing in for no network, no API key, or a refused request.
struct FailingQuestionGenerator: QuestionGenerator {
    struct Unavailable: Error {}
    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion] {
        throw Unavailable()
    }
}

/// A generator that returns whatever a test tells it to, including deliberately useless questions.
struct ScriptedQuestionGenerator: QuestionGenerator {
    let scripted: [LunchQuestion]
    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion] { scripted }
}

// MARK: - Builders

func restaurant(_ name: String,
                cuisine: Cuisine = .modernAustralian,
                price: Int = 20,
                walk: Int = 5,
                opens: String = "11:00",
                closes: String = "15:00",
                dietary: Set<DietaryConstraint> = [],
                provenance: DietaryProvenance = .restaurantReported,
                attributes: Set<RestaurantAttribute> = [.quickService]) -> Restaurant {
    Restaurant(id: .init(name.lowercased().replacingOccurrences(of: " ", with: "-")),
               name: name, cuisine: cuisine, pricePerHead: price, rating: 4.2, ratingCount: 100,
               walkingMinutes: walk, opensAt: TimeOfDay(opens)!, closesAt: TimeOfDay(closes)!,
               dietary: dietary, dietaryProvenance: provenance, attributes: attributes,
               editorialSummary: "\(name) serves lunch.", reviewSnippets: ["Good lunch."])
}

func preferences(dietary: Set<DietaryConstraint> = [],
                 avoiding: Set<Cuisine> = [],
                 budget: Int = 25,
                 walk: Int = 10,
                 mealTime: String = "12:30") -> DiningPreferences {
    DiningPreferences(dietaryRequirements: dietary, avoidedCuisines: avoiding,
                      budgetPerHead: budget, willingToWalkMinutes: walk,
                      usualMealTime: TimeOfDay(mealTime)!)
}

func candidates(_ restaurants: [Restaurant]) -> [CandidateRestaurant] {
    restaurants.map(CandidateRestaurant.init)
}
