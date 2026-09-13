import Foundation

/// Records what the diner can and cannot do, so that every later lunch can be decided without
/// asking again.
///
/// This is the only moment the app asks for anything slow. Everything the diner enters here is
/// used to rule restaurants out silently, which is what keeps the daily interaction down to a
/// couple of taps.
public struct SaveDiningPreferencesUseCase {
    private let store: DiningPreferencesStore

    public init(store: DiningPreferencesStore) { self.store = store }

    /// Validates and saves the diner's preferences.
    ///
    /// - Throws: `SaveDiningPreferencesError` when the preferences could not produce a usable
    ///   search — for example a budget of zero, which would rule out every restaurant in the city.
    @discardableResult
    public func execute(_ preferences: DiningPreferences) throws -> DiningPreferences {
        guard preferences.budgetPerHead > 0 else {
            throw SaveDiningPreferencesError.budgetNotSet
        }
        guard Self.walkingRange.contains(preferences.willingToWalkMinutes) else {
            throw SaveDiningPreferencesError.walkingTimeOutOfRange(allowed: Self.walkingRange)
        }
        guard preferences.avoidedCuisines.count < Cuisine.allCases.count else {
            throw SaveDiningPreferencesError.everyCuisineRuledOut
        }
        try store.save(preferences)
        return preferences
    }

    /// A lunch break sets the outer limit: beyond 45 minutes' walk there is no lunch left to eat.
    public static let walkingRange = 1...45
}

/// What can go wrong while a diner is setting themselves up, written for the diner rather than
/// for a developer.
public enum SaveDiningPreferencesError: LocalizedError, Equatable {
    /// The diner left the budget empty or set it to zero.
    case budgetNotSet
    /// The walking time is either meaningless or longer than a lunch break.
    case walkingTimeOutOfRange(allowed: ClosedRange<Int>)
    /// Every cuisine has been ruled out, so nothing could ever be suggested.
    case everyCuisineRuledOut

    public var errorDescription: String? {
        switch self {
        case .budgetNotSet:
            "Set what you're happy to spend on lunch, otherwise there's nothing to work with."
        case .walkingTimeOutOfRange(let allowed):
            "Walking time needs to be between \(allowed.lowerBound) and \(allowed.upperBound) minutes."
        case .everyCuisineRuledOut:
            "You've ruled out every kind of food, so there'd be nothing left to suggest."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .budgetNotSet: "Enter a rough amount per head — you can change it any time."
        case .walkingTimeOutOfRange: "Ten minutes is about right for a CBD lunch break."
        case .everyCuisineRuledOut: "Put a couple back and let the questions do the narrowing instead."
        }
    }
}
