import Foundation

/// A single yes-or-no question put to the diner in order to narrow the shortlist.
///
/// A question carries its own answer key: `keptByYes` names the restaurants a yes leaves standing,
/// and everything else is what a no leaves. Applying an answer is therefore a set intersection and
/// needs nothing from a venue's structured fields, which is what lets a question be about something
/// only a reader could know — whether the reviews sound rushed, whether a place is a treat or a
/// refuel.
///
/// This replaced a design where a question named one of thirteen fixed characteristics and the app
/// filtered on that. It read well and it could not work: a venue mapped from a places API carries
/// only the five characteristics the API asserts, so the interesting questions were discarded by
/// the split check and a template generator answered instead, which looked from the outside exactly
/// like success.
///
/// - Important: Business rule — a question is only valid if at least one candidate answers yes and
///   at least one answers no. Whatever wrote the question does not get to decide that; it is
///   checked against the candidates actually in front of the diner.
struct LunchQuestion: Equatable, Sendable {
    /// What the question is about, in a word or two, so the same ground is never covered twice.
    let topic: String
    /// The question as the diner reads it.
    let text: String
    /// The restaurants a yes keeps. Anything not named here is what a no keeps.
    let keptByYes: Set<Restaurant.ID>
    /// One line saying what this question is splitting on, shown under it.
    ///
    /// Belongs to the question rather than to the generator's stream of thinking, and that is the
    /// whole point. The screen used to show the first sentence of the reasoning, which describes
    /// whatever the model considered first — not necessarily the question the app went on to pick,
    /// since it chooses the most evenly splitting one. A diner then read a question about pubs
    /// explained by a sentence about two Italian places. Empty when whatever wrote the question
    /// had no reasoning to give, which the deterministic generator never does.
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

    /// Whether this covers ground the diner has already been asked about.
    ///
    /// Compared on the topic rather than the wording, because a model asked twice about the same
    /// thing rarely phrases it the same way twice.
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

/// Why the app stopped asking. Kept as a reason rather than a flag so the screen can explain itself.
enum StopReason: Equatable, Sendable {
    /// Three or fewer restaurants remain — the diner can choose from these without help.
    case fewEnoughLeft
    /// The app has asked as many questions as it is allowed to.
    case questionLimitReached
    /// Nothing left to ask that would tell the app anything new.
    case nothingLeftToAsk
    /// No question service is configured, so there is nothing to write the questions.
    ///
    /// Unlike the other three this is not a finished lunch, and the diner is not shown a shortlist.
    /// The app could fall back to the built-in generator and it deliberately does not: narrowing by
    /// what a places API happens to assert is a different, weaker product than narrowing by what a
    /// reader can tell about a place, and quietly serving the second while claiming the first is
    /// the same substitution that got the seeded catalogue deleted.
    case noQuestionService
}
