import SwiftUI
import EzypickCore

/// The first screen: one thing to do, and a reminder of what the app already knows.
///
/// Deliberately offers no list, no map and no filters. Being handed options is the problem the
/// app exists to solve, so the home screen hands the diner none.
struct HomeView: View {
    @StateObject private var profile: DiningProfileViewModel
    @StateObject private var search: LunchSearchViewModel
    @State private var showingProfile = false
    @State private var showingSearch = false

    init(store: DiningPreferencesStore, restaurants: RestaurantRepository, generator: QuestionGenerator) {
        _profile = StateObject(wrappedValue: DiningProfileViewModel(store: store))
        _search = StateObject(wrappedValue: LunchSearchViewModel(restaurants: restaurants, generator: generator))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Text("Ezypick").font(.system(size: 44, weight: .bold))
                VStack(spacing: 4) {
                    Text("I'll do the research.")
                    Text("You just answer a few questions.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Button {
                    showingSearch = true
                } label: {
                    Text("Find me lunch")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal, 32)

                savedProfileCard
                Spacer()
            }
            .navigationDestination(isPresented: $showingSearch) {
                LunchSearchView(model: search, preferences: profile.preferences)
            }
            .sheet(isPresented: $showingProfile) {
                NavigationStack { DiningProfileView(model: profile) }
            }
        }
    }

    private var savedProfileCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What Ezypick knows about you").font(.caption).foregroundStyle(.secondary)
            Text(summary).font(.subheadline.weight(.medium))
            Button("Edit") { showingProfile = true }.font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .padding(.horizontal, 32)
    }

    private var summary: String {
        let diet = profile.dietaryRequirements.isEmpty
            ? "no dietary requirements"
            : profile.dietaryRequirements.map(\.spokenName).sorted().joined(separator: ", ")
        return "\(diet) · $\(profile.budgetPerHead) a head · \(profile.willingToWalkMinutes) min walk"
    }
}
