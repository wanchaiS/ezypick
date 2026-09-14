import Foundation

/// A time of day on a 24-hour clock, used for lunch times and opening hours.
///
/// Stored as minutes since midnight so that comparisons are exact and free of
/// time-zone or calendar handling — a lunch decision never spans a date boundary.
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
    /// The app used to fence on a stored "usual meal time" of 12:30, which is a guess about a
    /// person rather than a fact about the day: at 3pm it would happily suggest a place that shut
    /// at two. Reading the clock is the only thing that makes "currently open" mean what it says.
    /// Every use case still takes the time as a parameter, so a test never depends on when it runs.
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

    // Decoded from "HH:MM" so the seeded catalogue reads like the API it mirrors.
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
