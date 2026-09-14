import Foundation

/// One thing the app knows about the diner, sized to be read at a glance.
struct PreferenceBadge: Identifiable, Equatable {
    let text: String

    var id: String { text }

    /// Every badge for a saved profile: what the diner will spend and how far they will walk.
    static func all(for preferences: DiningPreferences) -> [PreferenceBadge] {
        [
            PreferenceBadge(text: "Up to $\(preferences.budgetPerHead)"),
            PreferenceBadge(text: "\(preferences.willingToWalkMinutes) min walk")
        ]
    }
}
