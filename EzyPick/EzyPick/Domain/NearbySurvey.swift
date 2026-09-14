import Foundation

/// What is actually around the diner, before any of their limits are applied.
///
/// The app's whole promise is that it does the looking so the diner does not have to, and a promise
/// made silently is indistinguishable from no promise at all. This is the app showing its working:
/// here is what was found, here is the shape of it, now let me narrow it down for you.
///
/// Deliberately *not* filtered. Everything here counts every venue the search returned, including
/// the ones the diner's budget or walking limit is about to rule out, because the point is to say
/// what is out there rather than what survives.
struct NearbySurvey: Equatable, Sendable {
    /// Where the search was run from.
    ///
    /// Carried so the diner can be shown it. An app that searches "near you" without saying where
    /// it thinks you are asks to be trusted on the one thing the whole result depends on, and when
    /// it is wrong there is nothing on screen to give it away.
    let origin: Coordinate
    /// How many restaurants the search found, before any of the diner's limits are applied.
    let count: Int
    /// The shortest walk to any of them, in minutes.
    let nearestWalkMinutes: Int
    /// What a diner would typically spend at the middle of this lot, in whole dollars.
    ///
    /// The middle rather than the range. Places reports a price *band* per venue and the app reads
    /// its lower edge, so pairing the cheapest venue's floor with the dearest venue's floor
    /// produced "from $1 to $60 a head": true of no restaurant, and a summary nobody can act on.
    let typicalPerHead: Int
    /// The kinds of food most of them serve, most common first, at most three.
    let commonCuisines: [Cuisine]
    /// A few of them by name, so the diner can recognise where the app is looking.
    ///
    /// Counts and averages describe two different suburbs identically: a strip in Wolli Creek and a
    /// strip in Bondi both came back as "19 serving, nearest 2 min, typically $20 a head", which
    /// read as a bug in the location. Names cannot do that. They are the cheapest possible proof
    /// that the search happened where the diner is standing.
    let examples: [String]

    init(origin: Coordinate, count: Int, nearestWalkMinutes: Int,
                typicalPerHead: Int, commonCuisines: [Cuisine], examples: [String]) {
        self.origin = origin
        self.count = count
        self.nearestWalkMinutes = nearestWalkMinutes
        self.typicalPerHead = typicalPerHead
        self.commonCuisines = commonCuisines
        self.examples = examples
    }
}
