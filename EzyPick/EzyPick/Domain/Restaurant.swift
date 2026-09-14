import Foundation

/// A cuisine, as a diner would name it when saying where they want to eat.
enum Cuisine: String, CaseIterable, Codable, Sendable {
    case italian, thai, japanese, vietnamese, chinese, korean, indian, mexican
    case modernAustralian, modernAsian, middleEastern, burgers, salads, sandwiches, sushi, pizza, cafe

    /// How this cuisine is written on screen, in a diner's words rather than the enum's.
    ///
    /// Capitalising the raw value is not enough: it produces "Modernaustralian" and
    /// "Middleeastern". Title case because a cuisine is a proper adjective and appears on a label
    /// rather than inside a sentence.
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
/// These are the raw material for the narrowing questions: a question is only worth asking when
/// the restaurants still in the running disagree about one of these.
enum RestaurantAttribute: String, CaseIterable, Codable, Sendable {
    case quickService, sitDownDining, outdoorSeating, quiet, lively, goodForGroups
    case takeawayAvailable, sharedTables, licensed, counterOrder, bookingsTaken, hearty, light
}

/// A restaurant the app knows about and could suggest for lunch.
///
/// Mirrors the shape of Google Places API (New) closely enough that everything the app knows about
/// a restaurant is something one lookup actually answered for. Nothing here is inferred, and
/// nothing is carried that the app cannot act on.
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
    /// Minutes on foot from the office. Minutes rather than metres: a lunch break is measured in time.
    let walkingMinutes: Int
    let opensAt: TimeOfDay
    let closesAt: TimeOfDay
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
    /// - Important: Business rule — a restaurant that is shut when the diner wants to eat is not
    ///   a candidate, however well it fits otherwise.
    func isOpen(at time: TimeOfDay) -> Bool {
        time >= opensAt && time < closesAt
    }
}
