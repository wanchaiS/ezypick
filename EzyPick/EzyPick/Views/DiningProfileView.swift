import SwiftUI

/// Where the diner says what their lunch break allows: what they will spend, and how far they
/// will walk.
///
/// - Note: Short on purpose. A setting that never changes which restaurants come back has no
///   business on this screen.
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
