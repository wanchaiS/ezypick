import Foundation
import Combine
import EzypickCore

/// Drives the screen where the diner says what they can and cannot do.
///
/// Holds what the form currently shows and passes it to `SaveDiningPreferencesUseCase` when the
/// diner saves. No rule about what makes a profile usable lives here — that belongs to the use
/// case, so the same rule holds no matter which screen is in front of the diner.
@MainActor
final class DiningProfileViewModel: ObservableObject {
    @Published var dietaryRequirements: Set<DietaryConstraint> = []
    @Published var avoidedCuisines: Set<Cuisine> = []
    @Published var budgetPerHead = 25
    @Published var willingToWalkMinutes = 10
    @Published var mealHour = 12
    @Published var mealMinute = 30
    /// Optional. Without it the app still works, using its built-in questions.
    @Published var questionServiceKey = ""

    @Published var problem: String?
    @Published var howToFixIt: String?
    @Published var savedSuccessfully = false

    private let store: DiningPreferencesStore
    private let save: SaveDiningPreferencesUseCase

    init(store: DiningPreferencesStore) {
        self.store = store
        self.save = SaveDiningPreferencesUseCase(store: store)
        if let existing = store.load() { apply(existing) }
        questionServiceKey = UserDefaults.standard.string(forKey: Self.keyDefault) ?? ""
    }

    var preferences: DiningPreferences {
        DiningPreferences(dietaryRequirements: dietaryRequirements,
                          avoidedCuisines: avoidedCuisines,
                          budgetPerHead: budgetPerHead,
                          willingToWalkMinutes: willingToWalkMinutes,
                          usualMealTime: TimeOfDay(hour: mealHour, minute: mealMinute))
    }

    func toggle(_ requirement: DietaryConstraint) {
        if dietaryRequirements.contains(requirement) { dietaryRequirements.remove(requirement) }
        else { dietaryRequirements.insert(requirement) }
    }

    func toggle(_ cuisine: Cuisine) {
        if avoidedCuisines.contains(cuisine) { avoidedCuisines.remove(cuisine) }
        else { avoidedCuisines.insert(cuisine) }
    }

    /// Saves the profile, or shows the diner what stopped it and what to do instead.
    func saveProfile() {
        problem = nil; howToFixIt = nil
        do {
            try save.execute(preferences)
            UserDefaults.standard.set(questionServiceKey, forKey: Self.keyDefault)
            savedSuccessfully = true
        } catch let error as SaveDiningPreferencesError {
            problem = error.errorDescription
            howToFixIt = error.recoverySuggestion
        } catch {
            problem = "Your preferences could not be saved."
            howToFixIt = "Try again in a moment."
        }
    }

    private func apply(_ preferences: DiningPreferences) {
        dietaryRequirements = preferences.dietaryRequirements
        avoidedCuisines = preferences.avoidedCuisines
        budgetPerHead = preferences.budgetPerHead
        willingToWalkMinutes = preferences.willingToWalkMinutes
        mealHour = preferences.usualMealTime.hour
        mealMinute = preferences.usualMealTime.minute
    }

    static let keyDefault = "ezypick.questionServiceKey"
}
