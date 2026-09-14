import Foundation

/// One thing the app knows about the diner, sized to be read at a glance.
///
/// The home screen used to state the profile as a sentence, which has to be read word by word to
/// find the one fact you were checking. A badge is recognised rather than read — the diner looks
/// once and confirms the app has them right.
///
/// Badges used to come in two kinds, drawn differently, because a dietary requirement was a hard
/// limit the app would never trade away while a budget and a walk are practical facts it weighs.
/// Both kinds were worth keeping apart while both existed. The dietary requirements are gone, no
/// data source having ever been able to answer them, so a single kind is now the honest drawing:
/// everything left on this card is a practical limit.
struct PreferenceBadge: Identifiable, Equatable {
    let text: String

    var id: String { text }

    /// Every badge for a saved profile.
    ///
    /// Two chips, which is the whole profile. A card you have to read is a card that failed.
    static func all(for preferences: DiningPreferences) -> [PreferenceBadge] {
        [
            PreferenceBadge(text: "Up to $\(preferences.budgetPerHead)"),
            PreferenceBadge(text: "\(preferences.willingToWalkMinutes) min walk")
        ]
    }
}
