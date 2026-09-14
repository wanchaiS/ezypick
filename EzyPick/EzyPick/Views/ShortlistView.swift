import SwiftUI

/// The end of the trip: the pick with its reason, and the alternatives behind it.
struct ShortlistView: View {
    let candidates: [CandidateRestaurant]
    let stoppedBecause: StopReason?
    let questionsAsked: Int
    let noneOfThese: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(candidates.count == 1 ? "Here's your spot" : "\(candidates.count) spots for you")
                .font(.title.bold()).foregroundStyle(.red)
            if let explanation { Text(explanation).font(.caption).foregroundStyle(.secondary) }

            if let pick = candidates.first {
                topPick(pick)
            }

            if candidates.count > 1 {
                Text("Or one of these").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                ForEach(candidates.dropFirst()) { candidate in
                    alternative(candidate)
                }
            }

            Spacer()
            Button("None of these", action: noneOfThese)
                .font(.subheadline).padding(.bottom, 24)
        }
        .padding(.top, 12)
    }

    /// Why the app stopped asking, in the diner's terms.
    private var explanation: String? {
        switch stoppedBecause {
        case .fewEnoughLeft:
            questionsAsked == 0 ? "Only these fit what you told me." : "Narrowed down in \(questionsAsked) question\(questionsAsked == 1 ? "" : "s")."
        case .questionLimitReached: "That's as far as I'll ask. These are the best fits."
        case .nothingLeftToAsk: "These are alike enough that another question wouldn't help."
        // Never drawn: without a question service the search stops on its own screen and no
        // shortlist is assembled. Named rather than defaulted so a new stop reason makes the
        // compiler ask what the diner should be told.
        case .noQuestionService: nil
        case nil: nil
        }
    }

    private func topPick(_ candidate: CandidateRestaurant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MY PICK").font(.caption2.weight(.bold)).foregroundStyle(.red)
            Text(candidate.restaurant.name).font(.title2.bold())
            Text(candidate.restaurant.editorialSummary).font(.footnote).foregroundStyle(.secondary)
            Text(candidate.recommendationReason).font(.footnote)
            Link("Directions", destination: directions(to: candidate.restaurant))
                .font(.headline).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.red, lineWidth: 2))
        .padding(.horizontal, 24)
    }

    private func alternative(_ candidate: CandidateRestaurant) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.restaurant.name).font(.headline)
                Text("\(candidate.restaurant.cuisine.spokenName) · $\(candidate.restaurant.pricePerHead) · \(candidate.restaurant.walkingMinutes) min")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Link("Directions", destination: directions(to: candidate.restaurant)).font(.caption)
        }
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .padding(.horizontal, 24)
    }

    private func directions(to restaurant: Restaurant) -> URL {
        let query = restaurant.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "http://maps.apple.com/?q=\(query)&dirflg=w")!
    }
}

/// What the diner sees when their own limits leave nothing to suggest: the limit that did the
/// damage, and the way out of it.
struct NothingFitsView: View {
    let problem: String
    let howToFixIt: String
    let searchAgainAllowingOverBudget: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Nothing fits today").font(.title2.bold())
            Text(problem).multilineTextAlignment(.center)
            Text(howToFixIt).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Spend a bit more today", action: searchAgainAllowingOverBudget)
                .buttonStyle(.borderedProminent).tint(.red).padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

/// What the diner sees when the app found them places but cannot narrow them down.
///
/// - Important: Deliberately not `NothingFitsView`, whose "Nothing fits today" heading and offer
///   to spend more are both false here.
struct NotSetUpView: View {
    let placesFound: Int
    let problem: String
    let howToFixIt: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(placesFound == 1 ? "Found 1 place, can't narrow it" : "Found \(placesFound) places, can't narrow them")
                .font(.title2.bold()).multilineTextAlignment(.center)
            Text(problem).multilineTextAlignment(.center)
            Text(howToFixIt).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
