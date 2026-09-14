import Testing
import Foundation
@testable import EzyPick

/// Live data is where a shortlist stops being a data structure and starts being a claim about the
/// street outside. These check the readings that would be wrong in a way nobody notices: a walking
/// time belonging to the venue next door, a Wednesday read as a Saturday, and a venue with no price
/// slipping under a budget cap.
///
/// Serialised because the whole suite answers one canned response at a time.
@Suite("Reading restaurants back from Google Places", .serialized)
struct GooglePlacesRestaurantRepositoryTests {

    @Test("Each venue keeps its own walking time when a venue ahead of it is dropped")
    func alignsRoutingSummariesByIndexRatherThanByOutput() async throws {
        // routingSummaries is a parallel top-level array, not a field inside each place. The first
        // venue in the response is shut and is dropped, so an implementation that walks the two
        // arrays together as it builds its output hands Bar Totti's the shut venue's 912 seconds.
        let found = try await restaurants(answering: recordedResponse())

        #expect(found.first(where: { $0.name == "Bar Totti's" })?.walkingMinutes == 6)
        #expect(found.first(where: { $0.name == "Chat Thai" })?.walkingMinutes == 9)
        #expect(found.first(where: { $0.name == "Gandhi's Kitchen" })?.walkingMinutes == 5)
    }

    @Test("A venue is priced from its range, then its band, or it is not offered at all")
    func pricesFromTheRangeFirstAndDropsWhateverItCannotPrice() async throws {
        let found = try await restaurants(answering: recordedResponse())

        // "40" arrives as a string holding an integer, and PRICE_LEVEL_INEXPENSIVE is the fallback.
        #expect(found.first(where: { $0.name == "Bar Totti's" })?.pricePerHead == 40)
        #expect(found.first(where: { $0.name == "Chat Thai" })?.pricePerHead == 20)
        // Morso publishes neither. Keeping it would let it through the diner's budget cap unmeasured.
        #expect(!found.contains(where: { $0.name == "Morso Espresso Bar" }))
    }

    @Test("A venue that is not trading is never suggested")
    func dropsAVenueThatIsNotOperational() async throws {
        let found = try await restaurants(answering: recordedResponse())

        #expect(!found.contains(where: { $0.name == "Kingsleys Steak & Crabhouse" }))
    }

    @Test("Opening hours are read by the day they name, not by where they sit in the array")
    func readsOpeningHoursByDayValueAndTakesTheEarliestService() async throws {
        // Google's periods[] does not begin on Sunday. This week begins on Wednesday and gives every
        // day a different opening hour, so a reading by array position is wrong on all seven days.
        // Each day also carries a dinner service listed ahead of its lunch service.
        let today = Calendar(identifier: .gregorian).component(.weekday, from: Date()) - 1
        let found = try await restaurants(answering: rotatedWeekResponse())
        let venue = try #require(found.first)

        #expect(venue.opensAt == TimeOfDay(hour: 8 + today, minute: 0))
        #expect(venue.closesAt == TimeOfDay(hour: 15, minute: 30))
    }

    @Test("Last night's session still running at midnight is not mistaken for today's opening")
    func ignoresTheOvernightRolloverWhenPickingTodaysHours() async throws {
        // A bar that shut at 2am is reported as opening today at 00:00 with `truncated` set. Taking
        // the earliest opening at face value reads that as "open 00:00 to 02:00" and marks the venue
        // shut at lunchtime. Against live Sydney data this wrongly excluded three venues in fifteen.
        let found = try await restaurants(answering: overnightRolloverResponse())
        let venue = try #require(found.first)

        #expect(venue.opensAt == TimeOfDay(hour: 12, minute: 0))
        #expect(venue.isOpen(at: TimeOfDay(hour: 12, minute: 30)))
    }

    @Test("A boolean that is never false never becomes an attribute")
    func ignoresTheBooleansThatCannotSplitACandidateSet() async throws {
        let found = try await restaurants(answering: recordedResponse())
        let totti = try #require(found.first(where: { $0.name == "Bar Totti's" }))

        // dineIn was true on all 57 venues measured and false on none. A question built from it
        // narrows nothing and costs the diner one of the five answers they are willing to give.
        #expect(!totti.attributes.contains(.sitDownDining))
        #expect(totti.attributes == [.takeawayAvailable, .bookingsTaken, .licensed])
    }

    @Test("Each way the lookup can fail is reported as its own kind of failure")
    func reportsEachKindOfFailureSeparately() async throws {
        await #expect(throws: PlacesLookupError.placesUnavailable) {
            try await restaurants(from: .failedToConnect)
        }
        await #expect(throws: PlacesLookupError.placesUnavailable) {
            try await restaurants(answering: Data(#"{"error":{"code":500}}"#.utf8), status: 500)
        }
        await #expect(throws: PlacesLookupError.unreadableResponse) {
            try await restaurants(answering: Data("<html>Service unavailable</html>".utf8))
        }
        await #expect(throws: PlacesLookupError.nothingNearby) {
            try await restaurants(answering: Data(#"{"places":[]}"#.utf8))
        }
    }

    @Test("Every failure tells the diner what went wrong and what to do about it")
    func everyFailureCarriesAWayOut() throws {
        let failures: [PlacesLookupError] = [.placesUnavailable, .unreadableResponse, .nothingNearby]

        for failure in failures {
            let cause = try #require(failure.errorDescription)
            let wayOut = try #require(failure.recoverySuggestion)
            #expect(cause != wayOut, "A refusal that repeats itself has not told the diner anything")
            #expect(!cause.contains("—") && !wayOut.contains("—"),
                    "House style: no em dashes in what the diner reads")
        }
    }
}

// MARK: - Answering without a network

private extension GooglePlacesRestaurantRepositoryTests {

    func restaurants(answering body: Data, status: Int = 200) async throws -> [Restaurant] {
        try await restaurants(from: .replied(status: status, body: body))
    }

    func restaurants(from outcome: StubbedPlaces.Outcome) async throws -> [Restaurant] {
        try await placesRepository(answering: outcome).nearbyRestaurants()
    }

    /// A response recorded from the real endpoint, trimmed to five venues.
    func recordedResponse() throws -> Data {
        let url = try #require(Bundle(for: StubbedPlaces.self).url(forResource: "places-nearby-response",
                                                 withExtension: "json"))
        return try Data(contentsOf: url)
    }

    /// One venue whose week starts on Wednesday, with two services a day and a different opening
    /// hour on each of the seven.
    func rotatedWeekResponse() throws -> Data {
        let periods = [3, 4, 5, 6, 0, 1, 2].flatMap { day in
            [
                ["open": ["day": day, "hour": 18, "minute": 0],
                 "close": ["day": day, "hour": 22, "minute": 0]],
                ["open": ["day": day, "hour": 8 + day, "minute": 0],
                 "close": ["day": day, "hour": 15, "minute": 30]]
            ]
        }
        let place: [String: Any] = [
            "id": "rotated-week",
            "displayName": ["text": "Weekday Canteen", "languageCode": "en"],
            "primaryType": "cafe",
            "types": ["cafe", "restaurant", "food"],
            "priceLevel": "PRICE_LEVEL_INEXPENSIVE",
            "rating": 4.3,
            "userRatingCount": 88,
            "businessStatus": "OPERATIONAL",
            "currentOpeningHours": ["periods": periods]
        ]
        return try JSONSerialization.data(withJSONObject: ["places": [place]])
    }

    /// A late bar as Google actually reports it: today opens at midnight because last night never
    /// ended, and the real lunch service is listed afterwards.
    func overnightRolloverResponse() throws -> Data {
        let today = Calendar(identifier: .gregorian).component(.weekday, from: Date()) - 1
        let place: [String: Any] = [
            "id": "late-bar",
            "displayName": ["text": "Small Hours", "languageCode": "en"],
            "primaryType": "italian_restaurant",
            "types": ["italian_restaurant", "restaurant", "food"],
            "priceLevel": "PRICE_LEVEL_MODERATE",
            "rating": 4.0,
            "userRatingCount": 4456,
            "businessStatus": "OPERATIONAL",
            "currentOpeningHours": ["periods": [
                ["open": ["day": today, "hour": 0, "minute": 0, "truncated": true],
                 "close": ["day": today, "hour": 2, "minute": 0]],
                ["open": ["day": today, "hour": 12, "minute": 0],
                 "close": ["day": (today + 1) % 7, "hour": 0, "minute": 0]]
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: ["places": [place]])
    }
}
