import Foundation
import SwiftUI

/// Manages state for the onboarding wizard
class OnboardingState: ObservableObject {
    @Published var currentStep: Int = 1

    // MARK: - Step 1: Pay Period Configuration
    @Published var payPeriodType: PayPeriodType = .biweekly
    @Published var anchorPayday: Date = Date()

    // MARK: - Step 2: Leave Type Selection
    @Published var compEnabled: Bool = false
    @Published var vacationEnabled: Bool = false
    @Published var sickEnabled: Bool = false

    // MARK: - Step 3: Starting Balances
    @Published var compStartBalance: Decimal = 0
    @Published var vacationStartBalance: Decimal = 0
    @Published var sickStartBalance: Decimal = 0

    // MARK: - Step 4: Accrual Rates
    @Published var vacationAccrualRate: Decimal = 0
    @Published var sickAccrualRate: Decimal = 0

    // MARK: - Validation

    /// At least one leave type must be enabled
    var hasAtLeastOneLeaveType: Bool {
        compEnabled || vacationEnabled || sickEnabled
    }

    /// List of enabled leave types
    var enabledTypes: [LeaveType] {
        var types: [LeaveType] = []
        if compEnabled { types.append(.comp) }
        if vacationEnabled { types.append(.vacation) }
        if sickEnabled { types.append(.sick) }
        return types
    }

    /// Check if current step is valid and can proceed
    func canProceedFromStep(_ step: Int) -> Bool {
        switch step {
        case 1:
            return true  // Pay period always valid
        case 2:
            return hasAtLeastOneLeaveType
        case 3:
            return true  // Starting balances can be 0
        case 4:
            return true  // Accrual rates can be 0
        default:
            return false
        }
    }
}
