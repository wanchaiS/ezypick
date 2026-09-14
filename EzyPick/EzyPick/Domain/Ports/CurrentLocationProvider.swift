import Foundation

/// Where the diner is standing right now.
///
/// A port rather than a direct Core Location call, for the same reason restaurants come from a
/// port: the business rules are about lunch, not about authorisation prompts. The app target
/// supplies the real implementation; a test supplies a fixed corner of the Sydney CBD and the
/// rules cannot tell them apart.
///
/// - Important: The diner may refuse. An implementation is expected to throw rather than invent a
///   plausible coordinate, because a silent fallback to an office address would quietly recommend
///   lunch in the wrong suburb.
protocol CurrentLocationProvider: Sendable {
    /// The diner's position, or an error explaining why it is unavailable.
    func currentCoordinate() async throws -> Coordinate
}
