import Foundation
import os

/// Decides what to ask the diner next, or that nothing more is worth asking.
///
/// The app exists to spare someone the work of choosing, so every question has to earn its place.
/// A question is only asked when the restaurants still in the running genuinely disagree about it,
/// and the app stops the moment the answer can no longer change.
///
/// - Important: Business rules — at most five questions per lunch; stop as soon as three or fewer
///   remain; never ask the same thing twice; never ask anything that fails to split the candidates.
///   These rules are enforced here and not by whatever wrote the question, so a language model
///   cannot talk the app out of them.
struct AskNextQuestionsUseCase {
    /// The most questions a diner will ever be asked. A longer quiz would rebuild the very
    /// decision fatigue the app is meant to remove.
    static let questionLimit = 5
    /// How many restaurants count as few enough for a person to choose between unaided.
    static let shortlistTarget = 3

    private let generator: QuestionGenerator
    private let fallback: QuestionGenerator

    /// - Parameters:
    ///   - generator: the preferred source of questions, normally the language model.
    ///   - fallback: used when the preferred one fails, is unreachable, or returns nothing usable.
    init(generator: QuestionGenerator, fallback: QuestionGenerator = TemplateQuestionGenerator()) {
        self.generator = generator
        self.fallback = fallback
    }

    /// Whether this run can ask anything at all.
    ///
    /// Read by the view model so the search can stop on the results screen rather than walk the
    /// diner into a narrowing that is not configured to happen.
    var canAsk: Bool { generator.isConfigured }

    /// - Parameter thinkingAloud: passed through to the generator, so the screen can show the model
    ///   working. The fallback generator is silent, which is correct: it is instant.
    func execute(narrowing candidates: [CandidateRestaurant],
                        alreadyAsked: [LunchQuestion] = [],
                        thinkingAloud: @escaping @Sendable (String) -> Void = { _ in }) async -> NarrowingStep {
        guard generator.isConfigured else { return .stop(.noQuestionService) }
        guard candidates.count > Self.shortlistTarget else { return .stop(.fewEnoughLeft) }
        guard alreadyAsked.count < Self.questionLimit else { return .stop(.questionLimitReached) }

        let suggested = (try? await generator.questions(narrowing: candidates,
                                                        alreadyAsked: alreadyAsked,
                                                        thinkingAloud: thinkingAloud)) ?? []
        if let usable = bestUsable(from: suggested, candidates: candidates, alreadyAsked: alreadyAsked) {
            return .ask(usable)
        }

        // The diner is never told this happened, and should not be: they get a question either way.
        // Whoever is reading the console does need to know, because a run that quietly falls back
        // looks identical to one where the service answered well.
        Diagnostics.questions.notice("""
            falling back to the built-in generator: the service returned \
            \(suggested.count, privacy: .public) question(s), none of which split \
            \(candidates.count, privacy: .public) candidates or were unasked
            """)

        let backup = (try? await fallback.questions(narrowing: candidates, alreadyAsked: alreadyAsked)) ?? []
        if let usable = bestUsable(from: backup, candidates: candidates, alreadyAsked: alreadyAsked) {
            return .ask(usable)
        }

        return .stop(.nothingLeftToAsk)
    }

    /// The most evenly splitting question that divides the candidates and has not been asked.
    ///
    /// Taking the generator's first suggestion instead was worse in a way only live data showed. A
    /// model asked for its best question first leads with the most *interesting* one: against six
    /// Sydney venues it opened with "are you craving a focused bowl of ramen?", which keeps one
    /// restaurant, so yes ends the flow and no has narrowed almost nothing. The measurement behind
    /// the whole question design is that an even split is worth about a bit and a single-cuisine
    /// question about a seventh of one, so the app picks the even one and lets the generator's
    /// order break ties.
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
