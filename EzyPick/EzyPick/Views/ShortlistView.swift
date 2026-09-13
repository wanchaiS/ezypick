import SwiftUI
import EzypickCore

/// The end of the trip: a named suggestion with its reason, and two alternatives.
///
/// The app commits to a pick rather than handing back a list, but it shows its working and leaves
/// the choice with the diner — they are the one who has to walk there and eat it.
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
        case .questionLimitReached: "That's as far as I'll ask — these are the best fits."
        case .nothingLeftToAsk: "These are alike enough that another question wouldn't help."
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
                Text("\(candidate.restaurant.cuisine.rawValue.capitalized) · $\(candidate.restaurant.pricePerHead) · \(candidate.restaurant.walkingMinutes) min")
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

/// What the diner sees when their own limits leave nothing to suggest.
///
/// It names the limit that did the damage and offers the way out, because a hungry person handed
/// "no results" will simply go back to their usual takeaway.
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
