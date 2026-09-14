import SwiftUI

/// Builds the app's parts and hands them to the first screen.
///
/// - Note: The only place that knows which implementations are in use.
@main
struct EzyPickApp: App {
    private let store = UserDefaultsPreferencesStore()
    private let restaurants: RestaurantRepository
    private let generator: QuestionGenerator
    private let location = DeviceLocationProvider()

    init() {
        let configuration = AppConfiguration.current
        restaurants = Self.catalogue(configuration, at: location)
        generator = Self.questionWriter(configuration)
    }

    var body: some Scene {
        WindowGroup {
            HomeView(store: store, restaurants: restaurants, generator: generator, location: location)
        }
    }

    /// Where the candidate restaurants come from: real venues near the device, or a stub that
    /// says the app is not set up when no places key is configured.
    private static func catalogue(_ configuration: AppConfiguration,
                                  at location: any CurrentLocationProvider) -> RestaurantRepository {
        guard let key = configuration.googlePlacesAPIKey else { return UnconfiguredCatalogue() }
        return GooglePlacesRestaurantRepository(apiKey: key,
                                                location: location,
                                                searchRadiusMetres: configuration.placesSearchRadiusMetres)
    }

    /// Who writes the narrowing questions, pointed at a service by the local configuration file.
    ///
    /// - Important: With no question service configured the app stops after the research rather
    ///   than narrowing with the weaker built-in generator.
    private static func questionWriter(_ configuration: AppConfiguration) -> QuestionGenerator {
        guard let baseURL = configuration.aiBaseURL, let key = configuration.aiAPIKey else {
            return QuestionServiceMissing()
        }
        guard let model = configuration.aiModel else {
            return LLMQuestionGenerator(apiKey: key, endpoint: endpoint(from: baseURL))
        }
        return LLMQuestionGenerator(apiKey: key, endpoint: endpoint(from: baseURL), model: model)
    }

    /// Turns the configured base URL into the address the generator posts to.
    ///
    /// - Note: Services document their base URL ending at the version segment, which is what gets
    ///   pasted into a settings file. An address already written out in full is left alone.
    private static func endpoint(from baseURL: URL) -> URL {
        baseURL.path.hasSuffix("/chat/completions")
            ? baseURL
            : baseURL.appendingPathComponent("chat/completions")
    }
}

/// Stands in when no places key has been configured, so the app still launches and can say why.
///
/// - Important: Throws rather than returning an empty list, which the rules would report as
///   "nothing nearby fits".
private struct UnconfiguredCatalogue: RestaurantRepository {
    func nearbyRestaurants() async throws -> [Restaurant] { throw NotConfigured() }

    struct NotConfigured: LocalizedError {
        var errorDescription: String? {
            "Ezypick has not been set up to look up restaurants yet."
        }
        var recoverySuggestion: String? {
                "Add a Google Places key to the .env file at the root of the project and build again."
        }
    }
}

/// Stands in when no question service has been configured.
///
/// - Note: Never asked anything: `AskNextQuestionsUseCase` reads `isConfigured` first and stops.
///   The throw is there so a caller that ignored the flag fails loudly.
private struct QuestionServiceMissing: QuestionGenerator {
    var isConfigured: Bool { false }

    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion] {
        throw NotConfigured()
    }

    struct NotConfigured: LocalizedError {
        var errorDescription: String? {
            "Ezypick has not been set up to write questions yet."
        }
        var recoverySuggestion: String? {
            "Add a question service key to the .env file at the root of the project and build again."
        }
    }
}
