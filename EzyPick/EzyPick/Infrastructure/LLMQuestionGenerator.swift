import Foundation

/// Asks a language model to read what the remaining restaurants are actually like, and to write a
/// question that tells them apart.
///
/// - Note: It has no authority. The model sees the blurb and review snippets no filter can use and
///   names the restaurants a yes would keep; `AskNextQuestionsUseCase` discards any question that
///   does not divide the candidates in front of the diner, or has been asked already.
struct LLMQuestionGenerator: QuestionGenerator {
    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let session: URLSession

    init(apiKey: String,
         endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
         model: String = "gpt-4o-mini",
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.session = session
    }

    func questions(narrowing candidates: [CandidateRestaurant],
                   alreadyAsked: [LunchQuestion]) async throws -> [LunchQuestion] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": Self.brief],
                ["role": "user", "content": Self.describe(candidates, alreadyAsked: alreadyAsked)]
            ]
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GenerationError.modelUnavailable
        }
        return try Self.parse(Self.reply(in: data), candidates: candidates)
    }

    /// The assistant's message out of a chat completion reply.
    static func reply(in data: Data) throws -> String {
        struct Completion: Decodable {
            let choices: [Choice]
            struct Choice: Decodable { let message: Message }
            struct Message: Decodable { let content: String }
        }
        guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
              let content = completion.choices.first?.message.content,
              !content.isEmpty else {
            throw GenerationError.unreadableResponse
        }
        return content
    }

    /// What the model is told.
    ///
    /// - Note: The length and single-question rules live in the prompt rather than in code, and the
    ///   JSON shape is placeholders rather than an example so no sample question sits in context.
    ///   The field names must be exact.
    static let brief = [
        "You help someone choose where to eat lunch.",
        "The restaurants listed already fit their budget, walking distance and are open now,",
        "so never ask about price, distance or opening hours.",
        "Read what each place is actually like, including the blurb and what reviewers say, and",
        "find where they most genuinely differ.",
        "Write JSON and nothing else, in this shape:",
        #"{"questions":[{"topic":"<one word>","text":"<the question>","#,
        #""because":"<one sentence>","yes":[<numbers>]}]}"#,
        "where yes lists the numbers of the restaurants a yes answer keeps",
        "and because is one short sentence naming what that question splits on.",
        "Every question must keep at least one restaurant and leave out at least one.",
        "Write three questions, best first, each on a different topic.",
        "Keep each question to ten words at most and ask one single thing:",
        "no lists of examples, and nothing joined by and or or.",
        "Ask how the diner feels rather than what a restaurant is.",
        "Never write anything like",
        #""Do you want a traditional pub atmosphere with classic comfort food and live music?"."#,
        "Questions must be answerable by someone who knows nothing about these restaurants:",
        "ask about what they want, never about a venue by name."
    ].joined(separator: " ")

    /// Everything known about the candidates, numbered so the model can point at them: the mapping
    /// back is an array index in `parse(_:candidates:)`.
    static func describe(_ candidates: [CandidateRestaurant], alreadyAsked: [LunchQuestion]) -> String {
        let places = candidates.enumerated().map { index, candidate in
            let r = candidate.restaurant
            let facts = "\(r.cuisine.spokenName), about $\(r.pricePerHead) a head, "
                + "\(r.walkingMinutes) min walk, rated \(String(format: "%.1f", r.rating)) by \(r.ratingCount)"
            let tags = r.attributes.isEmpty ? ""
                : " Listed as: \(r.attributes.map(\.rawValue).sorted().joined(separator: ", "))."
            let blurb = r.editorialSummary.isEmpty ? "" : " \(r.editorialSummary)"
            let reviews = r.reviewSnippets.isEmpty ? ""
                : " Reviews: \(r.reviewSnippets.map { "\"\(Self.shortened($0))\"" }.joined(separator: " "))"
            return "\(index + 1). \(r.name) (\(facts)).\(blurb)\(tags)\(reviews)"
        }.joined(separator: "\n")

        let asked = alreadyAsked.isEmpty ? "nothing yet"
            : alreadyAsked.map { "\($0.topic): \($0.text)" }.joined(separator: " | ")
        return "Restaurants still in the running:\n\(places)\n\nAlready asked about: \(asked)"
    }

    /// One review, cut to the part that says something: the model mirrors the register it is fed,
    /// and the first couple of sentences carry the character of a place.
    static func shortened(_ review: String, to limit: Int = 200) -> String {
        let flattened = review.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flattened.count > limit else { return flattened }
        let cut = flattened.prefix(limit)
        guard let lastSpace = cut.lastIndex(of: " ") else { return String(cut) + "…" }
        return String(cut[..<lastSpace]) + "…"
    }

    /// Turns the model's reply into questions, resolving its numbers back to real restaurants.
    ///
    /// - Note: A number naming no candidate is dropped, and a question left with no restaurants is
    ///   discarded here rather than rejected later by the use case.
    static func parse(_ content: String, candidates: [CandidateRestaurant]) throws -> [LunchQuestion] {
        struct Payload: Decodable {
            let questions: [Item]
            struct Item: Decodable { let topic: String; let text: String; let yes: [Int]
                let because: String? }
        }

        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
              start < end,
              let payload = try? JSONDecoder().decode(Payload.self,
                  from: Data(content[start...end].utf8)) else {
            throw GenerationError.unreadableResponse
        }

        return payload.questions.compactMap { item in
            let kept = item.yes.compactMap { number -> Restaurant.ID? in
                guard candidates.indices.contains(number - 1) else { return nil }
                return candidates[number - 1].id
            }
            guard !kept.isEmpty else { return nil }
            return LunchQuestion(topic: item.topic, text: item.text, keptByYes: Set(kept),
                                 because: item.because ?? "")
        }
    }

    enum GenerationError: LocalizedError, Equatable {
        case modelUnavailable, unreadableResponse
        // Never shown: the use case falls back to the template generator.
        var errorDescription: String? { "Could not reach the question service." }
    }
}
