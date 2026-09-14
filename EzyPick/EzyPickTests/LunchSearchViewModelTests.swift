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

    @Test("Adjusting the settings re-fences the search already in hand, without paying for another")
    func newLimitsAreAppliedToTheSameSearch() async throws {
        let catalogue = CountingCatalogue([restaurant("Steakhouse", price: 60, opens: "00:00", closes: "23:59")])
        let search = LunchSearchViewModel(restaurants: catalogue,
                                          generator: UnconfiguredQuestionGenerator(),
                                          location: FixedLocation())

        await search.findLunch(for: preferences(budget: 25, walk: 30))
        #expect(nothingFits(search))

        // "Adjust settings", a bigger budget, and the sheet closing: the same trip, fenced again.
        await search.findLunch(for: preferences(budget: 70, walk: 30))
        #expect(search.candidates.count == 1)
        #expect(await catalogue.lookups == 1, "A settings change must not cost a second billed lookup")
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

/// Counts how many times the places were looked up, so the one-lookup claim can be proved.
private actor CountingCatalogue: RestaurantRepository {
    private let restaurants: [Restaurant]
    private(set) var lookups = 0

    init(_ restaurants: [Restaurant]) { self.restaurants = restaurants }

    func nearbyRestaurants() async throws -> [Restaurant] {
        lookups += 1
        return restaurants
    }
}
