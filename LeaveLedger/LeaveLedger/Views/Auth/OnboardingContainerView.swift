import SwiftUI

struct OnboardingContainerView: View {
    @StateObject private var onboardingState = OnboardingState()
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress Indicator
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { step in
                        Rectangle()
                            .fill(step <= onboardingState.currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding()

                // Current Step View
                Group {
                    switch onboardingState.currentStep {
                    case 1:
                        OnboardingStep1PayPeriodView(state: onboardingState)
                    case 2:
                        OnboardingStep2LeaveTypesView(state: onboardingState)
                    case 3:
                        OnboardingStep3StartingBalancesView(state: onboardingState)
                    case 4:
                        OnboardingStep4AccrualRatesView(state: onboardingState)
                    default:
                        EmptyView()
                    }
                }

                Spacer()

                // Navigation Buttons
                HStack {
                    if onboardingState.currentStep > 1 {
                        Button("Back") {
                            withAnimation {
                                onboardingState.currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(onboardingState.currentStep == 4 ? "Complete" : "Next") {
                        if onboardingState.currentStep == 4 {
                            completeOnboarding()
                        } else {
                            withAnimation {
                                onboardingState.currentStep += 1
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!onboardingState.canProceedFromStep(onboardingState.currentStep))
                }
                .padding()
            }
            .navigationTitle("Setup Your Account")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
        }
    }

    private func completeOnboarding() {
        // Save configuration to UserProfile
        viewModel.store.updateProfile { profile in
            profile.payPeriodType = onboardingState.payPeriodType.rawValue
            profile.payPeriodInterval = onboardingState.payPeriodType.intervalDays
            profile.anchorPayday = onboardingState.anchorPayday

            profile.compEnabled = onboardingState.compEnabled
            profile.vacationEnabled = onboardingState.vacationEnabled
            profile.sickEnabled = onboardingState.sickEnabled

            profile.compStartBalance = onboardingState.compStartBalance
            profile.vacStartBalance = onboardingState.vacationStartBalance
            profile.sickStartBalance = onboardingState.sickStartBalance

            profile.vacAccrualRate = onboardingState.vacationAccrualRate
            profile.sickAccrualRate = onboardingState.sickAccrualRate

            profile.isSetupComplete = true
        }

        // Refresh data and sync
        viewModel.refreshData()
        viewModel.syncWithSupabase()

        // Dismiss onboarding
        dismiss()
    }
}
