import SwiftUI

struct OnboardingStep1PayPeriodView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        Form {
            Section {
                Text("Configure your pay schedule")
                    .font(.headline)
                    .padding(.bottom, 4)

                Text("This determines when leave accruals are posted and how balances are calculated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pay Period Type") {
                Picker("Frequency", selection: $state.payPeriodType) {
                    ForEach(PayPeriodType.allCases) { type in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                            Text(type.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Anchor Payday") {
                DatePicker(
                    "Select a payday",
                    selection: $state.anchorPayday,
                    displayedComponents: .date
                )

                Text("Choose any recent or upcoming payday. This is used as a reference point for calculating future pay periods.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
