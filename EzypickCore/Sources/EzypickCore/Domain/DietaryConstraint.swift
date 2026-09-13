import Foundation

/// Something a diner cannot eat, whether for medical, religious or ethical reasons.
///
/// A \`DietaryConstraint\` is deliberately **not** a preference and is not the same kind of
/// thing as an answer to a question. Preferences are traded off against each other when the
/// app narrows a shortlist; a constraint never is. Keeping them as separate types means a
/// constraint cannot accidentally end up in a tally and be outweighed.
///
/// - Important: Business rule — a restaurant that cannot serve a diner's constraint is not a
///   candidate, regardless of how well it scores on anything else. There is no override.
public enum DietaryConstraint: String, CaseIterable, Codable, Sendable {
    case glutenFree, halal, vegetarian, vegan, nutFree, dairyFree, shellfishFree

    /// How this requirement is described to a person, in their words rather than the enum's.
    public var spokenName: String {
        switch self {
        case .glutenFree: "gluten-free"
        case .halal: "halal"
        case .vegetarian: "vegetarian"
        case .vegan: "vegan"
        case .nutFree: "nut-free"
        case .dairyFree: "dairy-free"
        case .shellfishFree: "shellfish-free"
        }
    }
}

/// Where a restaurant's dietary information came from, and therefore how far it can be trusted.
///
/// No mainstream places API exposes verified gluten-free, halal or allergen capability, so the
/// app must never imply it has checked. Provenance travels with the data and is shown to the
/// diner, who makes the final call at the counter.
///
/// - Important: Business rule — the app filters on dietary data but never claims to have
///   verified it. Wording is "lists gluten-free options — worth confirming when you order",
///   never "safe for coeliacs".
public enum DietaryProvenance: String, Codable, Sendable {
    /// Published by the restaurant itself.
    case restaurantReported
    /// Reported by diners rather than the venue.
    case userContributed
    /// Inferred from the venue's category, with nothing to back it up.
    case unverified

    public var caveat: String {
        switch self {
        case .restaurantReported: "as listed by the restaurant — worth confirming when you order"
        case .userContributed: "reported by other diners — worth confirming when you order"
        case .unverified: "not confirmed by the restaurant — please check before you order"
        }
    }
}
