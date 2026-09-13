import Foundation

/// A time of day on a 24-hour clock, used for lunch times and opening hours.
///
/// Stored as minutes since midnight so that comparisons are exact and free of
/// time-zone or calendar handling — a lunch decision never spans a date boundary.
public struct TimeOfDay: Equatable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let minutesSinceMidnight: Int

    public init(hour: Int, minute: Int) {
        self.minutesSinceMidnight = hour * 60 + minute
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h, minute: m)
    }

    public var hour: Int { minutesSinceMidnight / 60 }
    public var minute: Int { minutesSinceMidnight % 60 }

    public var description: String {
        String(format: "%d:%02d", hour, minute)
    }

    public static func < (a: TimeOfDay, b: TimeOfDay) -> Bool {
        a.minutesSinceMidnight < b.minutesSinceMidnight
    }

    // Decoded from "HH:MM" so the seeded catalogue reads like the API it mirrors.
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = TimeOfDay(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Expected a time of the form HH:MM, got \(text)"))
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%02d:%02d", hour, minute))
    }
}
