import Foundation
import os

/// What the app narrates about its own work, for whoever is watching the console.
///
/// Most of Ezypick's work is deliberately invisible: the fence rules restaurants out silently, and
/// when the question service fails the built-in generator answers in its place without a word to the
/// diner. That is right for the diner and useless for whoever is trying to understand a run, who
/// otherwise cannot tell a fallback from a success, or a fence from an empty neighbourhood.
///
/// Categories rather than one stream so the console can be filtered down to the stage in question.
/// In Xcode, filter the debug area on `ezypick`, or use Console.app and filter on the subsystem.
///
/// - Important: Values are logged `.public` on purpose. `Logger` redacts interpolated strings by
///   default, which is the right default for anything carrying a diner's data and the wrong one for
///   a restaurant name nobody needs protecting. Nothing here ever logs a key.
enum Diagnostics {
    static let subsystem = "ezypick"

    /// The places lookup: where it searched, what came back, what could not be mapped.
    static let places = Logger(subsystem: subsystem, category: "places")
    /// The silent fence: what each of the diner's limits cost them.
    static let fence = Logger(subsystem: subsystem, category: "fence")
    /// Question writing, including the prompt sent and whether the answer was usable.
    static let questions = Logger(subsystem: subsystem, category: "questions")
}
