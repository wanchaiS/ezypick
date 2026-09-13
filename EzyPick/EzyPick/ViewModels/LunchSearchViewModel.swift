import Foundation
import Combine
import EzypickCore

/// Drives one trip through the app: the research, the questions, and the shortlist at the end.
///
/// Holds where the diner currently is and what is on screen. Every decision — which restaurants
/// qualify, what to ask next, whether to stop — is made by a use case and only reported here.
@MainActor
final class LunchSearchViewModel: ObservableObject {

    /// Where the diner currently is in deciding.
    enum Phase: Equatable {
        case notStarted
        case researching
        case asking
        case shortlist
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

    private let shortlisting: ShortlistRestaurantsUseCase
    private let narrowing: AskNextQuestionsUseCase
    private let answering = AnswerQuestionUseCase()

    init(restaurants: RestaurantRepository, generator: QuestionGenerator) {
        self.shortlisting = ShortlistRestaurantsUseCase(restaurants: restaurants)
        self.narrowing = AskNextQuestionsUseCase(generator: generator)
    }

    var questionNumber: Int { askedSoFar.count + 1 }
    var questionLimit: Int { AskNextQuestionsUseCase.questionLimit }

    /// Does the research the diner would otherwise do themselves, then starts asking.
    func findLunch(for preferences: DiningPreferences) async {
        self.preferences = preferences
        phase = .researching
        askedSoFar = []
        question = nil
        stoppedBecause = nil
        await research()
    }

    /// Applies the diner's answer and either asks again or shows the shortlist.
    func answer(_ answer: Answer) async {
        guard let question else { return }
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

    private func research() async {
        guard let preferences else { return }
        do {
            let shortlist = try await shortlisting.execute(for: preferences,
                                                           declining: declined,
                                                           allowingOverBudget: allowingOverBudget)
            candidates = shortlist.candidates
            tally = shortlist.excluded
            await askOrFinish()
        } catch let error as ShortlistRestaurantsError {
            phase = .nothingFits(problem: error.errorDescription ?? "Nothing fits today.",
                                 howToFixIt: error.recoverySuggestion ?? "Try widening something.")
        } catch {
            phase = .nothingFits(problem: "The restaurant list could not be loaded.",
                                 howToFixIt: "Close Ezypick and open it again.")
        }
    }

    private func askOrFinish() async {
        switch await narrowing.execute(narrowing: candidates, alreadyAsked: askedSoFar) {
        case .ask(let next):
            question = next
            phase = .asking
        case .stop(let reason):
            stoppedBecause = reason
            question = nil
            candidates = Array(candidates.sorted { $0.restaurant.walkingMinutes < $1.restaurant.walkingMinutes }.prefix(3))
            phase = .shortlist
        }
    }
}
