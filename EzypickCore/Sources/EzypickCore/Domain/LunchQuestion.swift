import Foundation

/// A single yes-or-no question put to the diner in order to narrow the shortlist.
///
/// A question is always **about the restaurants still in the running** rather than about food in
/// the abstract. It exists only to split the surviving candidates; one that cannot split them
/// tells the app nothing and costs the diner a tap, so it is never asked.
///
/// - Important: Business rule — a question is only valid if at least one candidate answers yes and
///   at least one answers no.
public struct LunchQuestion: Equatable, Sendable {
    /// The characteristic being asked about. Answering yes keeps the candidates that have it.
    public let attribute: RestaurantAttribute
    /// The question as the diner reads it.
    public let text: String

    public init(attribute: RestaurantAttribute, text: String) {
        self.attribute = attribute
        self.text = text
    }

    /// Whether this question would actually divide the given candidates.
    public func splits(_ candidates: [CandidateRestaurant]) -> Bool {
        let yes = candidates.filter { $0.has(attribute) }.count
        return yes > 0 && yes < candidates.count
    }
}

/// The diner's answer to a question.
public enum Answer: Equatable, Sendable {
    case yes, no
}

/// What the app decided to do next: ask another question, or stop and show the shortlist.
public enum NarrowingStep: Equatable, Sendable {
    case ask(LunchQuestion)
    case stop(StopReason)
}

/// Why the app stopped asking. Kept as a reason rather than a flag so the screen can explain itself.
public enum StopReason: Equatable, Sendable {
    /// Three or fewer restaurants remain — the diner can choose from these without help.
    case fewEnoughLeft
    /// The app has asked as many questions as it is allowed to.
    case questionLimitReached
    /// Nothing left to ask that would tell the app anything new.
    case nothingLeftToAsk
}
