import Foundation
import Combine

/// Drives the screen where the diner says what their lunch break allows.
///
/// Holds what the form currently shows and passes it to `SaveDiningPreferencesUseCase` when the
/// diner saves. No rule about what makes a profile usable lives here — that belongs to the use
/// case, so the same rule holds no matter which screen is in front of the diner.
@MainActor
final class DiningProfileViewModel: ObservableObject {
    @Published var budgetPerHead = 25
    @Published var willingToWalkMinutes = 10

    /// Whether the diner has ever saved a profile.
    ///
    /// The home screen needs this to tell "$25 a head, ten minutes" chosen by a person apart from
    /// the same values sitting there as untouched defaults, which would have the app
    /// claiming to know someone it has never met.
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
