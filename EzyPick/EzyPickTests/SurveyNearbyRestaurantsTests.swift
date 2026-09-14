import Testing
import Foundation
@testable import EzyPick

/// The screen a diner sees before anything is narrowed. Its value is entirely in being unfiltered,
/// so these check that it stays that way.
@Suite("Describing what is around the diner")
struct SurveyNearbyRestaurantsTests {

    @Test("Everything nearby is counted, including what the diner's own limits would rule out")
    func countsEveryVenueRegardlessOfWhatWouldSurviveTheFence() async throws {
        // Only one of these three would survive a $25, ten minute fence. The summary is about what
        // is out there, so all three are counted; a diner told "one place nearby" would reasonably
        // conclude the neighbourhood was empty rather than that their budget was tight.
        let catalogue = StubCatalogue(restaurants: [
            restaurant("Within Reach", price: 20, walk: 5),
            restaurant("Too Dear", price: 90, walk: 5),
            restaurant("Too Far", price: 20, walk: 40)
        ])

        let survey = try await SurveyNearbyRestaurantsUseCase(restaurants: catalogue, location: FixedLocation())
            .execute()

        #expect(survey.count == 3)
        #expect(survey.nearestWalkMinutes == 5)
    }

    @Test("The typical price is one a real restaurant charges, not an average pulled up by one steakhouse")
    func reportsTheMiddleRestaurantsPriceRatherThanTheMean() async throws {
        // Mean is 41, which none of them charges and which sits above four of the five.
        let catalogue = StubCatalogue(restaurants: [
            restaurant("A", price: 15), restaurant("B", price: 18), restaurant("C", price: 22),
            restaurant("D", price: 25), restaurant("E", price: 125)
        ])

        let survey = try await SurveyNearbyRestaurantsUseCase(restaurants: catalogue, location: FixedLocation())
            .execute()

        #expect(survey.typicalPerHead == 22)
    }

    @Test("The summary reports the coordinate it actually searched from")
    func namesTheOriginTheSearchRanFrom() async throws {
        let bondi = Coordinate(latitude: -33.8915, longitude: 151.2767)
        let survey = try await SurveyNearbyRestaurantsUseCase(
            restaurants: StubCatalogue(restaurants: [restaurant("Anywhere")]),
            location: StubLocation(bondi)
        ).execute()

        #expect(survey.origin == bondi)
    }

    @Test("The nearest places are named, because counts alone cannot tell two suburbs apart")
    func namesTheClosestPlacesSoTheSearchIsRecognisable() async throws {
        // A strip in Wolli Creek and a strip in Bondi both summarised as "19 serving, nearest 2 min,
        // typically $20 a head". Identical numbers, entirely different restaurants, and the screen
        // gave a diner no way to tell which one it had searched.
        let catalogue = StubCatalogue(restaurants: [
            restaurant("Far Away", walk: 18),
            restaurant("Right Here", walk: 2),
            restaurant("Round The Corner", walk: 4),
            restaurant("Up The Road", walk: 9)
        ])

        let survey = try await SurveyNearbyRestaurantsUseCase(restaurants: catalogue,
                                                              location: FixedLocation())
            .execute()

        #expect(survey.examples == ["Right Here", "Round The Corner", "Up The Road"])
    }

    @Test("One position fix serves the search and the summary that describes it")
    func asksWhereTheDinerIsOnlyOnce() async throws {
        // Two fixes means two answers on a phone being carried down a street, and the summary would
        // then name a corner the restaurants were not chosen from. That reads as authoritative and
        // is wrong, which is worse than not showing it.
        let counting = CountingLocation(Coordinate(latitude: -33.8688, longitude: 151.2093))
        let remembered = RememberedLocation(counting)

        _ = try await remembered.currentCoordinate()
        _ = try await remembered.currentCoordinate()
        _ = try await remembered.currentCoordinate()

        #expect(await counting.fixes == 1)
    }

    @Test("A place that is shut is still counted as one of the places nearby")
    func countsWhatIsThereRatherThanWhatSurvives() async throws {
        // The summary's whole job is to say what is out there before the diner's limits touch it.
        // Counting only what survives would leave the screen unable to tell an empty neighbourhood
        // from a strict budget, which is the reason this use case exists at all.
        let catalogue = StubCatalogue(restaurants: [
            restaurant("Lunch Only", opens: "11:00", closes: "15:00"),
            restaurant("Dinner Only", opens: "17:00", closes: "22:00")
        ])

        let survey = try await SurveyNearbyRestaurantsUseCase(restaurants: catalogue, location: FixedLocation())
            .execute()

        #expect(survey.count == 2)
    }

    @Test("The kinds of food are the commonest three, in the same order every time")
    func namesTheCommonestCuisinesDeterministically() async throws {
        let catalogue = StubCatalogue(restaurants: [
            restaurant("T1", cuisine: .thai), restaurant("T2", cuisine: .thai),
            restaurant("T3", cuisine: .thai),
            restaurant("I1", cuisine: .italian), restaurant("I2", cuisine: .italian),
            restaurant("J1", cuisine: .japanese),
            restaurant("P1", cuisine: .pizza)
        ])
        let use = SurveyNearbyRestaurantsUseCase(restaurants: catalogue, location: FixedLocation())

        let first = try await use.execute()
        let second = try await use.execute()

        #expect(first.commonCuisines.prefix(2) == [.thai, .italian])
        #expect(first.commonCuisines.count == 3, "Three is as many as a person reads at a glance")
        #expect(first.commonCuisines == second.commonCuisines, "A summary that reshuffles reads as unreliable")
    }

    @Test("A search that comes back empty says so rather than describing nothing")
    func refusesToSummariseAnEmptySearch() async throws {
        await #expect(throws: SurveyNearbyRestaurantsError.nothingNearby) {
            try await SurveyNearbyRestaurantsUseCase(restaurants: StubCatalogue(restaurants: []), location: FixedLocation())
                .execute()
        }
    }

    @Test("One live search serves the whole trip")
    func looksUpRestaurantsOnceEvenWhenReadSeveralTimes() async throws {
        // The summary, the fence, and every "none of these" all read the same list. Against a billed
        // service a second call costs money; worse, it can return different venues, so the summary
        // the diner just read would not describe the shortlist they end up with.
        let counting = CountingCatalogue(restaurants: [restaurant("Only One")])
        let cache = OneShotRestaurantCache(counting)

        _ = try await SurveyNearbyRestaurantsUseCase(restaurants: cache, location: FixedLocation()).execute()
        _ = try await ShortlistRestaurantsUseCase(restaurants: cache).execute(for: preferences(), at: lunchtime)
        _ = try await ShortlistRestaurantsUseCase(restaurants: cache).execute(for: preferences(), at: lunchtime)

        #expect(await counting.lookups == 1)
    }
}

/// Counts how many times it was asked, so a caching claim can be proved rather than assumed.
private actor CountingCatalogue: RestaurantRepository {
    private let restaurants: [Restaurant]
    private(set) var lookups = 0

    init(restaurants: [Restaurant]) { self.restaurants = restaurants }

    func nearbyRestaurants() async throws -> [Restaurant] {
        lookups += 1
        return restaurants
    }
}

/// A diner standing somewhere the test chooses.
private struct StubLocation: CurrentLocationProvider {
    let coordinate: Coordinate
    init(_ coordinate: Coordinate) { self.coordinate = coordinate }
    func currentCoordinate() async throws -> Coordinate { coordinate }
}

/// Counts how often it was asked, so a single-fix claim can be proved rather than assumed.
private actor CountingLocation: CurrentLocationProvider {
    private let coordinate: Coordinate
    private(set) var fixes = 0

    init(_ coordinate: Coordinate) { self.coordinate = coordinate }

    func currentCoordinate() async throws -> Coordinate {
        fixes += 1
        return coordinate
    }
}
