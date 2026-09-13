import Foundation

/// The restaurants the app ships with.
///
/// Field names mirror Google Places API (New) closely enough that replacing this with a live
/// adapter is a change to this one type. Two things are seeded because no places API supplies
/// them: dietary capability, which no mainstream API exposes at all, and the review snippets and
/// atmosphere flags, which sit behind Google's most expensive billing tier.
public struct SeededRestaurantCatalogue: RestaurantRepository {
    private let restaurants: [Restaurant]

    /// Loads the catalogue bundled with the app.
    public init() throws {
        guard let url = Bundle.module.url(forResource: "restaurants", withExtension: "json") else {
            throw CatalogueError.catalogueMissing
        }
        try self.init(json: Data(contentsOf: url))
    }

    /// Loads a catalogue from raw JSON, which is how tests supply their own.
    public init(json: Data) throws {
        self.restaurants = try JSONDecoder().decode([Restaurant].self, from: json)
    }

    public func nearbyRestaurants() async throws -> [Restaurant] { restaurants }

    public enum CatalogueError: LocalizedError, Equatable {
        case catalogueMissing
        public var errorDescription: String? {
            "The restaurant list is missing from the app. Reinstall Ezypick to restore it."
        }
    }
}
