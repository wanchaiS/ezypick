import SwiftUI
import EzypickCore

/// Builds the app's parts and hands them to the first screen.
///
/// The only place that knows which implementations are in use: a seeded catalogue rather than a
/// live places API, `UserDefaults` rather than a database, and a language model only if the diner
/// has supplied a key. Nothing below this line knows the difference.
@main
struct EzyPickApp: App {
    private let store = UserDefaultsPreferencesStore()
    private let restaurants: RestaurantRepository
    private let generator: QuestionGenerator

    init() {
        restaurants = (try? SeededRestaurantCatalogue()) ?? EmptyCatalogue()
        let key = UserDefaults.standard.string(forKey: DiningProfileViewModel.keyDefault) ?? ""
        generator = key.isEmpty ? TemplateQuestionGenerator() : LLMQuestionGenerator(apiKey: key)
    }

    var body: some Scene {
        WindowGroup {
            HomeView(store: store, restaurants: restaurants, generator: generator)
        }
    }
}

/// Stands in when the bundled catalogue cannot be read, so the app still launches and can say so.
private struct EmptyCatalogue: RestaurantRepository {
    func nearbyRestaurants() async throws -> [Restaurant] { [] }
}
