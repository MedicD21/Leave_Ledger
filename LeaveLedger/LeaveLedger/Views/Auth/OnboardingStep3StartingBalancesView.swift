import SwiftUI

struct OnboardingStep3StartingBalancesView: View {
    @ObservedObject var state: OnboardingState

    @State private var compText: String = "0.00"
    @State private var vacationText: String = "0.00"
    @State private var sickText: String = "0.00"

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
                    DecimalField(label: "Comp Time", text: $compText)
                        .onChange(of: compText) { _, newValue in
                            state.compStartBalance = Decimal(string: newValue) ?? 0
                        }
                }

                if state.vacationEnabled {
                    DecimalField(label: "Vacation", text: $vacationText)
                        .onChange(of: vacationText) { _, newValue in
                            state.vacationStartBalance = Decimal(string: newValue) ?? 0
                        }
                }

                if state.sickEnabled {
                    DecimalField(label: "Sick Leave", text: $sickText)
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
    }
}
