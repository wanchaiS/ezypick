import SwiftUI

/// The first screen: one thing to do, and a reminder of what the app already knows.
///
/// Deliberately offers no list, no map and no filters. Being handed options is the problem the
/// app exists to solve, so the home screen hands the diner none.
struct HomeView: View {
    @StateObject private var profile: DiningProfileViewModel
    @StateObject private var search: LunchSearchViewModel
    @State private var showingProfile = false
    @State private var showingSearch = false

    init(store: DiningPreferencesStore, restaurants: RestaurantRepository,
         generator: QuestionGenerator, location: any CurrentLocationProvider) {
        _profile = StateObject(wrappedValue: DiningProfileViewModel(store: store))
        _search = StateObject(wrappedValue: LunchSearchViewModel(restaurants: restaurants,
                                                                generator: generator,
                                                                location: location))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Text("Ezypick").font(.system(size: 44, weight: .bold))
                Text("Picking a restaurant, made easier.")
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

                aboutYouCard
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

    /// The saved profile, shown as badges rather than prose.
    ///
    /// The point is recognition, not information: the diner should glance at this and know the app
    /// has them right. A sentence has to be read to be checked, so the profile is drawn as chips.
    private var aboutYouCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("About you").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(profile.hasSavedProfile ? "Edit" : "Set up") { showingProfile = true }
                    .font(.caption)
            }

            if profile.hasSavedProfile {
                ChipFlowLayout(spacing: 6) {
                    ForEach(PreferenceBadge.all(for: profile.preferences)) { badge in
                        PreferenceChip(badge: badge)
                    }
                }
            } else {
                Text("Nothing saved yet. Tell Ezypick what you'll spend and how far you'll walk.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .padding(.horizontal, 32)
    }
}
