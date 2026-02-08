import SwiftUI

struct DayDetailSheet: View {
    @Bindable var viewModel: AppViewModel
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @State private var showEntryEditor = false
    @State private var editingEntry: LeaveEntry?

    private var dayEntries: [LeaveEntry] {
        viewModel.entriesForDate(date)
    }

    private var payPeriod: PayPeriod {
        viewModel.payPeriodFor(date: date)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Date")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(DateUtils.shortDate(date))
                    }
                    HStack {
                        Text("Pay Period")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(payPeriod.description)
                            .font(.caption)
                    }
                    if viewModel.isPayday(date) {
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundStyle(.green)
                            Text("Payday")
                                .foregroundStyle(.green)
                                .font(.subheadline.bold())
                        }
                    }
                }

                // Forecast balances as of this date
                Section("Forecast as of \(DateUtils.shortDate(date))") {
                    let forecast = viewModel.forecastForDate(date)
                    BalanceRow(label: "Comp", value: forecast.comp, color: .green)
                    BalanceRow(label: "Vacation", value: forecast.vacation, color: .blue)
                    BalanceRow(label: "Sick", value: forecast.sick, color: .purple)
                }

                // Entries
                Section("Entries") {
                    if dayEntries.isEmpty {
                        Text("No entries for this date")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(dayEntries, id: \.id) { entry in
                            EntryRowView(
                                entry: entry,
                                isPosted: viewModel.isPosted(entry),
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
            .navigationTitle(DateUtils.shortDate(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
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
                    initialDate: date,
                    editingEntry: editingEntry
                )
            }
        }
    }
}

struct BalanceRow: View {
    let label: String
    let value: Decimal
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
            Spacer()
            Text(formatHours(value))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(value < 0 ? .red : .primary)
        }
    }

    private func formatHours(_ val: Decimal) -> String {
        let num = NSDecimalNumber(decimal: val).doubleValue
        return String(format: "%.2fh", num)
    }
}

struct EntryRowView: View {
    let entry: LeaveEntry
    let isPosted: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var entryColor: Color {
        switch entry.action {
        case .accrued:
            return entry.leaveType == .comp ? .green : .teal
        case .used:
            return .red
        case .adjustment:
            return (entry.adjustmentSign == .negative) ? .red.opacity(0.8) : .green.opacity(0.8)
        }
    }

    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(entryColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.chipLabel)
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    Text(isPosted ? "Posted" : "Pending")
                        .font(.caption2)
                        .foregroundStyle(isPosted ? .green : .orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (isPosted ? Color.green : Color.orange).opacity(0.15)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
