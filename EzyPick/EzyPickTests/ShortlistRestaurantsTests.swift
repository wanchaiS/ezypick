import Testing
import Foundation
@testable import EzyPick

/// The app's promise is that nothing it suggests is unsafe, unaffordable, shut or too far away.
/// These check each of those limits, including the boundaries where they take effect.
@Suite("Working out where the diner could actually eat")
struct ShortlistRestaurantsTests {

    @Test("A restaurant priced exactly at the budget is still affordable")
    func keepsRestaurantPricedExactlyAtTheBudget() async throws {
        let catalogue = StubCatalogue(restaurants: [restaurant("On The Nose", price: 25)])
        let shortlist = try await ShortlistRestaurantsUseCase(restaurants: catalogue)
            .execute(for: preferences(budget: 25), at: lunchtime)

        #expect(shortlist.candidates.count == 1)
    }

    @Test("A restaurant a dollar over the budget is ruled out")
    func excludesRestaurantOneDollarOverTheBudget() async throws {
        let catalogue = StubCatalogue(restaurants: [restaurant("Just Over", price: 26)])

        await #expect(throws: ShortlistRestaurantsError.self) {
            try await ShortlistRestaurantsUseCase(restaurants: catalogue)
                .execute(for: preferences(budget: 25), at: lunchtime)
        }
    }

    @Test("Lifting the budget deliberately brings the dearer places back")
    func includesOverBudgetRestaurantWhenTheDinerLiftsTheirBudget() async throws {
        let catalogue = StubCatalogue(restaurants: [restaurant("Just Over", price: 26)])
        let shortlist = try await ShortlistRestaurantsUseCase(restaurants: catalogue)
            .execute(for: preferences(budget: 25), at: lunchtime, allowingOverBudget: true)

        #expect(shortlist.candidates.count == 1)
    }

    @Test("A restaurant that closes before the diner eats is ruled out")
    func excludesRestaurantThatClosesBeforeTheMealTime() async throws {
        let catalogue = StubCatalogue(restaurants: [
            restaurant("Early Closer", closes: "12:00"),
            restaurant("Still Serving", closes: "15:00")
        ])
        let shortlist = try await ShortlistRestaurantsUseCase(restaurants: catalogue)
            .execute(for: preferences(), at: lunchtime)

        #expect(shortlist.candidates.map(\.restaurant.name) == ["Still Serving"])
        #expect(shortlist.excluded.byOpeningHours == 1)
    }

    @Test("A walk exactly as long as the diner will go is still acceptable")
    func keepsRestaurantExactlyAtTheWalkingLimit() async throws {
        let catalogue = StubCatalogue(restaurants: [
            restaurant("Ten Minutes", walk: 10),
            restaurant("Eleven Minutes", walk: 11)
        ])
        let shortlist = try await ShortlistRestaurantsUseCase(restaurants: catalogue)
            .execute(for: preferences(walk: 10), at: lunchtime)

        #expect(shortlist.candidates.map(\.restaurant.name) == ["Ten Minutes"])
        #expect(shortlist.excluded.byDistance == 1)
    }

    @Test("A restaurant turned down earlier is not offered again")
    func neverReOffersARestaurantTheDinerAlreadyTurnedDown() async throws {
        let declined = restaurant("Already Seen")
        let catalogue = StubCatalogue(restaurants: [declined, restaurant("Somewhere New")])
        let shortlist = try await ShortlistRestaurantsUseCase(restaurants: catalogue)
            .execute(for: preferences(), at: lunchtime, declining: [declined.id])

        #expect(shortlist.candidates.map(\.restaurant.name) == ["Somewhere New"])
        #expect(shortlist.excluded.byPreviousDecline == 1)
    }

    @Test("When nothing fits, the diner is told which limit caused it")
    func namesTheLimitResponsibleWhenNothingFits() async throws {
        // Three ruled out by budget, one by the walk: the diner needs to hear about the budget.
        let catalogue = StubCatalogue(restaurants: [
            restaurant("A", price: 99), restaurant("B", price: 99), restaurant("C", price: 99),
            restaurant("D", walk: 40)
        ])

        await #expect(throws: ShortlistRestaurantsError.nothingWithinReach({
            var tally = ExclusionTally()
            tally.consideredCount = 4
            tally.byBudget = 3
            tally.byDistance = 1
            return tally
        }())) {
            try await ShortlistRestaurantsUseCase(restaurants: catalogue)
                .execute(for: preferences(), at: lunchtime)
        }
    }

    @Test("The message a diner sees names the cause and a way out of it")
    func explainsTheFailureInWordsTheDinerCanAct0n() async throws {
        var tally = ExclusionTally()
        tally.byDistance = 7
        let error = ShortlistRestaurantsError.nothingWithinReach(tally)

        #expect(error.errorDescription == "The places that fit are all further than you said you'd walk.")
        #expect(error.recoverySuggestion == "Widen your walk to twenty minutes and try again.")
    }
}
