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
protocol QuestionGenerator: Sendable {
    /// Questions worth asking about these candidates, best first.
    ///
    /// - Parameters:
    ///   - candidates: the restaurants still in the running.
    ///   - alreadyAsked: questions the diner has answered already, which must not be repeated.
    ///   - thinkingAloud: called with each fragment of the generator's reasoning as it arrives, so
    ///     the screen can show the work rather than a spinner. A generator that has no reasoning to
    ///     report simply never calls it.
    /// - Returns: between one and three questions, in the order they should be asked.
    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion],
                   thinkingAloud: @escaping @Sendable (String) -> Void) async throws -> [LunchQuestion]

    /// Whether this generator can actually be asked anything.
    ///
    /// False only for the stand-in used when no question service is configured. It exists so the
    /// app can stop and say so rather than quietly narrow with something weaker: the use case reads
    /// this before asking, and the diner is told the app is not set up.
    var isConfigured: Bool { get }
}

extension QuestionGenerator {
    /// For callers that do not show the reasoning, chiefly tests and the deterministic generator.
    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion] = []) async throws -> [LunchQuestion] {
        try await questions(narrowing: candidates, alreadyAsked: alreadyAsked, thinkingAloud: { _ in })
    }

    /// Anything that can be asked is configured; the one that cannot says so for itself.
    var isConfigured: Bool { true }
}
