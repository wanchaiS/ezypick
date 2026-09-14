import Foundation
import Combine
import CoreLocation

/// Drives one trip through the app: the research, the questions, and the shortlist at the end.
///
/// - Note: Which restaurants qualify and what to ask next is decided by a use case, never here.
@MainActor
final class LunchSearchViewModel: ObservableObject {

    /// Where the diner currently is in deciding. The whole screen flow is driven off this.
    enum Phase: Equatable {
        /// The screen is up but `findLunch` has not run; drawn the same as ``lookingAround``.
        case notStarted
        /// The one billed lookup is in flight. Every later phase re-fences what it returned.
        case lookingAround
        /// The places that fit the diner's own limits, named rather than counted.
        case results(NearbySurvey)
        /// The last answer is applied and the next question written: the only wait on a service.
        case thinking
        /// A question is on screen. ``question`` must be set before this, or nothing is drawn.
        case asking
        /// The final few, with the pick first.
        case shortlist
        /// The search worked but the narrowing cannot run. Not the same as nothing fitting.
        case notSetUp(problem: String, howToFixIt: String)
        /// Where every failure lands, not only the diner's limits: a refused location or an
        /// unreachable service too, each with its own words.
        case nothingFits(problem: String, howToFixIt: String)
    }

    @Published private(set) var phase: Phase = .notStarted
    @Published private(set) var candidates: [CandidateRestaurant] = []
    @Published private(set) var question: LunchQuestion?
    @Published private(set) var askedSoFar: [LunchQuestion] = []
    @Published private(set) var tally: ExclusionTally?
    @Published private(set) var stoppedBecause: StopReason?

    private var declined: Set<Restaurant.ID> = []
    private var preferences: DiningPreferences?
    /// The one search this trip is built on: where it ran from, and what it returned.
    ///
    /// - Important: Held for the whole trip, so widening a limit re-fences the places already
    ///   found rather than paying for a second billed lookup.
    private var search: (origin: Coordinate, places: [Restaurant])?

    private let restaurants: RestaurantRepository
    private let location: any CurrentLocationProvider
    private let surveying = SurveyNearbyRestaurantsUseCase()
    private let shortlisting = ShortlistRestaurantsUseCase()
    private let narrowing: AskNextQuestionsUseCase
    private let answering = AnswerQuestionUseCase()

    /// The suburb, looked up after the results are already on screen: a courtesy, never a hold-up.
    @Published private(set) var originName: String?

    init(restaurants: RestaurantRepository,
         generator: QuestionGenerator,
         location: any CurrentLocationProvider) {
        self.restaurants = restaurants
        self.location = location
        self.narrowing = AskNextQuestionsUseCase(generator: generator)
    }

    var questionNumber: Int { askedSoFar.count + 1 }
    var questionLimit: Int { AskNextQuestionsUseCase.questionLimit }

    /// A new trip: the diner has come back to the home screen and pressed the button again.
    ///
    /// - Important: Turning down a shortlist lasts for one trip only. Left standing, it silently
    ///   excludes places the diner never saw.
    func startOver() {
        declined = []
        search = nil
        originName = nil
    }

    /// Looks up what is around the diner and stops, so they see the search before it is narrowed.
    func findLunch(for preferences: DiningPreferences) async {
        self.preferences = preferences
        phase = .lookingAround
        askedSoFar = []
        question = nil
        stoppedBecause = nil
        tally = nil

        do {
            let trip: (origin: Coordinate, places: [Restaurant])
            if let search {
                trip = search
            } else {
                trip = (try await location.currentCoordinate(),
                        try await restaurants.nearbyRestaurants())
                search = trip
            }

            // Both read the same one search: the survey describes everything found and excludes
            // nothing, the fence applies the diner's limits, so the count on screen and the tally
            // of what went missing under it are counted off the same denominator.
            let survey = try surveying.execute(from: trip.places, at: trip.origin)
            let shortlist = try shortlisting.execute(from: trip.places,
                                                     for: preferences,
                                                     at: TimeOfDay.now,
                                                     declining: declined)
            candidates = shortlist.candidates
            tally = shortlist.excluded
            phase = .results(survey)
            originName = await Self.suburb(at: trip.origin)
        } catch let error as any LocalizedError {
            // Every failure that reaches here writes its own words. Flattening them would tell
            // someone to reopen the app when they need to grant location access.
            phase = .nothingFits(problem: error.errorDescription ?? "Nothing fits today.",
                                 howToFixIt: error.recoverySuggestion ?? "Try widening something.")
        } catch {
            phase = .nothingFits(problem: "The restaurants around you could not be looked up.",
                                 howToFixIt: "Check your connection and try again.")
        }
    }

    /// Turns the coordinate the search ran from into a suburb name, shown next to the coordinate
    /// rather than instead of it.
    ///
    /// - Note: Failure is silent: a missing suburb name must never turn a working search into an
    ///   error.
    private static func suburb(at origin: Coordinate) async -> String? {
        let point = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(point).first else {
            return nil
        }
        return [placemark.subLocality ?? placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    func narrowItDown() async {
        phase = .thinking
        await askOrFinish()
    }

    /// Applies the diner's answer and either asks again or shows the shortlist.
    func answer(_ answer: Answer) async {
        guard let question else { return }
        phase = .thinking
        do {
            candidates = try answering.execute(answer, to: question, narrowing: candidates)
            askedSoFar.append(question)
            await askOrFinish()
        } catch {
            // The question should never have been asked; keep what the diner had and move on.
            askedSoFar.append(question)
            await askOrFinish()
        }
    }

    /// The diner does not fancy any of the three. Rule them out and look again.
    func noneOfThese() async {
        declined.formUnion(candidates.map(\.id))
        guard let preferences else { return }
        await findLunch(for: preferences)
    }

    private func askOrFinish() async {
        let step = await narrowing.execute(narrowing: candidates, alreadyAsked: askedSoFar)
        switch step {
        case .ask(let next):
            question = next
            phase = .asking
        case .stop(.noQuestionService):
            // Stops here rather than falling back to the built-in generator, which narrows by
            // whatever booleans a places API asserts.
            stoppedBecause = .noQuestionService
            question = nil
            phase = .notSetUp(
                problem: "Ezypick found these places but has not been set up to write questions yet.",
                howToFixIt: "Add a question service key to the .env file at the root of the project and build again.")
        case .stop(let reason):
            stoppedBecause = reason
            question = nil
            candidates = Array(candidates.sorted { $0.restaurant.walkingMinutes < $1.restaurant.walkingMinutes }.prefix(3))
            phase = .shortlist
        }
    }
}
