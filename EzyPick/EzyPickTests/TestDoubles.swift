import Foundation
@testable import EzyPick

/// A preferences store that keeps whatever it is given, for tests that care that saving happened.
final class InMemoryPreferencesStore: DiningPreferencesStore, @unchecked Sendable {
    private(set) var saved: DiningPreferences?
    func load() -> DiningPreferences? { saved }
    func save(_ preferences: DiningPreferences) throws { saved = preferences }
}

/// A question that keeps whichever of these candidates carries the attribute.
///
/// A question carries the restaurants a yes keeps, not an attribute, so the translation happens
/// here: naming an attribute is the cheapest readable way for a test to say "these two, not those".
func question(about attribute: RestaurantAttribute,
              among candidates: [CandidateRestaurant],
              text: String? = nil) -> LunchQuestion {
    LunchQuestion(topic: attribute.rawValue,
                  text: text ?? TemplateQuestionGenerator.wording(for: attribute),
                  keptByYes: Set(candidates.filter { $0.has(attribute) }.map(\.id)))
}

// MARK: - Builders

func restaurant(_ name: String,
                cuisine: Cuisine = .modernAustralian,
                price: Int = 20,
                walk: Int = 5,
                opens: String = "11:00",
                closes: String = "15:00",
                attributes: Set<RestaurantAttribute> = [.quickService]) -> Restaurant {
    Restaurant(id: .init(name.lowercased().replacingOccurrences(of: " ", with: "-")),
               name: name, cuisine: cuisine, pricePerHead: price, rating: 4.2, ratingCount: 100,
               walkingMinutes: walk, opensAt: TimeOfDay(opens)!, closesAt: TimeOfDay(closes)!,
               attributes: attributes,
               editorialSummary: "\(name) serves lunch.", reviewSnippets: ["Good lunch."])
}

func preferences(budget: Int = 25, walk: Int = 10) -> DiningPreferences {
    DiningPreferences(budgetPerHead: budget, willingToWalkMinutes: walk)
}

/// The time every test judges "open" against.
///
/// Stated rather than read from the clock: a test that read the clock would pass all morning and
/// fail after three.
let lunchtime = TimeOfDay("12:30")!

func candidates(_ restaurants: [Restaurant]) -> [CandidateRestaurant] {
    restaurants.map(CandidateRestaurant.init)
}
