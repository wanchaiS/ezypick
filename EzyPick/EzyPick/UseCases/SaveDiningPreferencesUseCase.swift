import Foundation

/// Records what the diner can and cannot do, so every later lunch can be decided without asking
/// again. These limits rule restaurants out silently, keeping the daily flow to a couple of taps.
///
/// - Important: Business rules — a profile is invalid if the budget per head is zero or less, or
///   the walk is outside one to twenty minutes.
struct SaveDiningPreferencesUseCase {
    private let store: DiningPreferencesStore

    init(store: DiningPreferencesStore) { self.store = store }

    /// - Throws: `SaveDiningPreferencesError` when the preferences could not produce a usable
    ///   search, such as a budget of zero.
    @discardableResult
    func execute(_ preferences: DiningPreferences) throws -> DiningPreferences {
        guard preferences.budgetPerHead > 0 else {
            throw SaveDiningPreferencesError.budgetNotSet
        }
        guard Self.walkingRange.contains(preferences.willingToWalkMinutes) else {
            throw SaveDiningPreferencesError.walkingTimeOutOfRange(allowed: Self.walkingRange)
        }
        try store.save(preferences)
        return preferences
    }

    /// Twenty minutes each way is already most of a lunch break spent walking.
    static let walkingRange = 1...20
}

/// What can go wrong while a diner is setting themselves up, written for the diner.
enum SaveDiningPreferencesError: LocalizedError, Equatable {
    /// The diner left the budget empty or set it to zero.
    case budgetNotSet
    /// The walking time is either meaningless or longer than a lunch break.
    case walkingTimeOutOfRange(allowed: ClosedRange<Int>)

    var errorDescription: String? {
        switch self {
        case .budgetNotSet:
            "Set what you're happy to spend on lunch, otherwise there's nothing to work with."
        case .walkingTimeOutOfRange(let allowed):
            "Walking time needs to be between \(allowed.lowerBound) and \(allowed.upperBound) minutes."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .budgetNotSet: "Enter a rough amount per head. You can change it any time."
        case .walkingTimeOutOfRange: "Ten minutes is about right for a CBD lunch break."
        }
    }
}
