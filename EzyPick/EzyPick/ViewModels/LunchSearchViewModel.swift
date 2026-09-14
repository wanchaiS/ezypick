import Foundation
import Combine
import CoreLocation

/// Drives one trip through the app: the research, the questions, and the shortlist at the end.
///
/// Holds where the diner currently is and what is on screen. Every decision — which restaurants
/// qualify, what to ask next, whether to stop — is made by a use case and only reported here.
@MainActor
final class LunchSearchViewModel: ObservableObject {

    /// Where the diner currently is in deciding.
    enum Phase: Equatable {
        case notStarted
        /// The search is running. Nothing is known yet.
        case lookingAround
        /// The search came back and the diner's own limits have been applied. These are the places
        /// that fit, named rather than counted.
        case results(NearbySurvey)
        /// The model is reading those places and working out what is worth asking.
        case thinking
        case asking
        case shortlist
        /// The search worked and the narrowing cannot run, which is a different thing from nothing
        /// fitting and gets a different screen.
        case notSetUp(problem: String, howToFixIt: String)
        /// Nothing could be suggested, with what blocked it and what to try instead.
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
    private var allowingOverBudget = false
    /// The one search this trip is built on: where it ran from, and what it returned.
    ///
    /// Kept so that widening a limit re-fences the places already found. Searching again would
    /// cost a second billed lookup and could describe a different moment from the summary the
    /// diner is looking at.
    private var search: (origin: Coordinate, places: [Restaurant])?

    private let restaurants: RestaurantRepository
    private let location: any CurrentLocationProvider
    private let surveying = SurveyNearbyRestaurantsUseCase()
    private let shortlisting = ShortlistRestaurantsUseCase()
    private let narrowing: AskNextQuestionsUseCase
    private let answering = AnswerQuestionUseCase()

    /// The suburb the search ran from, once it has been looked up. Nil while unknown.
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
    /// Two things are true only for as long as one trip lasts. Turning down a shortlist rules those
    /// venues out of the *rest of that decision*, not out of lunch forever, and lifting the budget
    /// is the diner saying they will spend more **today**. Both used to outlive the trip that set
    /// them, because nothing marked where a trip ended: a second search silently kept excluding
    /// places the diner had never seen, and quietly ignored the budget cap they had just gone back
    /// and set. A fence that has switched itself off is worse than no fence, because the tally
    /// still reports on it.
    func startOver() {
        declined = []
        allowingOverBudget = false
        search = nil
        originName = nil
    }

    /// Looks up what is around the diner and stops, so they see the search before it is narrowed.
    ///
    /// The narrowing is deliberately not started here. Being shown a question before being shown
    /// what the question is about is how the app would feel like it was guessing, when in fact it
    /// has already done the work.
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

            // The clock is read once and passed in, so the summary and the fence agree about what
            // is open even if the diner takes a minute to press Next.
            let survey = try surveying.execute(from: trip.places, at: trip.origin)
            let shortlist = try shortlisting.execute(from: trip.places,
                                                     for: preferences,
                                                     at: TimeOfDay.now,
                                                     declining: declined,
                                                     allowingOverBudget: allowingOverBudget)
            candidates = shortlist.candidates
            tally = shortlist.excluded
            phase = .results(survey)
            originName = await Self.suburb(at: trip.origin)
        } catch let error as any LocalizedError {
            // Every failure that can reach here writes its own words: the fence explaining which
            // limit did the damage, a refused location, a places lookup that did not come back.
            // Flattening them into one message would tell someone to reopen the app when what they
            // actually need to do is grant location access.
            phase = .nothingFits(problem: error.errorDescription ?? "Nothing fits today.",
                                 howToFixIt: error.recoverySuggestion ?? "Try widening something.")
        } catch {
            phase = .nothingFits(problem: "The restaurants around you could not be looked up.",
                                 howToFixIt: "Check your connection and try again.")
        }
    }

    /// Turns the coordinate the search ran from into a place a person recognises.
    ///
    /// Shown next to the raw coordinate rather than instead of it. A suburb name is what the diner
    /// can actually check against the street they are standing in, but it is a lookup that can be
    /// wrong or unavailable, and the numbers underneath it never are.
    ///
    /// Failure is silent on purpose: not knowing what the suburb is called has no bearing on
    /// whether the restaurants are right, so it must never turn a working search into an error.
    private static func suburb(at origin: Coordinate) async -> String? {
        let point = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(point).first else {
            return nil
        }
        return [placemark.subLocality ?? placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// The diner has seen what was found and asked the app to narrow it down.
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

    /// The diner has decided to spend more than they said today.
    func searchAgainAllowingOverBudget() async {
        allowingOverBudget = true
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
            // Stops here rather than falling back. The built-in generator could answer, and what it
            // would produce is a narrowing by whatever a places API happens to assert, which is a
            // weaker thing than the app claims to do. Serving that silently is the substitution the
            // seeded catalogue was deleted for.
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
