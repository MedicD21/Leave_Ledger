import SwiftUI

struct OnboardingStep4AccrualRatesView: View {
    @ObservedObject var state: OnboardingState
    @FocusState private var focusedField: Bool

    @State private var vacationRateText: String = ""
    @State private var sickRateText: String = ""

    var body: some View {
        Form {
            Section {
                Text("Configure accrual rates")
                    .font(.headline)
                    .padding(.bottom, 4)

                Text("How many hours do you earn per pay period? Comp time typically doesn't accrue automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Accrual Rates (hours per pay period)") {
                if state.vacationEnabled {
                    DecimalField(label: "Vacation Accrual", text: $vacationRateText, focused: $focusedField)
                        .onChange(of: vacationRateText) { _, newValue in
                            state.vacationAccrualRate = Decimal(string: newValue) ?? 0
                        }
                }

                if state.sickEnabled {
                    DecimalField(label: "Sick Leave Accrual", text: $sickRateText, focused: $focusedField)
                        .onChange(of: sickRateText) { _, newValue in
                            state.sickAccrualRate = Decimal(string: newValue) ?? 0
                        }
                }

                if !state.vacationEnabled && !state.sickEnabled {
                    Text("No accruals needed for the leave types you selected.")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Almost done!")
                        .font(.subheadline.weight(.medium))

                    Text("After completing setup, you'll be able to track your leave balances, add entries, and see forecasts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
