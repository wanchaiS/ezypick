import Foundation

/// Writes narrowing questions from the restaurants' structured attributes alone.
///
/// - Note: Picks whichever characteristic divides the remaining restaurants most evenly, because
///   that rules out the most options per tap. Deterministic and free, so it backs the language
///   model when the service is unreachable or answers with nothing usable, and it is what the
///   tests run against. It is not a substitute for a missing service: with none configured the
///   app stops on the results screen rather than narrowing on booleans alone.
struct TemplateQuestionGenerator: QuestionGenerator {
    init() {}

    func questions(narrowing candidates: [CandidateRestaurant],
                          alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion] {
        rankedQuestions(narrowing: candidates, alreadyAsked: alreadyAsked)
    }

    /// Synchronous because none of this waits on anything; the `async` above is the port's shape,
    /// not this generator's need.
    func rankedQuestions(narrowing candidates: [CandidateRestaurant],
                                alreadyAsked: [LunchQuestion]) -> [LunchQuestion] {
        guard !candidates.isEmpty else { return [] }

        let scored: [(question: LunchQuestion, balance: Int)] = RestaurantAttribute.allCases
            .compactMap { attribute in
                let yes = candidates.filter { $0.has(attribute) }
                guard !yes.isEmpty, yes.count < candidates.count else { return nil }
                let question = LunchQuestion(topic: attribute.rawValue,
                                             text: Self.wording(for: attribute),
                                             keptByYes: Set(yes.map(\.id)))
                guard !question.repeats(alreadyAsked) else { return nil }
                // Distance from a perfectly even split; smaller is a better question.
                return (question, abs(candidates.count - 2 * yes.count))
            }
            .sorted { ($0.balance, $0.question.topic) < ($1.balance, $1.question.topic) }

        return Array(scored.prefix(3).map(\.question))
    }

    /// How each characteristic is put to a diner, in the app's voice.
    static func wording(for attribute: RestaurantAttribute) -> String {
        switch attribute {
        case .quickService: "In a hurry today?"
        case .sitDownDining: "Got time to sit down properly?"
        case .outdoorSeating: "Fancy sitting outside?"
        case .quiet: "Somewhere quiet?"
        case .lively: "Somewhere with a bit of buzz?"
        case .goodForGroups: "Are you eating with other people?"
        case .takeawayAvailable: "Taking it back to the desk?"
        case .sharedTables: "Happy to share a table?"
        case .licensed: "Would you like somewhere that serves a drink?"
        case .counterOrder: "Happy to order at the counter?"
        case .bookingsTaken: "Would you rather book ahead?"
        case .hearty: "After something filling?"
        case .light: "After something light?"
        }
    }
}
