import Testing
import Foundation
@testable import EzyPick

/// Where a model's words become app behaviour.
///
/// Everything else in the app either works or throws. Here a misread reply produces a perfectly
/// well formed question that filters the wrong restaurants, which nobody would notice on screen, so
/// the reading is worth testing directly. Nothing here reaches the network.
@Suite("Asking a language model for the next question")
struct LLMQuestionGeneratorTests {

    private func threePlaces() -> [CandidateRestaurant] {
        candidates([restaurant("First"), restaurant("Second"), restaurant("Third")])
    }

    @Test("The restaurants a yes keeps are the ones the model numbered")
    func resolvesTheModelsNumbersBackToRestaurants() async throws {
        let places = threePlaces()
        let written = try await modelSaying([
            "They split on pace. ",
            #"{"questions":[{"topic":"pace","text":"In a hurry?","yes":[1,3]}]}"#
        ]).questions(narrowing: places, alreadyAsked: [])

        let question = try #require(written.first)
        // One-based on the wire, zero-based in the array. An off-by-one here does not crash and
        // does not look wrong: it quietly keeps the restaurant next door to the one meant.
        #expect(question.keptByYes == [places[0].id, places[2].id])
        #expect(question.splits(places))
        #expect(question.text == "In a hurry?")
    }

    @Test("The thinking reaches the screen as it arrives, and stops where the JSON starts")
    func reportsTheReasoningAndNotTheJson() async throws {
        let heard = Heard()
        _ = try await modelSaying([
            "One is quick. ",
            "The others are places to sit. ",
            #"{"questions":[{"topic":"pace","text":"In a hurry?","yes":[2]}]}"#
        ]).questions(narrowing: threePlaces(), alreadyAsked: [], thinkingAloud: { heard.add($0) })

        #expect(heard.text == "One is quick. The others are places to sit. ")
        // The diner is being shown a train of thought. A brace landing mid-sentence turns it into
        // a readout of a wire format.
        #expect(!heard.text.contains("{"))
        #expect(heard.fragments.count > 1, "Reasoning arriving in one lump is a stream in name only")
    }

    @Test("A question carries the reason written with it, not the opening line of the thinking")
    func keepsTheReasonThatBelongsToEachQuestion() async throws {
        let written = try await modelSaying([
            "These places differ most in how long you would sit. ",
            #"{"questions":[{"topic":"pace","text":"In a hurry?","#
            + #""because":"Two are counter service, one is a sit-down room.","yes":[1]},"#
            + #"{"topic":"noise","text":"Somewhere quiet?","yes":[2]}]}"#
        ]).questions(narrowing: threePlaces(), alreadyAsked: [])

        // The app asks whichever question splits the candidates most evenly, which is often not the
        // one the thinking opened with, so a reason taken from the stream can explain a question
        // the diner is not being asked.
        #expect(written.first?.because == "Two are counter service, one is a sit-down room.")
        #expect(written.last?.because == "", "A question with no reason must not borrow another's")
    }

    @Test("A long review is cut down before it is paid for and imitated")
    func shortensReviewsBeforeSendingThem() {
        let review = """
            The food was excellent and the service was quick.

            I would happily come back, although the room is louder than it looks from outside and
            the tables near the door are draughty in winter, which is worth knowing in advance.
            """
        let shortened = LLMQuestionGenerator.shortened(review, to: 60)

        #expect(shortened.count <= 61, "Sent on every question, and the model mirrors what it is fed")
        #expect(!shortened.contains("\n"), "A review's paragraph breaks become the listing's")
        #expect(shortened.hasPrefix("The food was excellent"))
        #expect(shortened.hasSuffix("…"))
    }

    @Test("A number naming no restaurant is dropped rather than trusted")
    func ignoresNumbersThatNameNoRestaurant() async throws {
        let places = threePlaces()
        let written = try await modelSaying([
            #"{"questions":[{"topic":"pace","text":"In a hurry?","yes":[2,9]}]}"#
        ]).questions(narrowing: places, alreadyAsked: [])

        #expect(try #require(written.first).keptByYes == [places[1].id])
    }

    @Test("A question that keeps nothing is never offered as a question")
    func discardsAQuestionWithAnEmptyAnswerKey() async throws {
        let written = try await modelSaying([
            #"{"questions":[{"topic":"pace","text":"In a hurry?","yes":[]},"#
            + #"{"topic":"noise","text":"Somewhere quiet?","yes":[1]}]}"#
        ]).questions(narrowing: threePlaces(), alreadyAsked: [])

        #expect(written.map(\.topic) == ["noise"])
    }

    @Test("A reply with no JSON in it fails rather than quietly returning nothing")
    func refusesAReplyThatNeverAnswered() async {
        await #expect(throws: LLMQuestionGenerator.GenerationError.unreadableResponse) {
            try await modelSaying(["I had a think and decided not to answer."])
                .questions(narrowing: threePlaces(), alreadyAsked: [])
        }
    }

    @Test("A refused request is a failure, so the built-in questions can take over")
    func reportsARefusedRequest() async {
        await #expect(throws: LLMQuestionGenerator.GenerationError.modelUnavailable) {
            try await modelSaying([], status: 429)
                .questions(narrowing: threePlaces(), alreadyAsked: [])
        }
    }

    // MARK: Stubbing the service

    /// A generator talking to a service that streams back exactly these fragments.
    private func modelSaying(_ fragments: [String], status: Int = 200) -> LLMQuestionGenerator {
        let key = UUID().uuidString
        StubbedModel.register(.init(status: status, fragments: fragments), for: key)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubbedModel.self]
        return LLMQuestionGenerator(apiKey: key,
                                    endpoint: URL(string: "https://example.invalid/v1/chat/completions")!,
                                    session: URLSession(configuration: configuration))
    }
}

/// What the screen was told, gathered from the generator's reporting closure.
///
/// A class with a lock rather than a captured array: the closure is `@Sendable` and is called from
/// whichever thread the response arrives on.
private final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [String] = []

    func add(_ fragment: String) {
        lock.lock(); defer { lock.unlock() }
        received.append(fragment)
    }

    var fragments: [String] {
        lock.lock(); defer { lock.unlock() }
        return received
    }

    var text: String { fragments.joined() }
}

/// Answers the generator's one request with a server-sent event stream.
///
/// Each fragment is delivered as its own event and as its own load, so a generator that only
/// reports once everything has arrived fails the streaming test rather than passing it by accident.
private final class StubbedModel: URLProtocol {

    struct Script: Sendable {
        let status: Int
        let fragments: [String]
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var byKey: [String: Script] = [:]

        func register(_ script: Script, for key: String) {
            lock.lock(); defer { lock.unlock() }
            byKey[key] = script
        }

        func script(for key: String?) -> Script? {
            lock.lock(); defer { lock.unlock() }
            return key.flatMap { byKey[$0] }
        }
    }

    private static let registry = Registry()

    static func register(_ script: Script, for key: String) {
        registry.register(script, for: key)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let bearer = request.value(forHTTPHeaderField: "Authorization")?
            .replacingOccurrences(of: "Bearer ", with: "")
        guard let script = StubbedModel.registry.script(for: bearer), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: script.status,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "text/event-stream"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for fragment in script.fragments {
            client?.urlProtocol(self, didLoad: Data(Self.event(carrying: fragment).utf8))
        }
        client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// One chat-completion chunk, built the way the service builds it.
    private static func event(carrying fragment: String) -> String {
        let chunk = ["choices": [["delta": ["content": fragment]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: chunk),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "data: \(json)\n\n"
    }
}
