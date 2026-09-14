import Foundation

/// Where the diner is standing right now.
///
/// - Important: The diner may refuse. An implementation must throw rather than invent a plausible
///   coordinate, since a silent fallback would recommend lunch in the wrong suburb.
protocol CurrentLocationProvider: Sendable {
    /// The diner's position, or an error explaining why it is unavailable.
    func currentCoordinate() async throws -> Coordinate
}
