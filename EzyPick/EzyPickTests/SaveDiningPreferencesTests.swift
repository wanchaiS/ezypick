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

    @Test("A walk longer than a lunch break is refused")
    func refusesAWalkLongerThanALunchBreak() {
        #expect(throws: SaveDiningPreferencesError.walkingTimeOutOfRange(allowed: 1...20)) {
            try SaveDiningPreferencesUseCase(store: InMemoryPreferencesStore())
                .execute(preferences(walk: 45))
        }
    }

    @Test("Every refusal tells the diner what to do about it, not just what went wrong")
    func everyRefusalCarriesAWayOut() {
        let refusals: [SaveDiningPreferencesError] = [
            .budgetNotSet, .walkingTimeOutOfRange(allowed: SaveDiningPreferencesUseCase.walkingRange)
        ]

        for refusal in refusals {
            let cause = try! #require(refusal.errorDescription)
            let wayOut = try! #require(refusal.recoverySuggestion)
            #expect(cause != wayOut, "A refusal that repeats itself has not told the diner anything")
            #expect(!wayOut.contains("—"), "House style: no em dashes in what the diner reads")
        }
    }

    @Test("A profile saved before the dietary settings were removed still loads")
    func keepsTheProfileWhenSavedFieldsNoLongerExist() throws {
        let suite = "ezypick.tests.retired-fields"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let savedByAnOlderVersion = """
            {"dietaryRequirements":["halal","glutenFree"],"budgetPerHead":35,\
            "willingToWalkMinutes":12,"usualMealTime":"12:30"}
            """
        defaults.set(Data(savedByAnOlderVersion.utf8), forKey: "ezypick.diningPreferences")

        let loaded = try #require(UserDefaultsPreferencesStore(defaults: defaults).load())

        // A profile written by an older version carries three fields this one has never heard of.
        // They have to be ignored rather than refused: the store swallows a decode failure and
        // reports no saved profile at all, so a stricter reading would silently reset the budget
        // and walk the diner chose.
        #expect(loaded.budgetPerHead == 35)
        #expect(loaded.willingToWalkMinutes == 12)
    }
}
