import Foundation

/// Restaurants from Google Places API (New), centred on wherever the diner is standing.
///
/// The live half of `RestaurantRepository`. The diner's own limits stay client-side, in
/// `ShortlistRestaurantsUseCase`.
///
/// - Important: `includedPrimaryTypes`, never `includedTypes`. `types[]` widens sideways across
///   anything that sells food, so `includedTypes: ["restaurant"]` returns supermarkets and hotels.
/// - Important: Never send `priceLevels`, `minRating` or `openNow`. Nearby Search accepts all
///   three with HTTP 200 and silently ignores them, so a fence built on them looks like it works
///   and filters nothing. Those limits are applied client-side.
struct GooglePlacesRestaurantRepository: RestaurantRepository {
    private let apiKey: String
    private let location: any CurrentLocationProvider
    private let searchRadiusMetres: Double
    private let session: URLSession

    /// - Parameters:
    ///   - searchRadiusMetres: default is the twenty minute walk the profile editor caps at.
    ///   - session: injected so tests can answer without a network.
    init(apiKey: String,
                location: any CurrentLocationProvider,
                searchRadiusMetres: Double = 1600,
                session: URLSession = .shared) {
        self.apiKey = apiKey
        self.location = location
        self.searchRadiusMetres = searchRadiusMetres
        self.session = session
    }

    /// Every operating, priced restaurant within the search radius of the diner.
    ///
    /// - Throws: `PlacesLookupError`, or the `LocationError` from finding the diner, left as it is:
    ///   someone who refused location access must be told about location, not about restaurants.
    func nearbyRestaurants() async throws -> [Restaurant] {
        let origin = try await location.currentCoordinate()

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.searchBody(around: origin, radiusMetres: searchRadiusMetres))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlacesLookupError.placesUnavailable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlacesLookupError.placesUnavailable
        }
        guard let payload = try? JSONDecoder().decode(Places.NearbyResponse.self, from: data) else {
            throw PlacesLookupError.unreadableResponse
        }

        let restaurants = Self.restaurants(in: payload, from: origin, on: Date())
        guard !restaurants.isEmpty else { throw PlacesLookupError.nothingNearby }
        return restaurants
    }

    static let endpoint = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!

    /// Exactly what is read below: Places bills per field at the highest tier in the mask.
    static let fieldMask = [
        "places.id", "places.displayName", "places.primaryType", "places.types",
        "places.priceLevel", "places.priceRange", "places.rating", "places.userRatingCount",
        "places.businessStatus", "places.location",
        "places.currentOpeningHours", "places.regularOpeningHours",
        "places.editorialSummary", "places.reviews",
        "places.dineIn", "places.takeout", "places.reservable", "places.outdoorSeating",
        "places.servesBeer", "places.servesWine",
        "places.servesCocktails",
        "routingSummaries"
    ].joined(separator: ",")

    /// The request body. `routingParameters` annotates rather than filters, and is the only source
    /// of a walking time.
    static func searchBody(around origin: Coordinate, radiusMetres: Double) -> [String: Any] {
        let centre: [String: Double] = ["latitude": origin.latitude, "longitude": origin.longitude]
        let circle: [String: Any] = ["center": centre, "radius": radiusMetres]
        let routing: [String: Any] = ["origin": centre, "travelMode": "WALK"]
        return [
            "includedPrimaryTypes": ["restaurant"],
            "maxResultCount": 20,
            "locationRestriction": ["circle": circle],
            "routingParameters": routing
        ]
    }
}

// MARK: - Turning places into restaurants

extension GooglePlacesRestaurantRepository {

    /// Maps a decoded response onto the domain, dropping anything the app cannot honestly offer.
    ///
    /// - Important: `routingSummaries` is a parallel top-level array aligned by index with
    ///   `places[]`, not a field inside each place. Zip by position in the source array: a dropped
    ///   venue must not shift the walking times after it.
    static func restaurants(in payload: Places.NearbyResponse,
                            from origin: Coordinate,
                            on date: Date) -> [Restaurant] {
        let places = payload.places ?? []
        let routes = payload.routingSummaries ?? []
        let weekday = gregorianWeekday(of: date)

        return places.enumerated().compactMap { index, place in
            // A truncated or absent summaries array is not worth a crash: an unrouted venue falls
            // back to straight-line distance below.
            let route = index < routes.count ? routes[index] : nil
            return restaurant(from: place, route: route, origin: origin, weekday: weekday)
        }
    }

    /// One venue, or `nil` when it is not something the app is willing to suggest: dropped when
    /// not `OPERATIONAL`, or when it has no price to check a budget against.
    static func restaurant(from place: Places.Place,
                           route: Places.RoutingSummary?,
                           origin: Coordinate,
                           weekday: Int) -> Restaurant? {
        guard let id = place.id,
              let name = place.displayName?.text, !name.isEmpty,
              place.businessStatus == "OPERATIONAL",
              let price = pricePerHead(of: place) else { return nil }

        let hours = tradingHours(of: place, on: weekday)
        return Restaurant(id: Restaurant.ID(id),
                          name: name,
                          cuisine: cuisine(of: place),
                          pricePerHead: price,
                          rating: place.rating ?? 0,
                          ratingCount: place.userRatingCount ?? 0,
                          walkingMinutes: walkingMinutes(route: route, from: origin, to: place.location),
                          opensAt: hours.opens,
                          closesAt: hours.closes,
                          attributes: attributes(of: place),
                          editorialSummary: place.editorialSummary?.text ?? "",
                          reviewSnippets: snippets(from: place.reviews))
    }

    // MARK: Cuisine

    /// Place types that name a cuisine a diner would recognise.
    ///
    /// - Note: Not exhaustive; unmatched falls back to `.modernAustralian`, and cuisine is
    ///   displayed rather than fenced on. Places reports a type array plus an optional
    ///   `primaryType`, so a venue can really be two cuisines where `Restaurant.cuisine` has one.
    static let cuisineByPlaceType: [String: Cuisine] = [
        "italian_restaurant": .italian,
        "thai_restaurant": .thai,
        "japanese_restaurant": .japanese,
        "sushi_restaurant": .sushi,
        "vietnamese_restaurant": .vietnamese,
        "chinese_restaurant": .chinese,
        "cantonese_restaurant": .chinese,
        "korean_restaurant": .korean,
        "korean_barbecue_restaurant": .korean,
        "indian_restaurant": .indian,
        "mexican_restaurant": .mexican,
        "tex_mex_restaurant": .mexican,
        "middle_eastern_restaurant": .middleEastern,
        "hamburger_restaurant": .burgers,
        "fast_food_restaurant": .burgers,
        "sandwich_shop": .sandwiches,
        "salad_shop": .salads,
        "pizza_restaurant": .pizza,
        "cafe": .cafe,
        "coffee_shop": .cafe,
        "asian_restaurant": .modernAsian,
        "asian_fusion_restaurant": .modernAsian,
        "ramen_restaurant": .modernAsian,
        "malaysian_restaurant": .modernAsian
    ]

    static func cuisine(of place: Places.Place) -> Cuisine {
        if let primary = place.primaryType, let named = cuisineByPlaceType[primary] { return named }
        // `types[]` is ordered most specific first, so the first recognised entry is the best one.
        for type in place.types ?? [] {
            if let named = cuisineByPlaceType[type] { return named }
        }
        return .modernAustralian
    }

    // MARK: Price

    /// What one person should expect to spend, in whole dollars.
    ///
    /// - Important: Taken from the **midpoint** of `priceRange`, not its floor. Google files a fast
    ///   food counter as one dollar to twenty, so a floor reads as `$1` and survives every budget.
    /// - Note: `priceLevel` is the coarser fallback, mapped onto each bucket's midpoint so both
    ///   paths mean the same thing.
    static func pricePerHead(of place: Places.Place) -> Int? {
        if let dollars = midpointOfBand(place.priceRange) { return dollars }
        guard let band = place.priceLevel else { return nil }
        switch band {
        case "PRICE_LEVEL_INEXPENSIVE": return 20
        case "PRICE_LEVEL_MODERATE": return 40
        case "PRICE_LEVEL_EXPENSIVE": return 60
        case "PRICE_LEVEL_VERY_EXPENSIVE": return 80
        default: return nil
        }
    }

    /// The middle of a reported band, rounded up; a band with no upper edge stands as given.
    private static func midpointOfBand(_ range: Places.PriceRange?) -> Int? {
        guard let start = range?.startPrice?.units.flatMap(Int.init) else { return nil }
        guard let end = range?.endPrice?.units.flatMap(Int.init), end > start else { return start }
        return (start + end + 1) / 2
    }

    // MARK: Walking time

    /// Minutes on foot from where the diner is standing.
    ///
    /// - Important: The fallback is straight-line distance at eighty metres a minute, ignoring
    ///   buildings, crossings and the harbour, so it under-reads every real walk. It is used only
    ///   when routing is missing.
    static func walkingMinutes(route: Places.RoutingSummary?,
                               from origin: Coordinate,
                               to venue: Places.LatLng?) -> Int {
        if let seconds = secondsOnFoot(route) { return Int((seconds / 60).rounded(.up)) }
        guard let latitude = venue?.latitude, let longitude = venue?.longitude else { return 0 }
        let metres = straightLineMetres(from: origin,
                                        to: Coordinate(latitude: latitude, longitude: longitude))
        return Int((metres / 80).rounded(.up))
    }

    /// - Important: `duration` is a string with a trailing `s` (`"351s"`), not a number. It does not
    ///   decode as one, and reading it as one silently loses every walking time in the response.
    static func secondsOnFoot(_ route: Places.RoutingSummary?) -> Double? {
        guard let duration = route?.legs?.first?.duration, duration.hasSuffix("s"),
              let seconds = Double(duration.dropLast()) else { return nil }
        return seconds
    }

    static func straightLineMetres(from origin: Coordinate, to venue: Coordinate) -> Double {
        // Equirectangular approximation; over a lunchtime walk the error is centimetres.
        let metresPerDegree = 111_320.0
        let northing = (venue.latitude - origin.latitude) * metresPerDegree
        let easting = (venue.longitude - origin.longitude) * metresPerDegree
            * cos(origin.latitude * .pi / 180)
        return (northing * northing + easting * easting).squareRoot()
    }

    // MARK: Opening hours

    /// Sunday is 0, matching Google's own numbering.
    static func gregorianWeekday(of date: Date) -> Int {
        Calendar(identifier: .gregorian).component(.weekday, from: date) - 1
    }

    /// When the venue serves today.
    ///
    /// - Important: Periods are matched by `open.day`, never by position: `periods[]` does not
    ///   begin on Sunday, so indexing reads one venue's Wednesday as another's Saturday.
    /// - Important: An opening marked `truncated` is last night still running, not today. Google
    ///   reports a bar that shut at 2am as opening today at 00:00, and reading that as today's
    ///   earliest opening marks the venue shut at lunchtime. Today's real sessions win.
    /// - Note: No published hours means open all day, since absent is not a refusal; hours
    ///   published with none for today means shut. A close past midnight clamps to 23:59.
    static func tradingHours(of place: Places.Place, on weekday: Int) -> (opens: TimeOfDay, closes: TimeOfDay) {
        let allDay: (opens: TimeOfDay, closes: TimeOfDay) =
            (TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 23, minute: 59))
        let shut: (opens: TimeOfDay, closes: TimeOfDay) =
            (TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 0, minute: 0))

        let periods = place.currentOpeningHours?.periods ?? place.regularOpeningHours?.periods ?? []
        guard !periods.isEmpty else { return allDay }

        let today = periods.filter { $0.open?.day == weekday }
        let trading = today.filter { $0.open?.truncated != true }
        // Several periods means a lunch and a dinner service, and lunch cares about the earliest.
        guard let period = (trading.isEmpty ? today : trading)
                .min(by: { minutes(of: $0.open) < minutes(of: $1.open) }),
              let opening = period.open else { return shut }

        let opens = TimeOfDay(hour: opening.hour ?? 0, minute: opening.minute ?? 0)
        guard let closing = period.close, closing.day == weekday else {
            return (opens, TimeOfDay(hour: 23, minute: 59))
        }
        let closes = TimeOfDay(hour: closing.hour ?? 23, minute: closing.minute ?? 59)
        return (opens, closes > opens ? closes : TimeOfDay(hour: 23, minute: 59))
    }

    static func minutes(of point: Places.Point?) -> Int {
        (point?.hour ?? 0) * 60 + (point?.minute ?? 0)
    }

    // MARK: Attributes

    /// The booleans worth carrying, which is far fewer than the API offers.
    ///
    /// - Important: An attribute earns its place only if it is sometimes false. `dineIn` and
    ///   `goodForGroups` are asserted or absent, never denied, so they are not mapped: the question
    ///   generator needs attributes the candidates disagree on.
    static func attributes(of place: Places.Place) -> Set<RestaurantAttribute> {
        var attributes: Set<RestaurantAttribute> = []
        if place.outdoorSeating == true { attributes.insert(.outdoorSeating) }
        if place.takeout == true { attributes.insert(.takeawayAvailable) }
        if place.reservable == true { attributes.insert(.bookingsTaken) }
        if place.servesBeer == true || place.servesWine == true || place.servesCocktails == true {
            attributes.insert(.licensed)
        }
        if place.primaryType == "fast_food_restaurant" { attributes.insert(.quickService) }
        return attributes
    }

    // MARK: Reviews

    /// Up to five review quotes, cut at a word boundary. The question generator reads these.
    static func snippets(from reviews: [Places.Review]?) -> [String] {
        let quotes = (reviews ?? []).compactMap { review -> String? in
            guard let text = review.text?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return shortened(text)
        }
        return Array(quotes.prefix(5))
    }

    static func shortened(_ text: String, to limit: Int = 200) -> String {
        guard text.count > limit else { return text }
        let clipped = text.prefix(limit - 1)
        guard let lastGap = clipped.lastIndex(where: { $0 == " " || $0 == "\n" }) else {
            return String(clipped) + "…"
        }
        return String(clipped[..<lastGap]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

// MARK: - What Google sends back

/// The wire shapes, named exactly as Google names them. Nothing in here leaves this file.
///
/// - Important: Every property is optional. Places attributes are three-valued: true, false, or
///   absent, and absent means the venue said nothing, never "no".
enum Places {

    struct NearbyResponse: Codable {
        let places: [Place]?
        /// Aligned by index with `places`, not nested inside it.
        let routingSummaries: [RoutingSummary]?
    }

    struct Place: Codable {
        let id: String?
        let displayName: LocalizedText?
        let primaryType: String?
        let types: [String]?
        let priceLevel: String?
        let priceRange: PriceRange?
        let rating: Double?
        let userRatingCount: Int?
        let businessStatus: String?
        let location: LatLng?
        let currentOpeningHours: OpeningHours?
        let regularOpeningHours: OpeningHours?
        let editorialSummary: LocalizedText?
        let reviews: [Review]?
        /// Decoded but deliberately not mapped. See `attributes(of:)`: it is never false.
        let dineIn: Bool?
        let takeout: Bool?
        let reservable: Bool?
        let outdoorSeating: Bool?
        let servesBeer: Bool?
        let servesWine: Bool?
        let servesCocktails: Bool?
    }

    struct LocalizedText: Codable {
        let text: String?
        let languageCode: String?
    }

    struct LatLng: Codable {
        let latitude: Double?
        let longitude: Double?
    }

    struct PriceRange: Codable {
        let startPrice: Money?
        let endPrice: Money?
    }

    struct Money: Codable {
        let currencyCode: String?
        /// A string holding an integer, as Google sends it: `"40"`, not `40`.
        let units: String?
    }

    struct OpeningHours: Codable {
        /// Decoded but never read: Google's answer at response time, while the fence judges "open"
        /// against the clock the caller passes in. Two clocks would disagree on one screen.
        let openNow: Bool?
        let periods: [Period]?
    }

    struct Period: Codable {
        let open: Point?
        let close: Point?
    }

    struct Point: Codable {
        /// 0 is Sunday. The array these sit in does not start there.
        let day: Int?
        let hour: Int?
        let minute: Int?
        /// Set when this opening began before the reported window: last night, still running.
        let truncated: Bool?
    }

    struct Review: Codable {
        let text: LocalizedText?
        let rating: Double?
    }

    struct RoutingSummary: Codable {
        let legs: [Leg]?
    }

    struct Leg: Codable {
        /// Seconds with a trailing `s`: `"351s"`.
        let duration: String?
        let distanceMeters: Int?
    }
}

// MARK: - Failure

/// What the diner is told when live restaurant data cannot be turned into a shortlist.
enum PlacesLookupError: LocalizedError, Equatable {
    /// The request never completed, or came back as anything other than a 2xx.
    case placesUnavailable
    /// A 2xx body that would not decode, which means the response shape has changed.
    case unreadableResponse
    /// The response was fine and nothing in it was a restaurant the app could offer.
    case nothingNearby

    var errorDescription: String? {
        switch self {
        case .placesUnavailable:
            return "Ezypick could not reach the restaurant service."
        case .unreadableResponse:
            return "The restaurant service sent back something Ezypick could not read."
        case .nothingNearby:
            return "Nothing around you came back as a restaurant Ezypick can suggest."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .placesUnavailable:
            return "Check your connection and try again in a moment."
        case .unreadableResponse:
            return "Try again shortly. If it keeps happening, Ezypick needs an update."
        case .nothingNearby:
            return "Try again from somewhere busier, or a little later in the day."
        }
    }
}
