import Testing
import Foundation
@testable import EzyPick

/// The screen state that carries a decision from the first tap to the shortlist.
///
/// Only the things that survive *between* trips are checked here. Everything about which
/// restaurants fit belongs to the use cases and is tested there against no view at all.
@MainActor
@Suite("Carrying one lunch decision, and only one")
struct LunchSearchViewModelTests {

    /// Open right through the day, because the view model reads the real clock: a venue with lunch
    /// hours would make this suite pass in the morning and fail after three.
    private func model(_ restaurants: [Restaurant]) -> LunchSearchViewModel {
        LunchSearchViewModel(restaurants: StubCatalogue(restaurants: restaurants),
                             generator: UnconfiguredQuestionGenerator(),
                             location: FixedLocation())
    }

    private func nothingFits(_ model: LunchSearchViewModel) -> Bool {
        if case .nothingFits = model.phase { return true }
        return false
    }

    @Test("Spending more than you said is allowed for today, not for every trip after it")
    func aLiftedBudgetDoesNotSurviveTheTripThatLiftedIt() async throws {
        let search = model([restaurant("Steakhouse", price: 60, opens: "00:00", closes: "23:59")])
        let tight = preferences(budget: 25, walk: 30)

        await search.findLunch(for: tight)
        #expect(nothingFits(search))

        // The diner decides to spend more today, and the one venue comes back.
        await search.searchAgainAllowingOverBudget()
        #expect(search.candidates.count == 1)

        // Today ends when they go home and start again. The cap they set is a cap again.
        search.startOver()
        await search.findLunch(for: tight)
        #expect(nothingFits(search))
    }

    @Test("A place turned down in one decision is offered again in the next one")
    func decliningRulesAVenueOutOfThatDecisionOnly() async throws {
        let search = model([restaurant("Ramen Bar", price: 20, opens: "00:00", closes: "23:59")])

        await search.findLunch(for: preferences(walk: 30))
        #expect(search.candidates.count == 1)

        // "None of these" rules it out of the rest of this decision, and the search runs dry.
        await search.noneOfThese()
        #expect(nothingFits(search))

        // Not out of lunch forever, though. Tomorrow's diner has never seen it.
        search.startOver()
        await search.findLunch(for: preferences(walk: 30))
        #expect(search.candidates.count == 1)
    }
}
