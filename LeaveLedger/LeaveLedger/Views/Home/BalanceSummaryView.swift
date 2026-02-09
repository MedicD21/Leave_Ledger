import SwiftUI

struct BalanceSummaryView: View {
    let officialBalance: BalanceSnapshot
    let forecastBalance: BalanceSnapshot
    let lastPaydayDate: Date
    let forecastAsOfDate: Date
    let forecastMode: AppViewModel.ForecastMode
    let enabledLeaveTypes: [LeaveType]
    let onForecastModeChange: (AppViewModel.ForecastMode) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if enabledLeaveTypes.contains(.comp) {
                    BalanceCard(
                        title: "Comp",
                        official: officialBalance.comp,
                        forecast: forecastBalance.comp,
                        lastPayday: lastPaydayDate,
                        forecastDate: forecastAsOfDate,
                        color: .green
                    )
                }
                if enabledLeaveTypes.contains(.vacation) {
                    BalanceCard(
                        title: "Vacation",
                        official: officialBalance.vacation,
                        forecast: forecastBalance.vacation,
                        lastPayday: lastPaydayDate,
                        forecastDate: forecastAsOfDate,
                        color: .blue
                    )
                }
                if enabledLeaveTypes.contains(.sick) {
                    BalanceCard(
                        title: "Sick",
                        official: officialBalance.sick,
                        forecast: forecastBalance.sick,
                        lastPayday: lastPaydayDate,
                        forecastDate: forecastAsOfDate,
                        color: .purple
                    )
                }
            }

            // Forecast mode picker
            HStack {
                Text("Forecast as of:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { forecastMode },
                    set: { onForecastModeChange($0) }
                )) {
                    ForEach(AppViewModel.ForecastMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct BalanceCard: View {
    let title: String
    let official: Decimal
    let forecast: Decimal
    let lastPayday: Date
    let forecastDate: Date
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("Official")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(formatHours(official))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("as of \(shortDate(lastPayday))")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text("Forecast")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(formatHours(forecast))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(forecast < 0 ? .red : .primary)
                Text("as of \(shortDate(forecastDate))")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatHours(_ value: Decimal) -> String {
        let num = NSDecimalNumber(decimal: value).doubleValue
        return String(format: "%.2fh", num)
    }

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}
