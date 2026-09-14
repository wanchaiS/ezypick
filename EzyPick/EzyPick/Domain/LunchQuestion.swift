import Foundation

/// A single yes-or-no question put to the diner in order to narrow the shortlist.
///
/// - Important: `keptByYes` is the answer key — a yes keeps those restaurants, a no keeps the
///   rest — so applying an answer is a set intersection that reads no structured fields.
/// - Important: Business rule — a question is valid only if at least one candidate answers yes and
///   at least one answers no, checked against the candidates in front of the diner.
struct LunchQuestion: Equatable, Sendable {
    /// What the question is about, in a word or two, so the same ground is never covered twice.
    let topic: String
    /// The question as the diner reads it.
    let text: String
    /// The restaurants a yes keeps. Anything not named here is what a no keeps.
    let keptByYes: Set<Restaurant.ID>
    /// One line saying what this question is splitting on, shown under it. Belongs to the question
    /// rather than the generator's reasoning stream, so it always matches the question actually
    /// picked; empty when the writer gave no reason.
    let because: String

    init(topic: String, text: String, keptByYes: Set<Restaurant.ID>, because: String = "") {
        self.topic = topic
        self.text = text
        self.keptByYes = keptByYes
        self.because = because
    }

    /// Whether this question would actually divide the given candidates.
    func splits(_ candidates: [CandidateRestaurant]) -> Bool {
        let yes = candidates.lazy.filter { keptByYes.contains($0.id) }.count
        return yes > 0 && yes < candidates.count
    }

    /// How many of these candidates a yes would keep, which is what the screen counts down.
    func yesCount(among candidates: [CandidateRestaurant]) -> Int {
        candidates.lazy.filter { keptByYes.contains($0.id) }.count
    }

    /// Whether this covers ground the diner has already been asked about, compared on `topic`
    /// rather than wording, since the same ground is rarely phrased the same twice.
    func repeats(_ asked: [LunchQuestion]) -> Bool {
        asked.contains { $0.topic.caseInsensitiveCompare(topic) == .orderedSame }
    }
}

/// The diner's answer to a question.
enum Answer: Equatable, Sendable {
    case yes, no
}

/// What the app decided to do next: ask another question, or stop and show the shortlist.
enum NarrowingStep: Equatable, Sendable {
    case ask(LunchQuestion)
    case stop(StopReason)
}

/// Why the app stopped asking, kept as a reason rather than a flag so the screen can explain itself.
enum StopReason: Equatable, Sendable {
    /// Three or fewer restaurants remain — the diner can choose from these without help.
    case fewEnoughLeft
    /// The app has asked as many questions as it is allowed to.
    case questionLimitReached
    /// Nothing left to ask that would tell the app anything new.
    case nothingLeftToAsk
    /// No question service is configured, so nothing can write the questions.
    ///
    /// - Important: Not a finished lunch; no shortlist is shown, and the app deliberately does not
    ///   fall back to the built-in generator.
    case noQuestionService
}
