import SwiftUI

struct OnboardingStep4AccrualRatesView: View {
    @ObservedObject var state: OnboardingState

    @State private var vacationRateText: String = "0.00"
    @State private var sickRateText: String = "0.00"

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
                    DecimalField(label: "Vacation Accrual", text: $vacationRateText)
                        .onChange(of: vacationRateText) { _, newValue in
                            state.vacationAccrualRate = Decimal(string: newValue) ?? 0
                        }
                }

                if state.sickEnabled {
                    DecimalField(label: "Sick Leave Accrual", text: $sickRateText)
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
    }
}
