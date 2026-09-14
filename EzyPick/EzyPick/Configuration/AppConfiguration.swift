import Foundation

/// The local settings the app reads once at launch: a places key, a search radius, and an optional
/// question-writing service.
///
/// - Important: Read from a `KEY=VALUE` file the build copies into the bundle as `env.txt`, never
///   from source. A fresh clone gets nil for every property, and the app says so rather than
///   inventing data: with no places key it refuses to search, and with no question service it
///   shows what it found and stops.
struct AppConfiguration {
    /// Read once, at launch: nothing re-reads the file, so a changed setting needs a fresh build.
    static let current = AppConfiguration()

    /// Google Places API (New). Absent means no restaurants at all, and the app says so.
    let googlePlacesAPIKey: String?

    let placesSearchRadiusMetres: Double

    /// Where the question service lives. Missing this or ``aiAPIKey`` means no questions at all.
    let aiBaseURL: URL?

    let aiAPIKey: String?

    /// Which model to ask for. Absent leaves the generator's own default in place.
    let aiModel: String?

    /// Radius used when the file says nothing, or something that is not a number. 1600 m is the
    /// furthest walk the profile editor allows, so the fence downstream is what runs out, not this.
    static let defaultSearchRadiusMetres: Double = 1600

    init(values: [String: String] = AppConfiguration.bundledValues()) {
        googlePlacesAPIKey = values["GOOGLE_PLACES_API_KEY"]
        placesSearchRadiusMetres = values["PLACES_SEARCH_RADIUS_METRES"].flatMap { Double($0) }
            ?? Self.defaultSearchRadiusMetres
        aiBaseURL = values["AI_BASE_URL"].flatMap { URL(string: $0) }
        aiAPIKey = values["AI_API_KEY"]
        aiModel = values["AI_MODEL"]
    }

    /// Reads `env.txt` out of the app bundle. Missing and unreadable both come back as no settings,
    /// because the caller does the same thing either way.
    static func bundledValues() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "env", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    /// Turns the file's text into settings: one `KEY=VALUE` per line.
    ///
    /// - Note: Blank and `#` lines are skipped, and the split is on the *first* `=` only, since a
    ///   key or a URL may contain one. An empty value counts as absent.
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let statement = line.trimmingCharacters(in: .whitespaces)
            guard !statement.isEmpty, !statement.hasPrefix("#"),
                  let separator = statement.firstIndex(of: "=") else { continue }

            let key = statement[..<separator].trimmingCharacters(in: .whitespaces)
            let value = statement[statement.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
        return values
    }
}
