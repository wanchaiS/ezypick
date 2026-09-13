import Foundation

/// Asks a language model to read what the remaining restaurants are actually like, and to write
/// questions that tell them apart.
///
/// The model is given the parts of a restaurant that no filter can use — the editorial blurb and
/// the review snippets — because that is the only thing here a query cannot already do. It is
/// given no authority: `AskNextQuestionsUseCase` checks every question it returns against the real
/// candidates and discards any that would not split them.
public struct LLMQuestionGenerator: QuestionGenerator {
    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let session: URLSession

    public init(apiKey: String,
                endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
                model: String = "gpt-4o-mini",
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    public func questions(narrowing candidates: [CandidateRestaurant],
                          alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": Self.brief],
                ["role": "user", "content": Self.describe(candidates, alreadyAsked: alreadyAsked)]
            ]
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GenerationError.modelUnavailable
        }
        return try Self.parse(data)
    }

    /// What the model is told. It may choose and phrase; it may not invent characteristics.
    static let brief = """
    You help someone choose where to eat lunch. You are given restaurants that already fit their     dietary needs, budget, walking distance and timing, so never ask about those. Pick the     characteristics where the restaurants most disagree and write up to three short yes/no     questions about them. Answer with JSON only, in the form     {"questions":[{"attribute":"quickService","text":"In a hurry today?"}]}. The attribute must be     one of: \(RestaurantAttribute.allCases.map(\.rawValue).joined(separator: ", ")).
    """

    static func describe(_ candidates: [CandidateRestaurant], alreadyAsked: [LunchQuestion]) -> String {
        let places = candidates.map { candidate in
            let r = candidate.restaurant
            return "- \(r.name) (\(r.cuisine.rawValue), $\(r.pricePerHead), \(r.walkingMinutes) min): "
                + "\(r.editorialSummary) Reviews: \(r.reviewSnippets.joined(separator: " | ")) "
                + "Tags: \(r.attributes.map(\.rawValue).sorted().joined(separator: ", "))"
        }.joined(separator: "\n")
        let asked = alreadyAsked.isEmpty ? "none" : alreadyAsked.map(\.text).joined(separator: " | ")
        return "Restaurants still in the running:\n\(places)\n\nAlready asked: \(asked)"
    }

    static func parse(_ data: Data) throws -> [LunchQuestion] {
        struct Envelope: Decodable { let choices: [Choice]
            struct Choice: Decodable { let message: Message }
            struct Message: Decodable { let content: String } }
        struct Payload: Decodable { let questions: [Item]
            struct Item: Decodable { let attribute: String; let text: String } }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let content = envelope.choices.first?.message.content,
              let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
              let payload = try? JSONDecoder().decode(Payload.self,
                  from: Data(content[start...end].utf8)) else {
            throw GenerationError.unreadableResponse
        }
        return payload.questions.compactMap { item in
            guard let attribute = RestaurantAttribute(rawValue: item.attribute) else { return nil }
            return LunchQuestion(attribute: attribute, text: item.text)
        }
    }

    public enum GenerationError: LocalizedError, Equatable {
        case modelUnavailable, unreadableResponse
        // Never shown: the use case falls back to the template generator and the diner sees a
        // question either way.
        public var errorDescription: String? { "Could not reach the question service." }
    }
}
