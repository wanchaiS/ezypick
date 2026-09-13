import Foundation

/// Something that can read a set of candidate restaurants and write questions that tell them apart.
///
/// Two implementations exist and the difference matters. \`LLMQuestionGenerator\` reads the parts of a
/// restaurant no database column can express — the reviews, the editorial blurb — and phrases a
/// question about them. \`TemplateQuestionGenerator\` works from the structured attributes alone and
/// always returns the most evenly splitting one.
///
/// - Important: Whatever a generator returns is treated as a suggestion. The use case checks that a
///   question genuinely splits the candidates and has not already been asked before it reaches
///   anyone; a question that fails that check is discarded.
public protocol QuestionGenerator: Sendable {
    /// Questions worth asking about these candidates, best first.
    ///
    /// - Parameters:
    ///   - candidates: the restaurants still in the running.
    ///   - alreadyAsked: questions the diner has answered already, which must not be repeated.
    /// - Returns: between one and three questions, in the order they should be asked.
    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion]
}
