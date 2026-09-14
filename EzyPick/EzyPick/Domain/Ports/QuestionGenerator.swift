import Foundation

/// Something that can read candidate restaurants and write questions that tell them apart.
///
/// - Important: What a generator returns is a suggestion, never an instruction. The use case checks
///   that a question really splits the candidates and was not already asked, and discards it if not.
protocol QuestionGenerator: Sendable {
    /// Questions worth asking about these candidates, best first.
    ///
    /// - Parameter alreadyAsked: questions the diner has answered, which must not be repeated.
    /// - Returns: between one and three questions, preferred first. Preference is a hint only: the
    ///   use case picks whichever splits the candidates most evenly and uses this order for ties.
    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion]

    /// Whether this generator can actually be asked anything.
    ///
    /// - Important: False only for the stand-in used when no question service is configured; the
    ///   use case reads it and stops rather than narrowing with something weaker.
    var isConfigured: Bool { get }
}

extension QuestionGenerator {
    /// Anything that can be asked is configured; the stand-in overrides this.
    var isConfigured: Bool { true }
}
