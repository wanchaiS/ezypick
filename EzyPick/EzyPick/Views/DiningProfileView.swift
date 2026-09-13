import SwiftUI
import EzypickCore

/// Where the diner says what they cannot eat, what they would rather avoid, and the limits of
/// their lunch break.
///
/// The two lists are presented differently on purpose. What the diner *cannot* eat is a hard
/// limit the app will never trade away; what they would *rather not* eat is a preference that can
/// be. Showing them as the same kind of control would misrepresent how the app treats them.
struct DiningProfileView: View {
    @ObservedObject var model: DiningProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(DietaryConstraint.allCases, id: \.self) { requirement in
                    Toggle(requirement.spokenName.capitalized,
                           isOn: Binding(get: { model.dietaryRequirements.contains(requirement) },
                                         set: { _ in model.toggle(requirement) }))
                }
            } header: {
                Text("What you can't eat")
            } footer: {
                Text("Ezypick will never suggest somewhere that can't cater for these. It goes on what restaurants publish, so it's still worth confirming when you order.")
            }

            Section {
                Stepper("$\(model.budgetPerHead) a head", value: $model.budgetPerHead, in: 5...120, step: 5)
                Stepper("\(model.willingToWalkMinutes) min walk", value: $model.willingToWalkMinutes, in: 1...45)
                DatePicker("Usually eat at", selection: mealTimeBinding, displayedComponents: .hourAndMinute)
            } header: {
                Text("Your lunch break")
            }

            Section {
                ForEach(Cuisine.allCases, id: \.self) { cuisine in
                    Toggle(cuisine.rawValue.capitalized,
                           isOn: Binding(get: { model.avoidedCuisines.contains(cuisine) },
                                         set: { _ in model.toggle(cuisine) }))
                }
            } header: {
                Text("What you'd rather not eat")
            } footer: {
                Text("A preference, not a rule — Ezypick will avoid these unless there's nothing else nearby.")
            }

            Section {
                SecureField("Paste a key to use smarter questions", text: $model.questionServiceKey)
            } header: {
                Text("Question service (optional)")
            } footer: {
                Text("Without a key Ezypick uses its own questions, which work perfectly well.")
            }

            if let problem = model.problem {
                Section {
                    Text(problem).foregroundStyle(.red)
                    if let fix = model.howToFixIt { Text(fix).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Your profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.saveProfile()
                    if model.savedSuccessfully { dismiss() }
                }
            }
        }
    }

    private var mealTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: model.mealHour, minute: model.mealMinute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                model.mealHour = parts.hour ?? 12
                model.mealMinute = parts.minute ?? 30
            }
        )
    }
}
