import Testing
import Foundation
@testable import EzyPick

/// The screen a diner sees before anything is narrowed. Its value is entirely in being unfiltered,
/// so these check that it stays that way.
@Suite("Describing what is around the diner")
struct SurveyNearbyRestaurantsTests {

    @Test("Everything nearby is counted, including what the diner's own limits would rule out")
    func countsEveryVenueRegardlessOfWhatWouldSurviveTheFence() throws {
        // Only one of these three would survive a $25, ten minute fence. The summary is about what
        // is out there, so all three are counted; a diner told "one place nearby" would reasonably
        // conclude the neighbourhood was empty rather than that their budget was tight.
        let places = [
            restaurant("Within Reach", price: 20, walk: 5),
            restaurant("Too Dear", price: 90, walk: 5),
            restaurant("Too Far", price: 20, walk: 40)
        ]

        let survey = try SurveyNearbyRestaurantsUseCase().execute(from: places, at: townHall)

        #expect(survey.count == 3)
        #expect(survey.nearestWalkMinutes == 5)
    }

    @Test("The typical price is one a real restaurant charges, not an average pulled up by one steakhouse")
    func reportsTheMiddleRestaurantsPriceRatherThanTheMean() throws {
        // Mean is 41, which none of them charges and which sits above four of the five.
        let places = [
            restaurant("A", price: 15), restaurant("B", price: 18), restaurant("C", price: 22),
            restaurant("D", price: 25), restaurant("E", price: 125)
        ]

        let survey = try SurveyNearbyRestaurantsUseCase().execute(from: places, at: townHall)

        #expect(survey.typicalPerHead == 22)
    }

    @Test("The summary reports the coordinate it actually searched from")
    func namesTheOriginTheSearchRanFrom() throws {
        let bondi = Coordinate(latitude: -33.8915, longitude: 151.2767)

        let survey = try SurveyNearbyRestaurantsUseCase()
            .execute(from: [restaurant("Anywhere")], at: bondi)

        #expect(survey.origin == bondi)
    }

    @Test("The nearest places are named, because counts alone cannot tell two suburbs apart")
    func namesTheClosestPlacesSoTheSearchIsRecognisable() throws {
        // A strip in Wolli Creek and a strip in Bondi both summarised as "19 serving, nearest 2 min,
        // typically $20 a head". Identical numbers, entirely different restaurants, and the screen
        // gave a diner no way to tell which one it had searched.
        let places = [
            restaurant("Far Away", walk: 18),
            restaurant("Right Here", walk: 2),
            restaurant("Round The Corner", walk: 4),
            restaurant("Up The Road", walk: 9)
        ]

        let survey = try SurveyNearbyRestaurantsUseCase().execute(from: places, at: townHall)

        #expect(survey.examples == ["Right Here", "Round The Corner", "Up The Road"])
    }

    @Test("A place that is shut is still counted as one of the places nearby")
    func countsWhatIsThereRatherThanWhatSurvives() throws {
        // The summary's whole job is to say what is out there before the diner's limits touch it.
        // Counting only what survives would leave the screen unable to tell an empty neighbourhood
        // from a strict budget, which is the reason this use case exists at all.
        let places = [
            restaurant("Lunch Only", opens: "11:00", closes: "15:00"),
            restaurant("Dinner Only", opens: "17:00", closes: "22:00")
        ]

        let survey = try SurveyNearbyRestaurantsUseCase().execute(from: places, at: townHall)

        #expect(survey.count == 2)
    }

    @Test("The kinds of food are the commonest three, in the same order every time")
    func namesTheCommonestCuisinesDeterministically() throws {
        let places = [
            restaurant("T1", cuisine: .thai), restaurant("T2", cuisine: .thai),
            restaurant("T3", cuisine: .thai),
            restaurant("I1", cuisine: .italian), restaurant("I2", cuisine: .italian),
            restaurant("J1", cuisine: .japanese),
            restaurant("P1", cuisine: .pizza)
        ]
        let use = SurveyNearbyRestaurantsUseCase()

        let first = try use.execute(from: places, at: townHall)
        let second = try use.execute(from: places, at: townHall)

        #expect(first.commonCuisines.prefix(2) == [.thai, .italian])
        #expect(first.commonCuisines.count == 3, "Three is as many as a person reads at a glance")
        #expect(first.commonCuisines == second.commonCuisines, "A summary that reshuffles reads as unreliable")
    }

    @Test("A search that comes back empty says so rather than describing nothing")
    func refusesToSummariseAnEmptySearch() throws {
        #expect(throws: SurveyNearbyRestaurantsError.nothingNearby) {
            try SurveyNearbyRestaurantsUseCase().execute(from: [], at: townHall)
        }
    }
}

/// Where a search runs from when the test does not care about the spot, matching the diner outside
/// Town Hall the rest of the suite uses.
private let townHall = Coordinate(latitude: -33.8688, longitude: 151.2093)
