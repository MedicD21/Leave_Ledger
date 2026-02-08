import SwiftUI

struct LedgerView: View {
    @Bindable var viewModel: AppViewModel
    let leaveType: LeaveType
    @State private var showEntryEditor = false
    @State private var editingEntry: LeaveEntry?

    private var entries: [LeaveEntry] {
        viewModel.entriesForLeaveType(leaveType)
    }

    private var accrualInfo: String? {
        switch leaveType {
        case .vacation:
            let rate = NSDecimalNumber(decimal: viewModel.profile.vacAccrualRate).doubleValue
            return String(format: "+%.2fh per payday", rate)
        case .sick:
            let rate = NSDecimalNumber(decimal: viewModel.profile.sickAccrualRate).doubleValue
            return String(format: "+%.2fh per payday", rate)
        case .comp:
            return "Manual accrual only"
        }
    }

    var body: some View {
        List {
            // Balance summary at top
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Official Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let official = officialForType()
                        Text(formatHours(official))
                            .font(.title2.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Forecast Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let forecast = forecastForType()
                        Text(formatHours(forecast))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(forecast < 0 ? .red : .primary)
                    }
                }

                if let info = accrualInfo {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.teal)
                        Text("Accrual: \(info)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Virtual accrual events section
            if leaveType != .comp {
                Section("Upcoming Accruals") {
                    let upcomingPaydays = nextPaydays(count: 3)
                    ForEach(upcomingPaydays, id: \.self) { payday in
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .foregroundStyle(.teal)
                                .font(.caption)
                            VStack(alignment: .leading) {
                                Text("Payday Accrual")
                                    .font(.subheadline)
                                Text(DateUtils.shortDate(payday))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(accrualAmount())
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.teal)
                        }
                    }
                }
            }

            // Entries list
            Section("Entries (\(entries.count))") {
                if entries.isEmpty {
                    Text("No entries yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, id: \.id) { entry in
                        LedgerEntryRow(
                            entry: entry,
                            isPosted: viewModel.isPosted(entry),
                            payPeriod: viewModel.payPeriodFor(date: entry.date),
                            onEdit: {
                                editingEntry = entry
                                showEntryEditor = true
                            },
                            onDelete: {
                                viewModel.deleteEntry(entry)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("\(leaveType.displayName) Ledger")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingEntry = nil
                    showEntryEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEntryEditor) {
            EntryEditorView(
                viewModel: viewModel,
                initialDate: Date(),
                editingEntry: editingEntry
            )
        }
    }

    private func officialForType() -> Decimal {
        switch leaveType {
        case .comp: return viewModel.officialBalance.comp
        case .vacation: return viewModel.officialBalance.vacation
        case .sick: return viewModel.officialBalance.sick
        }
    }

    private func forecastForType() -> Decimal {
        switch leaveType {
        case .comp: return viewModel.forecastBalance.comp
        case .vacation: return viewModel.forecastBalance.vacation
        case .sick: return viewModel.forecastBalance.sick
        }
    }

    private func nextPaydays(count: Int) -> [Date] {
        let today = Date()
        var result: [Date] = []
        var current = PayPeriodService.nextPaydayOnOrAfter(date: today, anchorPayday: viewModel.profile.anchorPayday)
        for _ in 0..<count {
            result.append(current)
            current = DateUtils.addDays(current, PayPeriodService.payInterval)
        }
        return result
    }

    private func accrualAmount() -> String {
        let rate: Decimal
        switch leaveType {
        case .vacation: rate = viewModel.profile.vacAccrualRate
        case .sick: rate = viewModel.profile.sickAccrualRate
        case .comp: rate = 0
        }
        let num = NSDecimalNumber(decimal: rate).doubleValue
        return String(format: "+%.2fh", num)
    }

    private func formatHours(_ val: Decimal) -> String {
        let num = NSDecimalNumber(decimal: val).doubleValue
        return String(format: "%.2fh", num)
    }
}

struct LedgerEntryRow: View {
    let entry: LeaveEntry
    let isPosted: Bool
    let payPeriod: PayPeriod
    let onEdit: () -> Void
    let onDelete: () -> Void

    var entryColor: Color {
        switch entry.action {
        case .accrued: return .green
        case .used: return .red
        case .adjustment:
            return (entry.adjustmentSign == .negative) ? .red.opacity(0.8) : .green.opacity(0.8)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(entryColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.action.displayName)
                        .font(.subheadline.bold())
                    Spacer()
                    let h = NSDecimalNumber(decimal: entry.hours).doubleValue
                    let sign = entry.action == .used ? "-" :
                        (entry.adjustmentSign == .negative ? "-" : "+")
                    Text("\(sign)\(String(format: "%.2f", h))h")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(entryColor)
                }

                HStack(spacing: 6) {
                    Text(DateUtils.shortDate(entry.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("PP: \(payPeriod.description)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text(isPosted ? "Posted" : "Pending")
                        .font(.caption2.bold())
                        .foregroundStyle(isPosted ? .green : .orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background((isPosted ? Color.green : Color.orange).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}
