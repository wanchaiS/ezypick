import Foundation

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
public struct AskNextQuestionsUseCase {
    /// The most questions a diner will ever be asked. A longer quiz would rebuild the very
    /// decision fatigue the app is meant to remove.
    public static let questionLimit = 5
    /// How many restaurants count as few enough for a person to choose between unaided.
    public static let shortlistTarget = 3

    private let generator: QuestionGenerator
    private let fallback: QuestionGenerator

    /// - Parameters:
    ///   - generator: the preferred source of questions, normally the language model.
    ///   - fallback: used when the preferred one fails, is unreachable, or returns nothing usable.
    public init(generator: QuestionGenerator, fallback: QuestionGenerator = TemplateQuestionGenerator()) {
        self.generator = generator
        self.fallback = fallback
    }

    public func execute(narrowing candidates: [CandidateRestaurant],
                        alreadyAsked: [LunchQuestion] = []) async -> NarrowingStep {
        guard candidates.count > Self.shortlistTarget else { return .stop(.fewEnoughLeft) }
        guard alreadyAsked.count < Self.questionLimit else { return .stop(.questionLimitReached) }

        let suggested = (try? await generator.questions(narrowing: candidates, alreadyAsked: alreadyAsked)) ?? []
        if let usable = firstUsable(from: suggested, candidates: candidates, alreadyAsked: alreadyAsked) {
            return .ask(usable)
        }

        let backup = (try? await fallback.questions(narrowing: candidates, alreadyAsked: alreadyAsked)) ?? []
        if let usable = firstUsable(from: backup, candidates: candidates, alreadyAsked: alreadyAsked) {
            return .ask(usable)
        }

        return .stop(.nothingLeftToAsk)
    }

    /// A question is usable only if it divides the candidates and has not been asked before.
    private func firstUsable(from questions: [LunchQuestion],
                             candidates: [CandidateRestaurant],
                             alreadyAsked: [LunchQuestion]) -> LunchQuestion? {
        let asked = Set(alreadyAsked.map(\.attribute))
        return questions.first { !asked.contains($0.attribute) && $0.splits(candidates) }
    }
}
