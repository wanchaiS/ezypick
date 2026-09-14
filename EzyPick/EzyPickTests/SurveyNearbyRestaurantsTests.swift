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
