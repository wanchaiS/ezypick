import Testing
import Foundation
@testable import EzyPick

/// Setting up is the one slow moment in the app, and the only place the diner can lock themselves
/// out of every possible suggestion. These check they are stopped before that happens.
@Suite("Saving what the diner can and cannot do")
struct SaveDiningPreferencesTests {

    @Test("A usable set of preferences is saved and kept")
    func savesPreferencesTheDinerCanActuallySearchWith() throws {
        let store = InMemoryPreferencesStore()
        let saved = try SaveDiningPreferencesUseCase(store: store)
            .execute(preferences(budget: 25, walk: 10))

        #expect(store.saved == saved)
        #expect(store.load()?.budgetPerHead == 25)
    }

    @Test("A budget of nothing is refused, because it would rule out every restaurant")
    func refusesABudgetOfNothing() {
        let store = InMemoryPreferencesStore()

        #expect(throws: SaveDiningPreferencesError.budgetNotSet) {
            try SaveDiningPreferencesUseCase(store: store).execute(preferences(budget: 0))
        }
        #expect(store.saved == nil)
    }

}
