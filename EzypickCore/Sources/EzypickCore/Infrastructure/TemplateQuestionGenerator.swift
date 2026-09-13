import Foundation

/// Writes narrowing questions from the restaurants' structured attributes alone.
///
/// It picks whichever characteristic divides the remaining restaurants most evenly, because that
/// is the question that rules out the most options per tap. Deterministic, instant and free: it
/// backs the language model when there is no network, no key, or nothing usable came back, and it
/// is what the tests run against so that business rules are never asserted against a model's mood.
public struct TemplateQuestionGenerator: QuestionGenerator {
    public init() {}

    public func questions(narrowing candidates: [CandidateRestaurant],
                          alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion] {
        rankedQuestions(narrowing: candidates, alreadyAsked: alreadyAsked)
    }

    /// Exposed synchronously so callers that cannot await still have a question to fall back on.
    public func rankedQuestions(narrowing candidates: [CandidateRestaurant],
                                alreadyAsked: [LunchQuestion]) -> [LunchQuestion] {
        guard !candidates.isEmpty else { return [] }
        let asked = Set(alreadyAsked.map(\.attribute))

        let scored: [(question: LunchQuestion, balance: Int)] = RestaurantAttribute.allCases
            .filter { !asked.contains($0) }
            .compactMap { attribute in
                let yes = candidates.filter { $0.has(attribute) }.count
                guard yes > 0, yes < candidates.count else { return nil }
                // Distance from a perfectly even split; smaller is a better question.
                let balance = abs(candidates.count - 2 * yes)
                return (LunchQuestion(attribute: attribute, text: Self.wording(for: attribute)), balance)
            }
            .sorted { ($0.balance, $0.question.attribute.rawValue) < ($1.balance, $1.question.attribute.rawValue) }

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
