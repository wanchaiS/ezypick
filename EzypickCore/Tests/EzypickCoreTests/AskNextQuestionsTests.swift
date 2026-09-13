import Testing
import Foundation
@testable import EzypickCore

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

    @Test("Stops asking as soon as three or fewer places are left")
    func stopsAsSoonAsThreeOrFewerRemain() async {
        let step = await AskNextQuestionsUseCase(generator: TemplateQuestionGenerator())
            .execute(narrowing: candidates([restaurant("A"), restaurant("B"), restaurant("C")]))

        #expect(step == .stop(.fewEnoughLeft))
    }

    @Test("Never asks a sixth question, however many places are left")
    func neverAsksMoreThanFiveQuestions() async {
        let asked = [RestaurantAttribute.quiet, .lively, .hearty, .light, .licensed]
            .map { LunchQuestion(attribute: $0, text: "asked already") }

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

    @Test("Stops when every remaining place would answer the same way")
    func stopsWhenNoQuestionWouldTellThePlacesApart() async {
        // Four places, identical in every respect the app could ask about.
        let identical = candidates((1...4).map { restaurant("Same \($0)", attributes: [.quickService]) })
        let step = await AskNextQuestionsUseCase(generator: TemplateQuestionGenerator())
            .execute(narrowing: identical)

        #expect(step == .stop(.nothingLeftToAsk))
    }

    @Test("Discards a suggested question that would not narrow anything")
    func discardsASuggestedQuestionThatSplitsNothing() async throws {
        // Every candidate offers takeaway, so asking about it cannot change the outcome.
        let useless = LunchQuestion(attribute: .takeawayAvailable, text: "Taking it away?")
        let places = candidates([
            restaurant("A", attributes: [.takeawayAvailable, .quiet]),
            restaurant("B", attributes: [.takeawayAvailable, .quiet]),
            restaurant("C", attributes: [.takeawayAvailable, .lively]),
            restaurant("D", attributes: [.takeawayAvailable, .lively])
        ])

        let step = await AskNextQuestionsUseCase(generator: ScriptedQuestionGenerator(scripted: [useless]))
            .execute(narrowing: places)

        guard case .ask(let question) = step else {
            Issue.record("Expected the useless question to be replaced, not to stop the flow")
            return
        }
        #expect(question.attribute != .takeawayAvailable)
        #expect(question.splits(places))
    }

    @Test("Never repeats a question the diner has already answered")
    func neverRepeatsAQuestionAlreadyAnswered() async throws {
        let places = fiveMixedCandidates()
        let repeated = LunchQuestion(attribute: .quickService, text: "In a hurry today?")

        let step = await AskNextQuestionsUseCase(generator: ScriptedQuestionGenerator(scripted: [repeated]))
            .execute(narrowing: places, alreadyAsked: [repeated])

        guard case .ask(let question) = step else {
            Issue.record("Expected a different question rather than a stop")
            return
        }
        #expect(question.attribute != .quickService)
    }

    @Test("Still asks a sensible question when the question service is unreachable")
    func fallsBackToTheBuiltInQuestionsWhenTheServiceFails() async throws {
        let places = fiveMixedCandidates()
        let step = await AskNextQuestionsUseCase(generator: FailingQuestionGenerator())
            .execute(narrowing: places)

        guard case .ask(let question) = step else {
            Issue.record("A failed question service must not stop the diner from deciding")
            return
        }
        #expect(question.splits(places))
    }

    @Test("Prefers the question that divides the places most evenly")
    func prefersTheQuestionThatDividesThePlacesMostEvenly() async throws {
        // Four quiet, four lively — an even split. Only one is licensed — a poor question.
        let places = candidates([
            restaurant("A", attributes: [.quiet, .licensed]),
            restaurant("B", attributes: [.quiet]),
            restaurant("C", attributes: [.quiet]),
            restaurant("D", attributes: [.quiet]),
            restaurant("E", attributes: [.lively]),
            restaurant("F", attributes: [.lively]),
            restaurant("G", attributes: [.lively]),
            restaurant("H", attributes: [.lively])
        ])

        let ranked = TemplateQuestionGenerator().rankedQuestions(narrowing: places, alreadyAsked: [])

        #expect(ranked.first?.attribute == .quiet || ranked.first?.attribute == .lively)
        #expect(ranked.first?.attribute != .licensed)
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
        let question = LunchQuestion(attribute: .quickService, text: "In a hurry today?")

        let yes = try AnswerQuestionUseCase().execute(.yes, to: question, narrowing: places)
        let no = try AnswerQuestionUseCase().execute(.no, to: question, narrowing: places)

        #expect(yes.map(\.restaurant.name) == ["Quick One"])
        #expect(no.map(\.restaurant.name) == ["Sit Down"])
    }

    @Test("An answer is refused if it would leave the diner with nowhere to eat")
    func refusesAnAnswerThatWouldLeaveNothing() throws {
        let places = candidates([restaurant("Only Option", attributes: [.quickService])])
        let question = LunchQuestion(attribute: .outdoorSeating, text: "Fancy sitting outside?")

        #expect(throws: AnswerQuestionError.answerWouldRuleOutEverything(question: "Fancy sitting outside?")) {
            try AnswerQuestionUseCase().execute(.yes, to: question, narrowing: places)
        }
    }
}
