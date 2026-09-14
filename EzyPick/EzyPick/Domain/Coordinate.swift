import Foundation

/// A point on the earth, in decimal degrees.
///
/// The domain needs somewhere to stand before it can ask what is nearby, and it needs that without
/// importing Core Location: this package is Foundation only, so the business rules build and test
/// on a machine with no device, no permissions dialog and no simulator. The app layer converts a
/// `CLLocation` into one of these at its boundary and nothing below that boundary knows the
/// difference.
struct Coordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
