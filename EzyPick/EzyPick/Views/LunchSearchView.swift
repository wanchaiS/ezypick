import SwiftUI

/// One trip through deciding: the research, then the questions, then the shortlist.
///
/// A single screen that changes with the phase rather than a stack of pushes, because the diner is
/// doing one continuous thing and going "back" halfway through has no meaning.
struct LunchSearchView: View {
    @ObservedObject var model: LunchSearchViewModel
    let preferences: DiningPreferences

    var body: some View {
        Group {
            switch model.phase {
            case .notStarted, .lookingAround:
                LookingAroundView()
            case .results(let survey):
                PlacesFoundView(survey: survey,
                                places: model.candidates,
                                excluded: model.tally,
                                originName: model.originName) {
                    Task { await model.narrowItDown() }
                }
            case .thinking:
                ThinkingView(thinking: model.thinking)
            case .asking:
                if let question = model.question {
                    QuestionView(question: question,
                                 remaining: model.candidates.count,
                                 number: model.questionNumber,
                                 limit: model.questionLimit) { answer in
                        Task { await model.answer(answer) }
                    }
                }
            case .shortlist:
                ShortlistView(candidates: model.candidates,
                              stoppedBecause: model.stoppedBecause,
                              questionsAsked: model.askedSoFar.count) {
                    Task { await model.noneOfThese() }
                }
            case .notSetUp(let problem, let howToFixIt):
                NotSetUpView(placesFound: model.candidates.count,
                             problem: problem,
                             howToFixIt: howToFixIt)
            case .nothingFits(let problem, let howToFixIt):
                NothingFitsView(problem: problem, howToFixIt: howToFixIt) {
                    Task { await model.searchAgainAllowingOverBudget() }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.findLunch(for: preferences) }
    }
}

/// Shown while the search itself is running.
///
/// Separate from the research screen because they are different promises. This one says "I am
/// looking"; the research screen says "here is what I ruled out and why". Collapsing them would
/// leave the diner unable to tell a slow network from a strict budget.
struct LookingAroundView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Looking around you").font(.title2.bold())
            Text("Finding the places you could walk to right now.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// What the search found: the places that actually fit, by name.
///
/// The app has just done, in a couple of seconds, the legwork its whole premise is built on. Doing
/// that invisibly and jumping straight to a question would waste the one moment the diner can see
/// that the questions come from somewhere real, so narrowing is something they ask for rather than
/// something that happens to them.
///
/// Names rather than counts. Counts are true of anywhere: two different suburbs once summarised
/// identically here, down to the dollar, and nothing on screen could tell them apart. A name is the
/// cheapest proof that a search happened where somebody is standing.
struct PlacesFoundView: View {
    let survey: NearbySurvey
    /// The restaurants left after the diner's own limits, which is what the list names.
    let places: [CandidateRestaurant]
    /// What each limit cost, so the number above can be shown to add up.
    let excluded: ExclusionTally?
    /// The suburb, when it is known. The coordinate below it is shown either way.
    let originName: String?
    let narrowItDown: () -> Void

    /// What happened to everything that is not on the list.
    ///
    /// This line used to read "from 15 nearby, 6 open right now", which was true and read as a
    /// contradiction: six open, two listed, and nothing on screen accounting for the other four.
    /// Two counts from different denominators sitting next to each other invite a subtraction that
    /// gives the wrong answer. The tally is the one the app actually applied, limit by limit, and it
    /// reconciles exactly: what is listed is what is left.
    private var whatWentMissing: String {
        guard let excluded else { return "\(survey.count) nearby" }
        var reasons: [String] = []
        if excluded.byBudget > 0 { reasons.append("\(excluded.byBudget) over your budget") }
        if excluded.byDistance > 0 { reasons.append("\(excluded.byDistance) further than you'd walk") }
        if excluded.byOpeningHours > 0 { reasons.append("\(excluded.byOpeningHours) shut right now") }
        if excluded.byPreviousDecline > 0 { reasons.append("\(excluded.byPreviousDecline) you turned down") }
        guard !reasons.isEmpty else { return "all \(excluded.consideredCount) nearby, and all of them fit" }
        return "from \(excluded.consideredCount) nearby: " + reasons.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 16) {
            searchedFrom.padding(.top, 8)

            VStack(spacing: 2) {
                Text("\(places.count)").font(.system(size: 56, weight: .bold))
                Text(places.count == 1 ? "place fits what you told me" : "places fit what you told me")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Text(whatWentMissing)
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(places) { place in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text(place.restaurant.name)
                            Spacer(minLength: 8)
                            Text("\(place.restaurant.walkingMinutes) min")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 36)
            }

            Text("Help me pick one.")
                .font(.footnote).foregroundStyle(.secondary)

            Button(action: narrowItDown) {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
        }
    }

    /// Where the app looked, said plainly.
    ///
    /// The coordinate is shown as well as the suburb, and deliberately not hidden behind a tap.
    /// "Near you" is the one claim in this whole screen a diner cannot check, and on a simulator or
    /// with a stale fix it is also the claim most likely to be wrong. Six decimal places would be
    /// noise; four puts it within about ten metres, which is enough to recognise a street corner.
    private var searchedFrom: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill").font(.caption2)
                Text(originName ?? "Searching from your location")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.red)

            Text(String(format: "%.4f, %.4f", survey.origin.latitude, survey.origin.longitude))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

}

/// The model's reasoning, put on screen while it happens.
///
/// A spinner here would be a lie of omission. The app is not waiting on a network, it is reading
/// what other diners wrote about twenty restaurants to find the one thing they genuinely disagree
/// about, and that reading is the work the diner came for. It is also the only way anyone watching
/// can tell a service that answered from one that quietly fell back to the built-in questions.
struct ThinkingView: View {
    let thinking: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading the reviews").font(.title3.bold())
            }

            ScrollView {
                Text(thinking.isEmpty ? "Working out what is worth asking you." : thinking)
                    .font(.callout)
                    .foregroundStyle(thinking.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(.default, value: thinking)

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
    }
}

/// One yes-or-no question, with why it is being asked underneath.
///
/// The count of what is left is deliberately visible: it tells the diner their tap did something,
/// which is what makes answering a second one feel worth it.
///
/// The line underneath is the question's **own** reason, written alongside it. It used to be the
/// first sentence of the streamed thinking, which describes whatever the model considered first,
/// while the app goes on to ask whichever question splits the candidates most evenly. Those are
/// often not the same question, so a diner read one about pubs explained by a sentence about two
/// Italian places. A reason that explains a different question is worse than no reason.
struct QuestionView: View {
    let question: LunchQuestion
    let remaining: Int
    let number: Int
    let limit: Int
    let answer: (Answer) -> Void

    /// The reason, when whatever wrote the question gave one.
    private var reason: String? {
        let trimmed = question.because.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Text("\(remaining) places fit").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("question \(number) of \(limit) at most").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)

            Spacer()
            Text(question.text)
                .font(.system(size: 34, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            if let reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            Spacer()

            HStack(spacing: 48) {
                answerButton("No", filled: false) { answer(.no) }
                answerButton("Yes", filled: true) { answer(.yes) }
            }
            .padding(.bottom, 40)
        }
    }

    private func answerButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(width: 110, height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(filled ? .red : .gray.opacity(0.25))
        .foregroundStyle(filled ? .white : .primary)
    }
}
