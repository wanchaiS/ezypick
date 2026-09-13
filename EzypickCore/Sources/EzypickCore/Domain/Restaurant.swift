import Foundation

/// A cuisine, as a diner would name it when saying where they want to eat.
public enum Cuisine: String, CaseIterable, Codable, Sendable {
    case italian, thai, japanese, vietnamese, chinese, korean, indian, mexican
    case modernAustralian, modernAsian, middleEastern, burgers, salads, sandwiches, sushi, pizza, cafe
}

/// A characteristic of a restaurant that a diner could answer yes or no about.
///
/// These are the raw material for the narrowing questions: a question is only worth asking when
/// the restaurants still in the running disagree about one of these.
public enum RestaurantAttribute: String, CaseIterable, Codable, Sendable {
    case quickService, sitDownDining, outdoorSeating, quiet, lively, goodForGroups
    case takeawayAvailable, sharedTables, licensed, counterOrder, bookingsTaken, hearty, light
}

/// A restaurant the app knows about and could suggest for lunch.
///
/// Mirrors the shape of Google Places API (New) closely enough that the seeded catalogue can be
/// swapped for live data by replacing the repository and nothing else. \`dietaryOptions\` has no
/// equivalent in any places API and is therefore carried with its own provenance.
public struct Restaurant: Identifiable, Equatable, Codable, Sendable {
    /// A restaurant's identity, typed so it can never be confused with any other identifier.
    public struct ID: Hashable, Codable, Sendable {
        public let value: String
        public init(_ value: String) { self.value = value }
        public init(from decoder: Decoder) throws {
            value = try decoder.singleValueContainer().decode(String.self)
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer(); try c.encode(value)
        }
    }

    public let id: ID
    public let name: String
    public let cuisine: Cuisine
    /// Typical spend for one diner, in whole dollars.
    public let pricePerHead: Int
    public let rating: Double
    public let ratingCount: Int
    /// Minutes on foot from the office. Minutes rather than metres: a lunch break is measured in time.
    public let walkingMinutes: Int
    public let opensAt: TimeOfDay
    public let closesAt: TimeOfDay
    /// Dietary requirements this restaurant can cater for.
    public let dietary: Set<DietaryConstraint>
    public let dietaryProvenance: DietaryProvenance
    public let attributes: Set<RestaurantAttribute>
    public let editorialSummary: String
    /// Short quotes from diners. Unstructured, and therefore the material a language model reads.
    public let reviewSnippets: [String]

    public init(id: ID, name: String, cuisine: Cuisine, pricePerHead: Int, rating: Double,
                ratingCount: Int, walkingMinutes: Int, opensAt: TimeOfDay, closesAt: TimeOfDay,
                dietary: Set<DietaryConstraint>, dietaryProvenance: DietaryProvenance,
                attributes: Set<RestaurantAttribute>, editorialSummary: String, reviewSnippets: [String]) {
        self.id = id; self.name = name; self.cuisine = cuisine; self.pricePerHead = pricePerHead
        self.rating = rating; self.ratingCount = ratingCount; self.walkingMinutes = walkingMinutes
        self.opensAt = opensAt; self.closesAt = closesAt; self.dietary = dietary
        self.dietaryProvenance = dietaryProvenance; self.attributes = attributes
        self.editorialSummary = editorialSummary; self.reviewSnippets = reviewSnippets
    }

    /// Whether the restaurant is serving at a given time.
    ///
    /// - Important: Business rule — a restaurant that is shut when the diner wants to eat is not
    ///   a candidate, however well it fits otherwise.
    public func isOpen(at time: TimeOfDay) -> Bool {
        time >= opensAt && time < closesAt
    }

    /// Whether the restaurant can cater for every one of the diner's requirements.
    public func canCater(for constraints: Set<DietaryConstraint>) -> Bool {
        constraints.isSubset(of: dietary)
    }
}
