import Testing
import Foundation
@testable import EzyPick

/// The whole point of the app, run end to end over a response recorded from the real endpoint.
///
/// This used to run against a catalogue of invented venues, which made it a test of the app's
/// imagination as much as its rules. Replaying twenty real Sydney restaurants through the real
/// adapter tests the same journey against data nobody tuned to pass: if live venues turn out to be
/// too alike for any question to divide them, that is a finding no amount of correct logic could
/// survive, and this is where it shows up.
@Suite("A lunch decided from start to finish", .serialized)
struct LunchDecisionJourneyTests {

    @Test("A diner reaches a handful of places within the question limit")
    func narrowsRealVenuesToAShortlistWithinFiveQuestions() async throws {
        let places = try await placesRepository(replaying: "places-sydney-lunch").nearbyRestaurants()
        let profile = preferences(budget: 45, walk: 20)

        let shortlist = try ShortlistRestaurantsUseCase().execute(from: places, for: profile, at: lunchtime)
        var remaining = shortlist.candidates
        var asked: [LunchQuestion] = []

        var trace = ["Considered \(shortlist.excluded.consideredCount) restaurants",
                     "  − \(shortlist.excluded.byBudget) over $45",
                     "  − \(shortlist.excluded.byDistance) further than 20 min",
                     "  − \(shortlist.excluded.byOpeningHours) shut at 12:30",
                     "→ \(remaining.count) fit"]

        let narrowing = AskNextQuestionsUseCase(generator: TemplateQuestionGenerator())
        while case .ask(let question) = await narrowing.execute(narrowing: remaining, alreadyAsked: asked) {
            let answer: Answer = asked.count.isMultiple(of: 2) ? .yes : .no
            remaining = try AnswerQuestionUseCase().execute(answer, to: question, narrowing: remaining)
            asked.append(question)
            trace.append("Q\(asked.count): \(question.text) → \(answer == .yes ? "yes" : "no") → \(remaining.count) left")
        }
        trace.append("Shortlist: " + remaining.map(\.restaurant.name).joined(separator: ", "))
        print(trace.joined(separator: "\n"))

        #expect(asked.count <= AskNextQuestionsUseCase.questionLimit)
        #expect(!asked.isEmpty, "Real venues that never differ would make the whole app pointless")
        #expect(!remaining.isEmpty)
        #expect(remaining.count <= 4, "Narrowing should leave a handful of places, not a list to scroll")
        #expect(remaining.allSatisfy { $0.restaurant.pricePerHead <= 45 })
        #expect(remaining.allSatisfy { $0.restaurant.walkingMinutes <= 20 })
        #expect(remaining.allSatisfy { $0.restaurant.isOpen(at: TimeOfDay("12:30")!) })
    }
}
