import Foundation

/// Holds on to one position fix so a single trip through the app asks once.
///
/// Two things need to know where the diner is: the search itself, and the screen that tells them
/// where it searched. Asking twice would mean two trips to the location hardware, and on a phone
/// being carried down a street the second answer is not the first one. The summary would then name
/// a corner the restaurants were not chosen from, which is a worse failure than not showing it at
/// all, because it looks authoritative.
///
/// - Important: Paired with `OneShotRestaurantCache` on purpose. Together they make one decision
///   equal one fix and one lookup, so everything the diner reads describes the same moment.
actor RememberedLocation: CurrentLocationProvider {
    private let source: any CurrentLocationProvider
    private var fix: Coordinate?

    init(_ source: any CurrentLocationProvider) {
        self.source = source
    }

    func currentCoordinate() async throws -> Coordinate {
        if let fix { return fix }
        let found = try await source.currentCoordinate()
        fix = found
        return found
    }

    /// Forgets where the diner was, so the next search finds them again.
    func startAgain() {
        fix = nil
    }
}
