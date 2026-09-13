import Testing
import Foundation
@testable import EzypickCore

/// The whole point of the app, run end to end against the catalogue it actually ships with.
///
/// This is the test that would catch a catalogue whose restaurants are too alike for any question
/// to divide them — a data problem no amount of correct logic could survive.
@Suite("A lunch decided from start to finish")
struct LunchDecisionJourneyTests {

    @Test("A diner with real constraints reaches three places within the question limit")
    func narrowsTheShippedCatalogueToAShortlistWithinFiveQuestions() async throws {
        let catalogue = try SeededRestaurantCatalogue()
        let profile = preferences(dietary: [.glutenFree], budget: 25, walk: 10, mealTime: "12:30")

        let shortlist = try await ShortlistRestaurantsUseCase(restaurants: catalogue).execute(for: profile)
        var remaining = shortlist.candidates
        var asked: [LunchQuestion] = []

        var trace = ["Considered \(shortlist.excluded.consideredCount) restaurants",
                     "  − \(shortlist.excluded.byDietary) can't do gluten-free",
                     "  − \(shortlist.excluded.byBudget) over $25",
                     "  − \(shortlist.excluded.byDistance) further than 10 min",
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
        #expect(!remaining.isEmpty)
        #expect(remaining.count <= 4, "Narrowing should leave a handful of places, not a list to scroll")
        #expect(remaining.allSatisfy { $0.restaurant.dietary.contains(.glutenFree) })
        #expect(remaining.allSatisfy { $0.restaurant.pricePerHead <= 25 })
        #expect(remaining.allSatisfy { $0.restaurant.isOpen(at: TimeOfDay("12:30")!) })
    }

    @Test("The shipped catalogue is readable and complete")
    func shippedCatalogueLoads() async throws {
        let restaurants = try await SeededRestaurantCatalogue().nearbyRestaurants()

        #expect(restaurants.count == 40)
        #expect(Set(restaurants.map(\.id)).count == 40, "Every restaurant needs its own identity")
        #expect(restaurants.allSatisfy { !$0.reviewSnippets.isEmpty }, "Reviews are what the model reads")
    }

    @Test("A suggestion states where its dietary information came from")
    func statesTheProvenanceOfDietaryInformation() throws {
        let reported = CandidateRestaurant(restaurant("Kiln", dietary: [.glutenFree], provenance: .restaurantReported))
        let unverified = CandidateRestaurant(restaurant("Hearsay", dietary: [.glutenFree], provenance: .unverified))

        #expect(reported.recommendationReason.contains("as listed by the restaurant"))
        #expect(unverified.recommendationReason.contains("not confirmed by the restaurant"))
        // The app never claims to have checked on the diner's behalf.
        #expect(!reported.recommendationReason.lowercased().contains("safe"))
    }
}
