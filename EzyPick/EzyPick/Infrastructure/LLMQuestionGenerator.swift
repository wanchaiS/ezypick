import Foundation
import os

/// Asks a language model to read what the remaining restaurants are actually like, and to write a
/// question that tells them apart.
///
/// The model is given everything the places lookup returned, including the parts no filter can use:
/// the editorial blurb and the review snippets. It is also asked to name, for each question, the
/// restaurants a yes would keep, so its answer is usable whether it noticed something in a boolean
/// or in a sentence a diner wrote.
///
/// It is given no authority. `AskNextQuestionsUseCase` checks that a question genuinely divides the
/// candidates in front of the diner and has not already been asked, and discards it otherwise.
///
/// The reply is streamed: the model is told to think in plain words first and answer in JSON last,
/// so the thinking can be put on screen while it happens instead of behind a spinner. That is not
/// decoration. The wait is the one moment the app is visibly doing the legwork it exists to do.
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
                          alreadyAsked: [LunchQuestion],
                          thinkingAloud: @escaping @Sendable (String) -> Void) async throws -> [LunchQuestion] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let brief = Self.brief
        let described = Self.describe(candidates, alreadyAsked: alreadyAsked)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.4,
            "stream": true,
            "messages": [
                ["role": "system", "content": brief],
                ["role": "user", "content": described]
            ]
        ])

        // Logged because a question that reads oddly is almost always explained by what the model
        // was told rather than by the model, and the prompt is otherwise assembled and thrown away
        // with nothing to inspect.
        //
        // A line at a time, because a single call could not carry it. `os_log` elides any string
        // argument over about a kilobyte, so the listing — nine venues and their reviews, six and a
        // half thousand characters — logged as literally "<…>". The log claimed to hold the full
        // prompt and held none of it, which is the exact failure this logging exists to catch.
        Diagnostics.questions.debug("""
            asking \(model, privacy: .public) at \(endpoint.absoluteString, privacy: .public)
            --- system ---
            """)
        Self.logInFull(brief)
        Diagnostics.questions.debug("--- user ---")
        for line in described.split(whereSeparator: \.isNewline) { Self.logInFull(String(line)) }

        let content = try await stream(request, reporting: thinkingAloud)
        let written = try Self.parse(content, candidates: candidates)
        Diagnostics.questions.info("""
            wrote \(written.count, privacy: .public): \
            \(written.map { "\($0.topic) \"\($0.text)\" keeps \($0.keptByYes.count)" }
                .joined(separator: " | "), privacy: .public)
            """)
        return written
    }

    /// Logs a string that is longer than one log entry can carry.
    ///
    /// `os_log` replaces any string argument over roughly a kilobyte with "<…>" rather than
    /// truncating it, so an oversized line is not shortened in the log, it is *absent* from it.
    static func logInFull(_ text: String, chunkedAt limit: Int = 800) {
        var rest = Substring(text)
        while !rest.isEmpty {
            let chunk = rest.prefix(limit)
            Diagnostics.questions.debug("\(String(chunk), privacy: .public)")
            rest = rest.dropFirst(chunk.count)
        }
    }

    /// Reads the streamed reply, forwarding the thinking as it arrives and returning the whole text.
    ///
    /// Only the words before the JSON begins are forwarded. The diner is being shown a train of
    /// thought, and a brace landing mid-sentence would turn it into a readout.
    private func stream(_ request: URLRequest,
                        reporting thinkingAloud: @escaping @Sendable (String) -> Void) async throws -> String {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Diagnostics.questions.error("question service refused with HTTP \(code, privacy: .public)")
            throw GenerationError.modelUnavailable
        }

        var content = ""
        var reported = 0
        // Timed because "the reasoning is on screen while it thinks" is only true if the service
        // actually sends it as it goes. A gateway that buffers the whole completion and flushes it
        // at the end satisfies every line of this code and shows the diner nothing.
        let startedAt = Date()
        var firstFragmentAfter: TimeInterval?
        for try await line in bytes.lines {
            guard let fragment = Self.fragment(from: line) else { continue }
            if fragment.isEmpty { break }
            content += fragment
            if firstFragmentAfter == nil { firstFragmentAfter = Date().timeIntervalSince(startedAt) }

            let thinking = content.prefix { $0 != "{" }
            if thinking.count > reported {
                thinkingAloud(String(thinking.dropFirst(reported)))
                reported = thinking.count
            }
        }

        guard !content.isEmpty else { throw GenerationError.unreadableResponse }
        Diagnostics.questions.info("""
            streamed \(content.count, privacy: .public) characters in \
            \(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) ms, \
            first arrived after \(Int((firstFragmentAfter ?? 0) * 1000), privacy: .public) ms, \
            \(reported, privacy: .public) characters of thinking shown to the diner
            """)
        return content
    }

    /// One chunk of text out of one server-sent event, or nil for the lines that carry none.
    ///
    /// Returns an empty string for the end of the stream, which is signalled by a sentinel rather
    /// than by the connection closing.
    static func fragment(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]" else { return "" }

        struct Chunk: Decodable {
            let choices: [Choice]
            struct Choice: Decodable { let delta: Delta }
            struct Delta: Decodable { let content: String? }
        }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)),
              let text = chunk.choices.first?.delta.content else { return nil }
        return text
    }

    /// What the model is told.
    ///
    /// The list of characteristics it may ask about is gone, and its absence is the point. That list
    /// could only ever contain what a places API asserts, so the model was being handed five
    /// booleans and asked to be interesting. It now reads the prose and says which restaurants its
    /// own question keeps, which is the only way a question about how somewhere *feels* can filter
    /// anything.
    ///
    /// The length rules are here rather than enforced in code, deliberately. Asked for one thing in
    /// ten words the model complies, and a rule that discarded long questions would throw away good
    /// ones to catch the occasional bad one. An earlier version of this brief simply lost the word
    /// "short" in a rewrite, which is how a diner ended up reading "Do you want a traditional pub
    /// atmosphere with classic comfort food and possible live music?" — three questions in one, and
    /// unanswerable by anyone who wants the pub but not the live music.
    ///
    /// The JSON shape is given as placeholders rather than a worked example, so there is no sample
    /// question sitting in the context for the model to reach for when the restaurants are dull.
    /// The field names still have to be exact, which placeholders keep visible.
    static let brief = [
        "You help someone choose where to eat lunch.",
        "The restaurants listed already fit their budget, walking distance and are open now,",
        "so never ask about price, distance or opening hours.",
        "Read what each place is actually like, including the blurb and what reviewers say, and",
        "find where they most genuinely differ.",
        "First write two or three short sentences of plain thinking about how these places differ.",
        "No lists and no headings, just the thinking.",
        "Then, on a new line, write JSON and nothing else, in this shape:",
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

    /// Everything known about the candidates, numbered so the model can point at them cheaply.
    ///
    /// Numbers rather than place ids: an id is twenty-odd opaque characters that costs tokens on the
    /// way in and invites a typo on the way back, and the mapping back is an array index here.
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

    /// One review, cut to the part that says something.
    ///
    /// Places returns reviews of any length, with their own paragraph breaks, and the full text was
    /// going over verbatim: nine venues came to six and a half thousand characters, most of it a
    /// stranger's account of the parking. Two effects, both bad. It is paid for on every question,
    /// and the model mirrors the register it is fed, so long florid reviews produced long florid
    /// questions. The first couple of sentences carry the character of a place; the rest is
    /// anecdote.
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
    /// A number that names no candidate is dropped rather than failing the reply, and a question
    /// left with no restaurants at all is discarded here: a question whose answer key is empty
    /// would be rejected by the use case anyway, and reporting it as a usable question first only
    /// makes the log harder to read.
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
        // Never shown: the use case falls back to the template generator and the diner sees a
        // question either way.
        var errorDescription: String? { "Could not reach the question service." }
    }
}
