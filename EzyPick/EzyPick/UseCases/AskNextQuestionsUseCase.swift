import Foundation

/// Decides what to ask the diner next, or that nothing more is worth asking.
///
/// - Important: Business rules — at most five questions per lunch; stop as soon as three or fewer
///   candidates remain; never ask the same thing twice; never ask anything that fails to split
///   the candidates. Enforced here rather than by whatever wrote the question.
struct AskNextQuestionsUseCase {
    /// The most questions a diner will ever be asked.
    static let questionLimit = 5
    /// How many restaurants count as few enough for a person to choose between unaided.
    static let shortlistTarget = 3

    private let generator: QuestionGenerator
    private let fallback: QuestionGenerator

    /// - Parameter fallback: used when the preferred generator fails, is unreachable, or returns
    ///   nothing usable.
    init(generator: QuestionGenerator, fallback: QuestionGenerator = TemplateQuestionGenerator()) {
        self.generator = generator
        self.fallback = fallback
    }

    /// Whether this run can ask anything at all. Read by the view model so the flow can stop on
    /// the results screen when no question service is configured.
    var canAsk: Bool { generator.isConfigured }

    func execute(narrowing candidates: [CandidateRestaurant],
                 alreadyAsked: [LunchQuestion] = []) async -> NarrowingStep {
        guard generator.isConfigured else { return .stop(.noQuestionService) }
        guard candidates.count > Self.shortlistTarget else { return .stop(.fewEnoughLeft) }
        guard alreadyAsked.count < Self.questionLimit else { return .stop(.questionLimitReached) }

        let suggested = (try? await generator.questions(narrowing: candidates,
                                                        alreadyAsked: alreadyAsked)) ?? []
        if let usable = bestUsable(from: suggested, candidates: candidates, alreadyAsked: alreadyAsked) {
            return .ask(usable)
        }

        // The service was reachable and said nothing usable, so the built-in generator answers.
        let backup = (try? await fallback.questions(narrowing: candidates, alreadyAsked: alreadyAsked)) ?? []
        if let usable = bestUsable(from: backup, candidates: candidates, alreadyAsked: alreadyAsked) {
            return .ask(usable)
        }

        return .stop(.nothingLeftToAsk)
    }

    /// The most evenly splitting question that divides the candidates and has not been asked.
    ///
    /// - Note: Most even rather than the generator's first suggestion, which tends to be the most
    ///   interesting question rather than the most useful: one only a single venue answers yes to
    ///   barely narrows anything. Generator order breaks ties.
    private func bestUsable(from questions: [LunchQuestion],
                            candidates: [CandidateRestaurant],
                            alreadyAsked: [LunchQuestion]) -> LunchQuestion? {
        questions
            .filter { !$0.repeats(alreadyAsked) && $0.splits(candidates) }
            .min { imbalance(of: $0, among: candidates) < imbalance(of: $1, among: candidates) }
    }

    /// How far from a half-and-half split a question falls. Smaller is a better question.
    private func imbalance(of question: LunchQuestion, among candidates: [CandidateRestaurant]) -> Int {
        abs(candidates.count - 2 * question.yesCount(among: candidates))
    }
}
