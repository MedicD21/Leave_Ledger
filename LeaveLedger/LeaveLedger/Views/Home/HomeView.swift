import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: AppViewModel
    @State private var showDaySheet = false
    @State private var showBalancePopover = false
    @State private var popoverDate: Date = Date()
    @State private var popoverBalance: BalanceSnapshot = .zero
    @State private var refreshID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            // Balance Summary
            BalanceSummaryView(
                officialBalance: viewModel.officialBalance,
                forecastBalance: viewModel.forecastBalance,
                lastPaydayDate: viewModel.lastPaydayDate,
                forecastAsOfDate: viewModel.forecastAsOfDate,
                forecastMode: viewModel.forecastMode,
                enabledLeaveTypes: viewModel.profile.enabledLeaveTypes,
                onForecastModeChange: { viewModel.setForecastMode($0) }
            )

            // Month Navigation
            HStack {
                Button(action: viewModel.goToPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }

                Spacer()

                Text(DateUtils.monthYear(for: viewModel.displayedMonth))
                    .font(.headline)

                Spacer()

                Button("Today") {
                    viewModel.goToToday()
                }
                .font(.subheadline)

                Button(action: viewModel.goToNextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Calendar Grid
            let entriesByDate = Dictionary(
                grouping: viewModel.entries.filter { entry in
                    let cal = Calendar.current
                    let monthComps = cal.dateComponents([.year, .month], from: viewModel.displayedMonth)
                    let entryComps = cal.dateComponents([.year, .month], from: entry.date)
                    return monthComps.year == entryComps.year && monthComps.month == entryComps.month
                },
                by: { Calendar.current.startOfDay(for: $0.date) }
            )

            let cal = Calendar.current
            let monthComps = cal.dateComponents([.year, .month], from: viewModel.displayedMonth)
            let firstDay = cal.date(from: monthComps)!
            let lastDay = cal.date(byAdding: DateComponents(month: 1, day: -1), to: firstDay)!
            let notesByDate = Dictionary(
                uniqueKeysWithValues: viewModel.store.notes(from: firstDay, to: lastDay).map {
                    (cal.startOfDay(for: $0.date), $0)
                }
            )

            CalendarGridView(
                displayedMonth: viewModel.displayedMonth,
                selectedDate: viewModel.selectedDate,
                entriesByDate: entriesByDate,
                notesByDate: notesByDate,
                anchorPayday: viewModel.profile.anchorPayday,
                onDateTap: { date in
                    viewModel.selectDate(date)
                    showDaySheet = true
                },
                onBalanceTap: { date in
                    popoverDate = date
                    popoverBalance = viewModel.forecastForDate(date)
                    showBalancePopover = true
                }
            )
            .padding(.horizontal, 8)
            .id(refreshID)

            Spacer()
        }
        .sheet(isPresented: $showDaySheet, onDismiss: {
            // Refresh calendar to reflect any note changes
            refreshID = UUID()
        }) {
            DayDetailSheet(viewModel: viewModel, date: viewModel.selectedDate)
        }
        .alert("Forecast Balances", isPresented: $showBalancePopover) {
            Button("OK") { showBalancePopover = false }
        } message: {
            let compStr = formatHours(popoverBalance.comp)
            let vacStr = formatHours(popoverBalance.vacation)
            let sickStr = formatHours(popoverBalance.sick)
            Text("As of \(DateUtils.shortDate(popoverDate))\n\nComp: \(compStr)\nVacation: \(vacStr)\nSick: \(sickStr)")
        }
    }

    private func formatHours(_ value: Decimal) -> String {
        let num = NSDecimalNumber(decimal: value).doubleValue
        return String(format: "%.2fh", num)
    }
}
