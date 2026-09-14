import SwiftUI

/// Where the diner says what their lunch break allows.
///
/// Two controls, and the list is short on purpose. Every control here is a tap the diner pays for
/// once and the app spends every day, so a setting that never changes which restaurants come back
/// has no business being on this screen. Four things have been removed on exactly that test:
/// cuisines to avoid, which are a craving and therefore what the questions are for; a meal-time
/// picker, which asked a lunch app to confirm it was lunchtime; a box for pasting an API key, which
/// an engineer configures once and nobody knows about themselves; and the dietary requirements,
/// which were the hardest rule in the app until live data showed that ticking one returned nothing
/// at all, wherever the diner stood.
struct DiningProfileView: View {
    @ObservedObject var model: DiningProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Stepper("Up to $\(model.budgetPerHead) a head", value: $model.budgetPerHead, in: 10...60, step: 5)
                Stepper("\(model.willingToWalkMinutes) min walk", value: $model.willingToWalkMinutes, in: 1...20)
            } header: {
                Text("Your lunch break")
            } footer: {
                Text("Ezypick only suggests places within this, and only ones open when you look.")
            }

            if let problem = model.problem {
                Section {
                    Text(problem).foregroundStyle(.red)
                    if let fix = model.howToFixIt { Text(fix).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("About you")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.saveProfile()
                    if model.savedSuccessfully { dismiss() }
                }
            }
        }
    }
}
