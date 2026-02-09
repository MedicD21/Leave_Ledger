import SwiftUI

struct OnboardingStep2LeaveTypesView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        Form {
            Section {
                Text("Select the types of leave you want to track")
                    .font(.headline)
                    .padding(.bottom, 4)

                if !state.hasAtLeastOneLeaveType {
                    Label("You must enable at least one leave type", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Leave Types") {
                Toggle(isOn: $state.compEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Comp Time", systemImage: "clock.arrow.circlepath")
                            .font(.body.weight(.medium))
                        Text("Compensatory time earned and used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.green)

                Toggle(isOn: $state.vacationEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Vacation", systemImage: "airplane")
                            .font(.body.weight(.medium))
                        Text("Paid vacation leave with accrual")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Toggle(isOn: $state.sickEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Sick Leave", systemImage: "cross.case")
                            .font(.body.weight(.medium))
                        Text("Sick leave with accrual")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.purple)
            }
        }
    }
}
