import Testing
import Foundation
@testable import EzyPick

/// The app promises to ask as little as possible. These check it keeps that promise even when the
/// language model is unavailable, repetitive, or suggesting something useless.
@Suite("Deciding what to ask next")
struct AskNextQuestionsTests {

    private func fiveMixedCandidates() -> [CandidateRestaurant] {
        candidates([
            restaurant("A", attributes: [.quickService, .light]),
            restaurant("B", attributes: [.quickService]),
            restaurant("C", attributes: [.sitDownDining, .hearty]),
            restaurant("D", attributes: [.sitDownDining, .outdoorSeating]),
            restaurant("E", attributes: [.sitDownDining, .quiet])
        ])
    }


    @Test("Never asks a sixth question, however many places are left")
    func neverAsksMoreThanFiveQuestions() async {
        let asked = ["quiet", "lively", "hearty", "light", "licensed"]
            .map { LunchQuestion(topic: $0, text: "asked already", keptByYes: []) }

        let step = await AskNextQuestionsUseCase(generator: TemplateQuestionGenerator())
            .execute(narrowing: fiveMixedCandidates(), alreadyAsked: asked)

        #expect(step == .stop(.questionLimitReached))
    }

    @Test("Asks a question the remaining places genuinely disagree about")
    func asksAQuestionThatDividesTheRemainingPlaces() async throws {
        let candidates = fiveMixedCandidates()
        let step = await AskNextQuestionsUseCase(generator: TemplateQuestionGenerator())
            .execute(narrowing: candidates)

        guard case .ask(let question) = step else {
            Issue.record("Expected a question with five places still in the running")
            return
        }
        #expect(question.splits(candidates))
    }

}

/// Applying an answer is where a shortlist can silently vanish, so it has its own rule.
@Suite("Applying the diner's answer")
struct AnswerQuestionTests {

    @Test("Yes keeps the places that match, no keeps the rest")
    func narrowsThePlacesToMatchTheAnswer() throws {
        let places = candidates([
            restaurant("Quick One", attributes: [.quickService]),
            restaurant("Sit Down", attributes: [.sitDownDining])
        ])
        let hurry = question(about: .quickService, among: places)

        let yes = try AnswerQuestionUseCase().execute(.yes, to: hurry, narrowing: places)
        let no = try AnswerQuestionUseCase().execute(.no, to: hurry, narrowing: places)

        #expect(yes.map(\.restaurant.name) == ["Quick One"])
        #expect(no.map(\.restaurant.name) == ["Sit Down"])
    }

    @Test("An answer is refused if it would leave the diner with nowhere to eat")
    func refusesAnAnswerThatWouldLeaveNothing() throws {
        let places = candidates([restaurant("Only Option", attributes: [.quickService])])
        let outside = question(about: .outdoorSeating, among: places)

        #expect(throws: AnswerQuestionError.answerWouldRuleOutEverything(question: "Fancy sitting outside?")) {
            try AnswerQuestionUseCase().execute(.yes, to: outside, narrowing: places)
        }
    }
}
