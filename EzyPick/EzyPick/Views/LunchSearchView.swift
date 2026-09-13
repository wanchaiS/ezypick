import SwiftUI
import EzypickCore

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
            case .notStarted, .researching:
                ResearchView(tally: model.tally)
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

/// What the app is doing on the diner's behalf, shown rather than hidden behind a spinner.
///
/// This is the work a person would otherwise do themselves — checking menus, prices, opening hours
/// and distances — so it is worth a moment of their attention.
struct ResearchView: View {
    let tally: ExclusionTally?

    var body: some View {
        VStack(spacing: 18) {
            Text("Looking around").font(.title.bold())
            if let tally {
                VStack(alignment: .leading, spacing: 8) {
                    row("\(tally.consideredCount) places nearby", bold: true)
                    if tally.byDietary > 0 { row("− \(tally.byDietary) can't cater for you", note: "diet") }
                    if tally.byBudget > 0 { row("− \(tally.byBudget) over your budget", note: "budget") }
                    if tally.byDistance > 0 { row("− \(tally.byDistance) further than you'd walk", note: "distance") }
                    if tally.byOpeningHours > 0 { row("− \(tally.byOpeningHours) not serving then", note: "hours") }
                }
                .padding(.horizontal, 40)
            } else {
                ProgressView()
            }
            Text("Nothing unsafe or unaffordable gets as far as a question.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }

    private func row(_ text: String, bold: Bool = false, note: String? = nil) -> some View {
        HStack {
            Text(text).font(bold ? .body.weight(.semibold) : .body)
            Spacer()
            if let note { Text(note).font(.caption).foregroundStyle(.red) }
        }
    }
}

/// One yes-or-no question, with the split it is exploiting shown underneath.
///
/// The count of what is left is deliberately visible: it tells the diner their tap did something,
/// which is what makes answering a second one feel worth it.
struct QuestionView: View {
    let question: LunchQuestion
    let remaining: Int
    let number: Int
    let limit: Int
    let answer: (Answer) -> Void

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
