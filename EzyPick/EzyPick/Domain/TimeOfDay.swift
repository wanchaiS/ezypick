import Foundation

/// A time of day on a 24-hour clock, used for lunch times and opening hours.
///
/// Stored as minutes since midnight: comparisons are exact, and a lunch decision never spans a
/// date boundary.
struct TimeOfDay: Equatable, Comparable, Codable, Sendable, CustomStringConvertible {
    let minutesSinceMidnight: Int

    init(hour: Int, minute: Int) {
        self.minutesSinceMidnight = hour * 60 + minute
    }

    init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h, minute: m)
    }

    var hour: Int { minutesSinceMidnight / 60 }
    var minute: Int { minutesSinceMidnight % 60 }

    /// The time on the diner's own clock, right now.
    ///
    /// - Important: Use cases still take the time as a parameter rather than reading this, so a
    ///   test never depends on when it runs.
    static var now: TimeOfDay {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    var description: String {
        String(format: "%d:%02d", hour, minute)
    }

    static func < (a: TimeOfDay, b: TimeOfDay) -> Bool {
        a.minutesSinceMidnight < b.minutesSinceMidnight
    }

    // Decoded from "HH:MM", the form the seeded catalogue and the places API both use.
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = TimeOfDay(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Expected a time of the form HH:MM, got \(text)"))
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%02d:%02d", hour, minute))
    }
}
