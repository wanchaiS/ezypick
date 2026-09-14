import Foundation

/// A point on the earth, in decimal degrees.
///
/// - Note: Foundation only, so the domain never imports Core Location. The app layer converts a
///   `CLLocation` into one of these at its boundary.
struct Coordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
