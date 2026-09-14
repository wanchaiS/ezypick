import Foundation

/// A cuisine, as a diner would name it when saying where they want to eat.
enum Cuisine: String, CaseIterable, Codable, Sendable {
    case italian, thai, japanese, vietnamese, chinese, korean, indian, mexican
    case modernAustralian, modernAsian, middleEastern, burgers, salads, sandwiches, sushi, pizza, cafe

    /// How this cuisine is written on screen.
    ///
    /// - Note: Not derived from the raw value, which capitalises to "Modernaustralian".
    var spokenName: String {
        switch self {
        case .italian: "Italian"
        case .thai: "Thai"
        case .japanese: "Japanese"
        case .vietnamese: "Vietnamese"
        case .chinese: "Chinese"
        case .korean: "Korean"
        case .indian: "Indian"
        case .mexican: "Mexican"
        case .modernAustralian: "Modern Australian"
        case .modernAsian: "Modern Asian"
        case .middleEastern: "Middle Eastern"
        case .burgers: "Burgers"
        case .salads: "Salads"
        case .sandwiches: "Sandwiches"
        case .sushi: "Sushi"
        case .pizza: "Pizza"
        case .cafe: "Café"
        }
    }
}

/// A characteristic of a restaurant that a diner could answer yes or no about.
///
/// - Note: A question is only worth asking when the remaining restaurants disagree about one.
enum RestaurantAttribute: String, CaseIterable, Codable, Sendable {
    case quickService, sitDownDining, outdoorSeating, quiet, lively, goodForGroups
    case takeawayAvailable, sharedTables, licensed, counterOrder, bookingsTaken, hearty, light
}

/// A restaurant the app knows about and could suggest for lunch.
///
/// - Note: Shaped after Google Places API (New); every field is something one lookup answered for.
struct Restaurant: Identifiable, Equatable, Codable, Sendable {
    /// A restaurant's identity, typed so it can never be confused with any other identifier.
    struct ID: Hashable, Codable, Sendable {
        let value: String
        init(_ value: String) { self.value = value }
        init(from decoder: Decoder) throws {
            value = try decoder.singleValueContainer().decode(String.self)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer(); try c.encode(value)
        }
    }

    let id: ID
    let name: String
    let cuisine: Cuisine
    /// Typical spend for one diner, in whole dollars.
    let pricePerHead: Int
    let rating: Double
    let ratingCount: Int
    /// Minutes on foot from wherever the diner is standing. Minutes rather than metres: a lunch
    /// break is measured in time.
    let walkingMinutes: Int
    let opensAt: TimeOfDay
    let closesAt: TimeOfDay
    /// Characteristics the data source asserts about this restaurant.
    ///
    /// - Important: Three-valued, flattened to a set. An attribute is asserted or absent, and
    ///   absent never means denied, so treating a missing attribute as false excludes venues that
    ///   were merely not described.
    let attributes: Set<RestaurantAttribute>
    let editorialSummary: String
    /// Short quotes from diners. Unstructured, and therefore the material a language model reads.
    let reviewSnippets: [String]

    init(id: ID, name: String, cuisine: Cuisine, pricePerHead: Int, rating: Double,
                ratingCount: Int, walkingMinutes: Int, opensAt: TimeOfDay, closesAt: TimeOfDay,
                attributes: Set<RestaurantAttribute>, editorialSummary: String, reviewSnippets: [String]) {
        self.id = id; self.name = name; self.cuisine = cuisine; self.pricePerHead = pricePerHead
        self.rating = rating; self.ratingCount = ratingCount; self.walkingMinutes = walkingMinutes
        self.opensAt = opensAt; self.closesAt = closesAt; self.attributes = attributes
        self.editorialSummary = editorialSummary; self.reviewSnippets = reviewSnippets
    }

    /// Whether the restaurant is serving at a given time.
    ///
    /// - Important: Business rule — a restaurant shut when the diner wants to eat is not a
    ///   candidate. Judged half-open: open at `opensAt`, already shut at `closesAt`.
    func isOpen(at time: TimeOfDay) -> Bool {
        time >= opensAt && time < closesAt
    }
}
