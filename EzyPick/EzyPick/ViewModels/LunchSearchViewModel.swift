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
    /// The model's reasoning, as it arrives.
    ///
    /// Shown rather than hidden because the wait is the app's case for itself: this is the reading
    /// a person would otherwise do. Empty whenever nothing is being asked for, and empty for the
    /// whole call when the deterministic generator answers, which is honest — it does not reason.
    @Published private(set) var thinking: String = ""

    private var declined: Set<Restaurant.ID> = []
    private var preferences: DiningPreferences?
    private var allowingOverBudget = false

    private let surveying: SurveyNearbyRestaurantsUseCase
    private let shortlisting: ShortlistRestaurantsUseCase
    private let narrowing: AskNextQuestionsUseCase
    private let answering = AnswerQuestionUseCase()
    private let search: OneShotRestaurantCache

    /// The suburb the search ran from, once it has been looked up. Nil while unknown.
    @Published private(set) var originName: String?

    init(restaurants: RestaurantRepository,
         generator: QuestionGenerator,
         location: any CurrentLocationProvider) {
        // One lookup and one position fix serve the whole trip. Without this the summary the diner
        // reads and the shortlist they get could describe two different searches, from two
        // different corners.
        let search = OneShotRestaurantCache(restaurants)
        self.search = search
        self.surveying = SurveyNearbyRestaurantsUseCase(restaurants: search, location: location)
        self.shortlisting = ShortlistRestaurantsUseCase(restaurants: search)
        self.narrowing = AskNextQuestionsUseCase(generator: generator)
    }

    var questionNumber: Int { askedSoFar.count + 1 }
    var questionLimit: Int { AskNextQuestionsUseCase.questionLimit }

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
        thinking = ""

        do {
            // Both of these read the same single lookup through `OneShotRestaurantCache`, so the
            // summary and the list below it always describe the same search and one trip costs one
            // billed call. The clock is read once, for the same reason.
            let now = TimeOfDay.now
            let survey = try await surveying.execute()
            let shortlist = try await shortlisting.execute(for: preferences,
                                                           at: now,
                                                           declining: declined,
                                                           allowingOverBudget: allowingOverBudget)
            candidates = shortlist.candidates
            tally = shortlist.excluded
            phase = .results(survey)
            originName = await Self.suburb(at: survey.origin)
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
        startThinking()
        await askOrFinish()
    }

    /// Applies the diner's answer and either asks again or shows the shortlist.
    func answer(_ answer: Answer) async {
        guard let question else { return }
        startThinking()
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

    /// Clears the last run's reasoning and shows the screen the diner waits in front of.
    private func startThinking() {
        thinking = ""
        phase = .thinking
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
        let step = await narrowing.execute(narrowing: candidates,
                                           alreadyAsked: askedSoFar,
                                           thinkingAloud: { [weak self] fragment in
                                               Task { @MainActor in self?.thinking += fragment }
                                           })
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
