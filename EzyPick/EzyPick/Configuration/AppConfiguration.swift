import Foundation

/// The local settings the app reads once at launch: a places key, how far to search, and an
/// optional question-writing service.
///
/// Read from a plain `KEY=VALUE` file that the build copies into the app bundle as `env.txt`,
/// never from source, so nothing here is ever committed. The file lives at the repository root as
/// `.env` and is excluded by `.gitignore`.
///
/// - Important: a missing file is the normal case, not an error. Someone who clones the repository
///   gets no `env.txt` at all, every property below comes back nil, and the app runs exactly as it
///   did before any of this existed: the seeded catalogue instead of live places, and the built-in
///   question generator instead of a service. Nothing warns, because nothing is wrong.
struct AppConfiguration {
    /// The configuration the running app was launched with.
    static let current = AppConfiguration()

    /// Key for Google Places API (New). Absent means the seeded catalogue.
    let googlePlacesAPIKey: String?

    /// How far out from the diner to search, in metres.
    let placesSearchRadiusMetres: Double

    /// Where the question-writing service lives. Both this and ``aiAPIKey`` are needed before it
    /// is used at all.
    let aiBaseURL: URL?

    /// Credential for the question-writing service.
    let aiAPIKey: String?

    /// Which model to ask for, when the service offers a choice. Absent leaves the generator's own
    /// default in place.
    let aiModel: String?

    /// The radius used when the file says nothing, or says something that is not a number.
    ///
    /// 1600 m is roughly the twenty-minute walk that is the furthest the profile editor lets
    /// anyone ask for, so the fence downstream is never the thing that ran out of candidates.
    static let defaultSearchRadiusMetres: Double = 1600

    init(values: [String: String] = AppConfiguration.bundledValues()) {
        googlePlacesAPIKey = values["GOOGLE_PLACES_API_KEY"]
        placesSearchRadiusMetres = values["PLACES_SEARCH_RADIUS_METRES"].flatMap { Double($0) }
            ?? Self.defaultSearchRadiusMetres
        aiBaseURL = values["AI_BASE_URL"].flatMap { URL(string: $0) }
        aiAPIKey = values["AI_API_KEY"]
        aiModel = values["AI_MODEL"]
    }

    /// Reads `env.txt` out of the app bundle, or reports that there was nothing to read.
    ///
    /// Both the missing file and the unreadable file come back as no settings, because the caller
    /// does the same thing either way and there is nobody to tell.
    static func bundledValues() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "env", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    /// Turns the file's text into settings: one `KEY=VALUE` per line.
    ///
    /// Blank lines and lines starting with `#` are skipped, so the file can explain itself to the
    /// next person who opens it. The split is on the *first* `=` only, because a key or a URL may
    /// well contain one. Keys and values are trimmed, and an empty value is treated as absent
    /// rather than as an empty string, which is what makes commenting a setting out and blanking
    /// it mean the same thing.
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
