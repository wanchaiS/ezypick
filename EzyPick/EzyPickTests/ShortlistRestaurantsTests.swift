import Testing
import Foundation
@testable import EzyPick

/// The app's promise is that nothing it suggests is unsafe, unaffordable, shut or too far away.
/// These check each of those limits, including the boundaries where they take effect.
@Suite("Working out where the diner could actually eat")
struct ShortlistRestaurantsTests {

    @Test("A restaurant priced exactly at the budget is still affordable")
    func keepsRestaurantPricedExactlyAtTheBudget() throws {
        let places = [restaurant("On The Nose", price: 25)]
        let shortlist = try ShortlistRestaurantsUseCase()
            .execute(from: places, for: preferences(budget: 25), at: lunchtime)

        #expect(shortlist.candidates.count == 1)
    }

    @Test("A restaurant a dollar over the budget is ruled out")
    func excludesRestaurantOneDollarOverTheBudget() throws {
        let places = [restaurant("Just Over", price: 26)]

        #expect(throws: ShortlistRestaurantsError.self) {
            try ShortlistRestaurantsUseCase()
                .execute(from: places, for: preferences(budget: 25), at: lunchtime)
        }
    }

    @Test("Lifting the budget deliberately brings the dearer places back")
    func includesOverBudgetRestaurantWhenTheDinerLiftsTheirBudget() throws {
        let places = [restaurant("Just Over", price: 26)]
        let shortlist = try ShortlistRestaurantsUseCase()
            .execute(from: places, for: preferences(budget: 25), at: lunchtime, allowingOverBudget: true)

        #expect(shortlist.candidates.count == 1)
    }

    @Test("A restaurant that closes before the diner eats is ruled out")
    func excludesRestaurantThatClosesBeforeTheMealTime() throws {
        let places = [
            restaurant("Early Closer", closes: "12:00"),
            restaurant("Still Serving", closes: "15:00")
        ]
        let shortlist = try ShortlistRestaurantsUseCase()
            .execute(from: places, for: preferences(), at: lunchtime)

        #expect(shortlist.candidates.map(\.restaurant.name) == ["Still Serving"])
        #expect(shortlist.excluded.byOpeningHours == 1)
    }

    @Test("A walk exactly as long as the diner will go is still acceptable")
    func keepsRestaurantExactlyAtTheWalkingLimit() throws {
        let places = [
            restaurant("Ten Minutes", walk: 10),
            restaurant("Eleven Minutes", walk: 11)
        ]
        let shortlist = try ShortlistRestaurantsUseCase()
            .execute(from: places, for: preferences(walk: 10), at: lunchtime)

        #expect(shortlist.candidates.map(\.restaurant.name) == ["Ten Minutes"])
        #expect(shortlist.excluded.byDistance == 1)
    }

    @Test("A restaurant turned down earlier is not offered again")
    func neverReOffersARestaurantTheDinerAlreadyTurnedDown() throws {
        let declined = restaurant("Already Seen")
        let places = [declined, restaurant("Somewhere New")]
        let shortlist = try ShortlistRestaurantsUseCase()
            .execute(from: places, for: preferences(), at: lunchtime, declining: [declined.id])

        #expect(shortlist.candidates.map(\.restaurant.name) == ["Somewhere New"])
        #expect(shortlist.excluded.byPreviousDecline == 1)
    }

    @Test("When nothing fits, the diner is told which limit caused it")
    func namesTheLimitResponsibleWhenNothingFits() throws {
        // Three ruled out by budget, one by the walk: the diner needs to hear about the budget.
        let places = [
            restaurant("A", price: 99), restaurant("B", price: 99), restaurant("C", price: 99),
            restaurant("D", walk: 40)
        ]

        #expect(throws: ShortlistRestaurantsError.nothingWithinReach({
            var tally = ExclusionTally()
            tally.consideredCount = 4
            tally.byBudget = 3
            tally.byDistance = 1
            return tally
        }())) {
            try ShortlistRestaurantsUseCase()
                .execute(from: places, for: preferences(), at: lunchtime)
        }
    }

    @Test("The message a diner sees names the cause and a way out of it")
    func explainsTheFailureInWordsTheDinerCanAct0n() throws {
        var tally = ExclusionTally()
        tally.byDistance = 7
        let error = ShortlistRestaurantsError.nothingWithinReach(tally)

        #expect(error.errorDescription == "The places that fit are all further than you said you'd walk.")
        #expect(error.recoverySuggestion == "Widen your walk to twenty minutes and try again.")
    }
}
