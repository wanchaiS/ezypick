import Testing
import Foundation
@testable import EzypickCore

/// Setting up is the one slow moment in the app, and the only place the diner can lock themselves
/// out of every possible suggestion. These check they are stopped before that happens.
@Suite("Saving what the diner can and cannot do")
struct SaveDiningPreferencesTests {

    @Test("A usable set of preferences is saved and kept")
    func savesPreferencesTheDinerCanActuallySearchWith() throws {
        let store = InMemoryPreferencesStore()
        let saved = try SaveDiningPreferencesUseCase(store: store)
            .execute(preferences(dietary: [.glutenFree], budget: 25, walk: 10))

        #expect(store.saved == saved)
        #expect(store.load()?.dietaryRequirements == [.glutenFree])
    }

    @Test("A budget of nothing is refused, because it would rule out every restaurant")
    func refusesABudgetOfNothing() {
        let store = InMemoryPreferencesStore()

        #expect(throws: SaveDiningPreferencesError.budgetNotSet) {
            try SaveDiningPreferencesUseCase(store: store).execute(preferences(budget: 0))
        }
        #expect(store.saved == nil)
    }

    @Test("A walk longer than a lunch break is refused")
    func refusesAWalkLongerThanALunchBreak() {
        #expect(throws: SaveDiningPreferencesError.walkingTimeOutOfRange(allowed: 1...45)) {
            try SaveDiningPreferencesUseCase(store: InMemoryPreferencesStore())
                .execute(preferences(walk: 90))
        }
    }

    @Test("Ruling out every kind of food is refused")
    func refusesToRuleOutEveryKindOfFood() {
        #expect(throws: SaveDiningPreferencesError.everyCuisineRuledOut) {
            try SaveDiningPreferencesUseCase(store: InMemoryPreferencesStore())
                .execute(preferences(avoiding: Set(Cuisine.allCases)))
        }
    }

    @Test("The refusal tells the diner what to do about it")
    func explainsHowToFixAnUnusableBudget() {
        let error = SaveDiningPreferencesError.budgetNotSet

        #expect(error.errorDescription == "Set what you're happy to spend on lunch, otherwise there's nothing to work with.")
        #expect(error.recoverySuggestion == "Enter a rough amount per head — you can change it any time.")
    }
}
