import SwiftUI

/// Builds the app's parts and hands them to the first screen.
///
/// The only place that knows which implementations are in use: the venues actually around the diner,
/// found from the device's own location, `UserDefaults` for the profile, and a language model for
/// the questions when one has been configured. Nothing below this line knows the difference.
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

    /// Where the candidate restaurants come from.
    ///
    /// There is one answer now. A catalogue of invented venues used to stand in when no key was
    /// configured, and it went because it was quietly answering a different question than the one
    /// the diner asked: it could say where someone might eat, never where they can eat today. An
    /// app that silently substitutes made-up restaurants for real ones is worse than an app that
    /// says it is not set up.
    private static func catalogue(_ configuration: AppConfiguration,
                                  at location: any CurrentLocationProvider) -> RestaurantRepository {
        guard let key = configuration.googlePlacesAPIKey else { return UnconfiguredCatalogue() }
        return GooglePlacesRestaurantRepository(apiKey: key,
                                                location: location,
                                                searchRadiusMetres: configuration.placesSearchRadiusMetres)
    }

    /// Who writes the narrowing questions.
    ///
    /// One way to point the app at a service, and it is the local configuration file. There used to
    /// be a second: a box in the profile editor for pasting a key. It went because it did not work
    /// and could not have. This initialiser runs once at launch, so a key typed into the profile
    /// took effect only after the app was killed and reopened, and nothing on screen said so. A
    /// control that silently does nothing is worse than no control.
    /// Without a configured service the app **stops after the research** and says so. It could fall
    /// back to the built-in generator, and deliberately does not: that generator narrows by the
    /// handful of booleans a places API asserts, which is a weaker product than reading what a
    /// place is actually like, and serving it silently while claiming the other is the same
    /// substitution the seeded catalogue was deleted for. The diner still gets the whole of stage
    /// one, which is real work on real data: where they are, what is around them, and what fits.
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
    /// Chat completion services document their base URL ending at the version segment, which is
    /// what people paste into a settings file, while `LLMQuestionGenerator` wants the full address.
    /// Completing it here keeps the file looking like the instructions it was copied from, and
    /// leaves an address that was already written out in full alone.
    private static func endpoint(from baseURL: URL) -> URL {
        baseURL.path.hasSuffix("/chat/completions")
            ? baseURL
            : baseURL.appendingPathComponent("chat/completions")
    }
}

/// Stands in when no places key has been configured, so the app still launches and can say why it
/// cannot do the one thing it exists to do.
///
/// Returning an empty list instead would be read by the shortlisting rules as "nothing nearby
/// fits", and the diner would be told to widen their budget when the real problem is that nobody
/// gave the app a key.
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

/// Stands in when no question service has been configured, so the narrowing can refuse rather than
/// be quietly done by something else.
///
/// It is never asked anything: `AskNextQuestionsUseCase` reads `isConfigured` first and stops. The
/// throw exists because a port has to be implementable, and because a caller that ignored the flag
/// should fail loudly rather than receive an empty list of questions and treat it as "nothing worth
/// asking", which is a true sentence about a completely different situation.
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
