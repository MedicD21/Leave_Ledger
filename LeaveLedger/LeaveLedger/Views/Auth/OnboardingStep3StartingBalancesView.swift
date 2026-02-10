import SwiftUI

struct OnboardingStep3StartingBalancesView: View {
    @ObservedObject var state: OnboardingState
    @FocusState private var focusedField: Bool

    @State private var compText: String = ""
    @State private var vacationText: String = ""
    @State private var sickText: String = ""

    var body: some View {
        Form {
            Section {
                Text("Enter your current leave balances")
                    .font(.headline)
                    .padding(.bottom, 4)

                Text("These are your balances as of the anchor payday you selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Starting Balances (in hours)") {
                if state.compEnabled {
                    DecimalField(label: "Comp Time", text: $compText, focused: $focusedField)
                        .onChange(of: compText) { _, newValue in
                            state.compStartBalance = Decimal(string: newValue) ?? 0
                        }
                }

                if state.vacationEnabled {
                    DecimalField(label: "Vacation", text: $vacationText, focused: $focusedField)
                        .onChange(of: vacationText) { _, newValue in
                            state.vacationStartBalance = Decimal(string: newValue) ?? 0
                        }
                }

                if state.sickEnabled {
                    DecimalField(label: "Sick Leave", text: $sickText, focused: $focusedField)
                        .onChange(of: sickText) { _, newValue in
                            state.sickStartBalance = Decimal(string: newValue) ?? 0
                        }
                }

                if !state.hasAtLeastOneLeaveType {
                    Text("No leave types enabled. Go back to select at least one.")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            Section {
                Text("Tip: You can leave these at 0 if you're starting fresh or don't know your current balances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = false
                }
            }
        }
    }
}
