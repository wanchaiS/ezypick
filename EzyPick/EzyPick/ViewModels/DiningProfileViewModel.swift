import Foundation
import Combine

/// Drives the screen where the diner says what their lunch break allows.
///
/// - Note: What makes a profile usable is `SaveDiningPreferencesUseCase`'s rule, not this one's.
@MainActor
final class DiningProfileViewModel: ObservableObject {
    @Published var budgetPerHead = 25
    @Published var willingToWalkMinutes = 10

    /// How the home screen tells a budget a person chose from an untouched default.
    @Published private(set) var hasSavedProfile = false

    @Published var problem: String?
    @Published var howToFixIt: String?
    @Published var savedSuccessfully = false

    private let store: DiningPreferencesStore
    private let save: SaveDiningPreferencesUseCase

    init(store: DiningPreferencesStore) {
        self.store = store
        self.save = SaveDiningPreferencesUseCase(store: store)
        let existing = store.load()
        hasSavedProfile = existing != nil
        if let existing { apply(existing) }
    }

    var preferences: DiningPreferences {
        DiningPreferences(budgetPerHead: budgetPerHead,
                          willingToWalkMinutes: willingToWalkMinutes)
    }

    /// Saves the profile, or shows the diner what stopped it and what to do instead.
    func saveProfile() {
        problem = nil; howToFixIt = nil
        do {
            try save.execute(preferences)
            savedSuccessfully = true
            hasSavedProfile = true
        } catch let error as SaveDiningPreferencesError {
            problem = error.errorDescription
            howToFixIt = error.recoverySuggestion
        } catch {
            problem = "Your preferences could not be saved."
            howToFixIt = "Try again in a moment."
        }
    }

    private func apply(_ preferences: DiningPreferences) {
        budgetPerHead = preferences.budgetPerHead
        willingToWalkMinutes = preferences.willingToWalkMinutes
    }
}
