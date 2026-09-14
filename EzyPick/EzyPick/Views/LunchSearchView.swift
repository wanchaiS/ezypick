import SwiftUI

/// One trip through deciding: the research, then the questions, then the shortlist.
struct LunchSearchView: View {
    @ObservedObject var model: LunchSearchViewModel
    @ObservedObject var profile: DiningProfileViewModel
    @State private var adjustingSettings = false

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
                ThinkingView()
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
                    adjustingSettings = true
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.findLunch(for: profile.preferences) }
        // Whatever the diner changed, the places found are already in hand, so the limits are
        // simply applied again. Cancelling changes nothing and costs nothing.
        .sheet(isPresented: $adjustingSettings) {
            Task { await model.findLunch(for: profile.preferences) }
        } content: {
            NavigationStack { DiningProfileView(model: profile) }
        }
    }
}

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

/// What the search found: the places that actually fit, named rather than counted, because a count
/// is true of anywhere.
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
    /// - Important: Reports the tally the app actually applied, limit by limit, so what is listed
    ///   is what is left. Counts from two different denominators invite a wrong subtraction.
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
    /// - Note: The coordinate is shown as well as the suburb, because "near you" is the one claim
    ///   on this screen a diner cannot check. Four decimal places puts it within about ten metres.
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

struct ThinkingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading the reviews").font(.title3.bold())
            }

            Text("Working out what is worth asking you.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
    }
}

/// One yes-or-no question, with why it is being asked underneath, and how many places are left.
///
/// - Important: The line underneath is the question's own reason, written alongside it, not the
///   model's first thought, which often explains a different question.
struct QuestionView: View {
    let question: LunchQuestion
    let remaining: Int
    let number: Int
    let limit: Int
    let answer: (Answer) -> Void

    /// Nil rather than empty: the template generator writes no reason, and a blank gap under the
    /// question reads as something that failed to load.
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
