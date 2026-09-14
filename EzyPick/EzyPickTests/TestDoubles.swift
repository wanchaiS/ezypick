import Foundation
import Testing
@testable import EzyPick

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
                   alreadyAsked: [LunchQuestion],
                   thinkingAloud: @escaping @Sendable (String) -> Void) async throws -> [LunchQuestion] {
        throw Unavailable()
    }
}

/// A generator that returns whatever a test tells it to, including deliberately useless questions.
struct ScriptedQuestionGenerator: QuestionGenerator {
    let scripted: [LunchQuestion]
    /// Reported through `thinkingAloud` before the questions are returned, for tests that care that
    /// the reasoning reaches the screen.
    var reasoning: [String] = []

    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion],
                   thinkingAloud: @escaping @Sendable (String) -> Void) async throws -> [LunchQuestion] {
        reasoning.forEach(thinkingAloud)
        return scripted
    }
}

/// Stands in for the app's missing-service generator, which is private to its composition root.
struct UnconfiguredQuestionGenerator: QuestionGenerator {
    var isConfigured: Bool { false }

    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion],
                   thinkingAloud: @escaping @Sendable (String) -> Void) async throws -> [LunchQuestion] {
        throw FailingQuestionGenerator.Unavailable()
    }
}

/// A question that keeps whichever of these candidates carries the attribute.
///
/// Tests still describe a split in terms of an attribute because it is the cheapest readable way to
/// say "these two, not those three". The app no longer works that way: a question carries the
/// restaurants a yes keeps, so the translation happens here, once.
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
/// Stated rather than read from the clock: the app searches against the current time, and a test
/// that did the same would pass all morning and fail after three.
let lunchtime = TimeOfDay("12:30")!

/// A diner standing outside Town Hall, so a search origin never depends on a device.
struct FixedLocation: CurrentLocationProvider {
    func currentCoordinate() async throws -> Coordinate {
        Coordinate(latitude: -33.8688, longitude: 151.2093)
    }
}

/// A repository reading a recorded Places response instead of the network.
///
/// With the seeded catalogue gone this is how a test gets a realistic set of restaurants: the real
/// adapter, doing its real mapping, over a response captured from the real endpoint. Nothing is
/// invented and nothing reaches the internet.
func placesRepository(replaying fixture: String) throws -> GooglePlacesRestaurantRepository {
    let url = try #require(Bundle(for: StubbedPlaces.self).url(forResource: fixture, withExtension: "json"))
    return placesRepository(answering: .replied(status: 200, body: try Data(contentsOf: url)))
}

/// A repository whose one request is answered however the caller asks.
func placesRepository(answering outcome: StubbedPlaces.Outcome) -> GooglePlacesRestaurantRepository {
    // The key doubles as the registration, so two suites stubbing at once cannot read each
    // other's response. A single shared slot made the tests order-dependent, and the failure looked
    // like a mapping bug rather than a test-harness one.
    let key = UUID().uuidString
    StubbedPlaces.register(outcome, for: key)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubbedPlaces.self]
    return GooglePlacesRestaurantRepository(apiKey: key,
                                            location: FixedLocation(),
                                            session: URLSession(configuration: configuration))
}

/// Answers the one request the repository makes, so no test ever reaches the internet.
final class StubbedPlaces: URLProtocol {

    enum Outcome: Sendable {
        case replied(status: Int, body: Data)
        case failedToConnect
    }

    /// Responses waiting to be served, keyed by the API key the requesting repository was built
    /// with, so concurrent suites never collide.
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var byKey: [String: Outcome] = [:]

        func register(_ outcome: Outcome, for key: String) {
            lock.lock(); defer { lock.unlock() }
            byKey[key] = outcome
        }

        func outcome(for key: String?) -> Outcome? {
            lock.lock(); defer { lock.unlock() }
            return key.flatMap { byKey[$0] }
        }
    }

    private static let registry = Registry()

    static func register(_ outcome: Outcome, for key: String) {
        registry.register(outcome, for: key)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        switch StubbedPlaces.registry.outcome(for: request.value(forHTTPHeaderField: "X-Goog-Api-Key")) ?? .failedToConnect {
        case .failedToConnect:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .replied(let status, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status,
                                                 httpVersion: "HTTP/1.1", headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

func candidates(_ restaurants: [Restaurant]) -> [CandidateRestaurant] {
    restaurants.map(CandidateRestaurant.init)
}
