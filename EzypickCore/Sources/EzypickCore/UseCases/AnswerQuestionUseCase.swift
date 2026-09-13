import Foundation

/// Applies the diner's yes or no, narrowing the restaurants still in the running.
///
/// - Important: Business rule — an answer must never leave the diner with nothing. If a question
///   could wipe out every remaining restaurant it should not have been asked, so this refuses to
///   apply it rather than emptying the shortlist.
public struct AnswerQuestionUseCase {
    public init() {}

    /// - Returns: the restaurants that match the diner's answer.
    /// - Throws: `AnswerQuestionError.answerWouldRuleOutEverything` when applying the answer would
    ///   leave nothing, which means the question should never have reached the diner.
    public func execute(_ answer: Answer,
                        to question: LunchQuestion,
                        narrowing candidates: [CandidateRestaurant]) throws -> [CandidateRestaurant] {
        let remaining = candidates.filter { candidate in
            switch answer {
            case .yes: candidate.has(question.attribute)
            case .no: !candidate.has(question.attribute)
            }
        }
        guard !remaining.isEmpty else {
            throw AnswerQuestionError.answerWouldRuleOutEverything(question: question.text)
        }
        return remaining
    }
}

/// What can go wrong when an answer is applied.
public enum AnswerQuestionError: LocalizedError, Equatable {
    /// The answer would have left the diner with no restaurants at all.
    case answerWouldRuleOutEverything(question: String)

    public var errorDescription: String? {
        switch self {
        case .answerWouldRuleOutEverything:
            "That would rule out everywhere left, so we've kept your options as they were."
        }
    }

    public var recoverySuggestion: String? {
        "Answer the next question instead, or pick from what's on the list."
    }
}
