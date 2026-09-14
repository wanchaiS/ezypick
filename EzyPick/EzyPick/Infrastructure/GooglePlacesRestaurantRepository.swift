import Foundation
import os

/// Restaurants from Google Places API (New), centred on wherever the diner is standing.
///
/// This is the live half of `RestaurantRepository`. Nothing above it changes: the use cases still
/// receive `[Restaurant]` and still apply every one of the diner's limits themselves. That split is
/// deliberate and it is not laziness. Nearby Search has almost nothing to fence with. Its only
/// honest server-side controls are the place-type lists and a radius in metres, so the request asks
/// for a wide-but-clean set of restaurants and the fence stays where it can be tested.
///
/// - Important: `includedPrimaryTypes`, never `includedTypes`. A request for `includedTypes:
///   ["restaurant"]` in the Sydney CBD comes back with a Woolworths and four hotels, because
///   `types[]` widens sideways across anything that sells food. `includedPrimaryTypes` widens only
///   downwards, into `ramen_restaurant`, `steak_house` and the rest, which is exactly what a diner
///   means by "somewhere to eat".
///
/// - Important: Do not add `priceLevels`, `minRating` or `openNow` to the request body. Nearby
///   Search accepts all three with HTTP 200 and silently ignores them: the result set comes back
///   byte-identical, and `openNow: true` returns venues that report `openNow: false`. An unknown
///   field is rejected with a 400, but an unimplemented one is accepted quietly, so a fence built on
///   them would look like it worked and would filter nothing. Every one of those limits is applied
///   client-side by `ShortlistRestaurantsUseCase`, which already does it and has tests that prove it.
struct GooglePlacesRestaurantRepository: RestaurantRepository {
    private let apiKey: String
    private let location: any CurrentLocationProvider
    private let searchRadiusMetres: Double
    private let session: URLSession

    /// - Parameters:
    ///   - apiKey: a Places API key. It is read from the app's configuration and never committed.
    ///   - location: where to search from.
    ///   - searchRadiusMetres: how far out to look. The default is roughly a twenty minute walk,
    ///     which is the widest limit the profile editor lets a diner set.
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
    /// Deliberately unfiltered beyond what the API can be trusted to do. The diner's budget, walk
    /// and the clock are all applied by `ShortlistRestaurantsUseCase`, which can be tested without
    /// a network and cannot be silently ignored by a remote service.
    /// What is dropped here is only what the app could not honestly offer at all: venues that are
    /// not trading, and venues with no price to measure against a budget.
    ///
    /// - Throws: `PlacesLookupError`, which is the only error a caller sees. A transport failure and
    ///   a 500 are the same thing to a diner, so they are reported the same way.
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

        Diagnostics.places.info("""
            searching from \(origin.latitude, privacy: .public), \
            \(origin.longitude, privacy: .public) within \(Int(searchRadiusMetres), privacy: .public) m
            """)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Diagnostics.places.error("lookup failed before a reply: \(error.localizedDescription, privacy: .public)")
            throw PlacesLookupError.placesUnavailable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Diagnostics.places.error("lookup refused with HTTP \(code, privacy: .public)")
            throw PlacesLookupError.placesUnavailable
        }
        guard let payload = try? JSONDecoder().decode(Places.NearbyResponse.self, from: data) else {
            Diagnostics.places.error("reply could not be decoded, \(data.count, privacy: .public) bytes")
            throw PlacesLookupError.unreadableResponse
        }

        let restaurants = Self.restaurants(in: payload, from: origin, on: Date())
        // The gap between the two counts is the venues dropped for not trading or having no price.
        Diagnostics.places.info("""
            \(payload.places?.count ?? 0, privacy: .public) venues returned, \
            \(restaurants.count, privacy: .public) usable: \
            \(restaurants.map(\.name).joined(separator: ", "), privacy: .public)
            """)
        guard !restaurants.isEmpty else { throw PlacesLookupError.nothingNearby }
        return restaurants
    }

    static let endpoint = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!

    /// Exactly what is read below, and nothing else.
    ///
    /// Places bills per field at the highest tier anything in the mask belongs to, and a mask of
    /// `*` is both the most expensive request available and a wall of data nobody reads. Each name
    /// here was checked against a live response before it was added.
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

    /// The whole request body, and it is short on purpose.
    ///
    /// `routingParameters` annotates rather than filters: the result set is identical with and
    /// without it. It earns its place because it is the only way to get a walking time, and a lunch
    /// break is measured in minutes rather than metres.
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
    ///   `places[]`, not a field nested inside each place. Zipping them by position in the *source*
    ///   array is the only correct reading, and it has to survive venues being dropped: a venue
    ///   skipped for being shut must not shift every walking time after it by one.
    static func restaurants(in payload: Places.NearbyResponse,
                            from origin: Coordinate,
                            on date: Date) -> [Restaurant] {
        let places = payload.places ?? []
        let routes = payload.routingSummaries ?? []
        let weekday = gregorianWeekday(of: date)

        return places.enumerated().compactMap { index, place in
            // Google returns one summary per place, but a truncated or absent array is not worth a
            // crash: an unrouted venue falls back to straight-line distance below.
            let route = index < routes.count ? routes[index] : nil
            return restaurant(from: place, route: route, origin: origin, weekday: weekday)
        }
    }

    /// One venue, or `nil` when it is not something the app is willing to suggest.
    ///
    /// Two reasons to drop a venue, and both protect a promise the app has already made. A venue
    /// that is not `OPERATIONAL` would send someone to a closed shopfront. A venue with no price at
    /// all cannot be measured against the diner's budget cap, and quietly keeping it would let it
    /// through a fence the diner explicitly set.
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
    /// Not exhaustive, and it does not need to be. Anything unmatched falls back to
    /// `.modernAustralian`, which is cosmetic: cuisine is displayed on the shortlist card and is
    /// never fenced on, so a mislabelled venue costs a word on screen and nothing else.
    ///
    /// - Important: `Restaurant.cuisine` is one value where Places returns an array plus an
    ///   *optional* `primaryType`. That mismatch is known and recorded rather than papered over. A
    ///   venue really can be two cuisines at once, and the model here says it cannot.
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
    /// `priceRange` is a band rather than an estimate, so the app has to decide which number in it
    /// a diner means when they say twenty-five dollars a head. It reads the **midpoint**.
    ///
    /// The lower edge was the first answer and it was wrong on screen: Google files a fast food
    /// counter as one dollar to twenty, so it read as `$1` and outlived every budget the app could
    /// set, while a restaurant filed at forty to eighty was refused on a floor nobody is charged
    /// either. A band's edges are both prices that no single meal costs; its middle is the only
    /// number in it that describes a likely bill.
    ///
    /// - Note: `priceLevel` is the coarser fallback and was already mapped onto the midpoint of
    ///   each bucket, so both paths now mean the same thing by the number they return.
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

    /// The middle of a reported price band, rounded up to a whole dollar.
    ///
    /// A band with no upper edge is all the API is willing to say, so its single figure stands.
    private static func midpointOfBand(_ range: Places.PriceRange?) -> Int? {
        guard let start = range?.startPrice?.units.flatMap(Int.init) else { return nil }
        guard let end = range?.endPrice?.units.flatMap(Int.init), end > start else { return start }
        return (start + end + 1) / 2
    }

    // MARK: Walking time

    /// Minutes on foot from where the diner is standing.
    ///
    /// A routed duration is a real walk along real footpaths. The fallback is not: straight-line
    /// distance at eighty metres a minute ignores buildings, crossings and the harbour, so it
    /// under-reads every genuine walk and a venue may turn out to be further than the app said.
    /// It is used only when routing is missing, which the live API does not do often.
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
        // Equirectangular approximation. Over a lunchtime walk the error is centimetres, and the
        // number it feeds is rounded to whole minutes anyway.
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
    /// - Important: Periods are found by their `open.day` value, never by their position in the
    ///   array. Google's own documentation warns that `periods[]` does not begin on Sunday, and a
    ///   live response confirms it. Indexing by position reads one venue's Wednesday as another
    ///   venue's Saturday, and the result looks entirely plausible.
    ///
    /// Three cases the domain cannot say any other way. A venue that published no hours at all is
    /// treated as open all day, because absent means it told Google nothing, not that it is shut,
    /// and an unknown must never quietly remove a venue the diner could have eaten at. A venue that
    /// published hours but listed none for today *did* tell Google, and what it said is that it is
    /// closed, so it gets an empty window that `Restaurant.isOpen(at:)` can never satisfy. A close
    /// that rolls past midnight is clamped to 23:59, because `TimeOfDay` has no way to carry a
    /// date and lunch never spans one.
    ///
    /// - Important: A period whose opening is `truncated` is **last night still running**, not
    ///   today's trading. Google reports a bar that shut at 2am as opening today at 00:00, and
    ///   taking the earliest opening at face value reads that as "open 00:00 to 02:00" and marks
    ///   the venue shut at lunchtime. Measured against live Sydney data, that wrongly excluded
    ///   three venues in fifteen. Today's real sessions are preferred; the rollover is used only
    ///   when it is all the venue has.
    static func tradingHours(of place: Places.Place, on weekday: Int) -> (opens: TimeOfDay, closes: TimeOfDay) {
        let allDay: (opens: TimeOfDay, closes: TimeOfDay) =
            (TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 23, minute: 59))
        let shut: (opens: TimeOfDay, closes: TimeOfDay) =
            (TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 0, minute: 0))

        let periods = place.currentOpeningHours?.periods ?? place.regularOpeningHours?.periods ?? []
        guard !periods.isEmpty else { return allDay }

        let today = periods.filter { $0.open?.day == weekday }
        let trading = today.filter { $0.open?.truncated != true }
        // Several periods means a lunch service and a dinner service. The earliest opening is the
        // one a lunch decision cares about, once last night's spillover is out of the way.
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
    /// An attribute earns its place here only if it is sometimes false. Across 57 Sydney
    /// restaurants `dineIn` came back 57 true and 0 false, and `goodForGroups` 54 true and 0 false:
    /// they are asserted or absent, never denied. Neither is mapped, and mapping them would be
    /// actively harmful rather than merely useless, because the question generator reads attributes
    /// looking for somewhere the candidates disagree. An attribute that is never false cannot split
    /// a set, so it would produce a question that narrows nothing and burns one of the five the
    /// diner is willing to answer.
    ///
    /// `outdoorSeating` is the opposite and is the reason this list exists at all: 26 true to 29
    /// false is almost exactly one bit, which halves the candidates in a single swipe.
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

    /// Up to five review quotes, tidied for a card.
    ///
    /// These are what the question generator reads, because they are the only part of a venue no
    /// structured field can express. Live reviews run to multiple paragraphs about parking and wait
    /// times, so each is cut at a word boundary rather than mid-syllable.
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

/// The wire shapes, named exactly as Google names them so a response and a decoder can be read side
/// by side. Nothing in here leaves this file: the namespace keeps `Place` and `LatLng` out of a
/// domain that should never learn what a field mask is.
///
/// Every property is optional, without exception. Places attributes are three-valued: true, false,
/// and absent, where absent means the venue told Google nothing. Collapsing absent into false would
/// turn "we do not know" into "no", which is a claim the data does not support.
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
        /// Set when this opening began before the window Google is reporting on, which in practice
        /// means last night's session still running at midnight.
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
///
/// Three cases, because they need three different things from the diner. A transport failure and a
/// 500 are the same event to somebody standing on a footpath, so they are reported as one.
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
