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

}
