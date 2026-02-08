import SwiftUI

struct EntryEditorView: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let editingEntry: LeaveEntry?

    @State private var date: Date
    @State private var leaveType: LeaveType
    @State private var action: LeaveAction
    @State private var hours: Decimal
    @State private var adjustmentSign: AdjustmentSign
    @State private var notes: String
    @State private var hoursText: String

    init(viewModel: AppViewModel, initialDate: Date, editingEntry: LeaveEntry?) {
        self.viewModel = viewModel
        self.initialDate = initialDate
        self.editingEntry = editingEntry

        if let entry = editingEntry {
            _date = State(initialValue: entry.date)
            _leaveType = State(initialValue: entry.leaveType)
            _action = State(initialValue: entry.action)
            _hours = State(initialValue: entry.hours)
            _adjustmentSign = State(initialValue: entry.adjustmentSign ?? .positive)
            _notes = State(initialValue: entry.notes ?? "")
            let h = NSDecimalNumber(decimal: entry.hours).doubleValue
            _hoursText = State(initialValue: String(format: "%.2f", h))
        } else {
            _date = State(initialValue: initialDate)
            _leaveType = State(initialValue: .comp)
            _action = State(initialValue: .used)
            _hours = State(initialValue: Decimal(string: "8.00")!)
            _adjustmentSign = State(initialValue: .positive)
            _notes = State(initialValue: "")
            _hoursText = State(initialValue: "8.00")
        }
    }

    private var isEditing: Bool { editingEntry != nil }

    private var availableActions: [LeaveAction] {
        switch leaveType {
        case .comp:
            return [.accrued, .used, .adjustment]
        case .vacation, .sick:
            return [.used, .adjustment]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Picker("Leave Type", selection: $leaveType) {
                        ForEach(LeaveType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: leaveType) { _, newValue in
                        // Reset action if not available for new type
                        if !availableActions.contains(action) {
                            action = availableActions.first ?? .used
                        }
                    }

                    Picker("Action", selection: $action) {
                        ForEach(availableActions) { act in
                            Text(act.displayName).tag(act)
                        }
                    }

                    if action == .adjustment {
                        Picker("Adjustment Direction", selection: $adjustmentSign) {
                            Text("Positive (+)").tag(AdjustmentSign.positive)
                            Text("Negative (-)").tag(AdjustmentSign.negative)
                        }
                    }
                }

                Section("Hours") {
                    HStack {
                        Text("Hours:")
                        TextField("0.00", text: $hoursText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: hoursText) { _, newValue in
                                if let val = Decimal(string: newValue) {
                                    hours = val
                                }
                            }
                    }

                    // Stepper
                    HStack {
                        Button {
                            adjustHours(by: Decimal(string: "-0.25")!)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(formatHours(hours))
                            .font(.title2.monospacedDigit().bold())

                        Spacer()

                        Button {
                            adjustHours(by: Decimal(string: "0.25")!)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)

                    // Quick buttons
                    HStack(spacing: 12) {
                        Text("Quick:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        quickButton(hours: 5)
                        quickButton(hours: 12)
                        quickButton(hours: 24)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let entry = editingEntry {
                                viewModel.deleteEntry(entry)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Entry")
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Entry" : "Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveEntry()
                        dismiss()
                    }
                    .bold()
                    .disabled(hours <= 0)
                }
            }
        }
    }

    private func quickButton(hours quickHours: Int) -> some View {
        Button("\(quickHours)h") {
            hours = Decimal(quickHours)
            hoursText = String(format: "%.2f", Double(quickHours))
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .font(.caption.bold())
    }

    private func adjustHours(by amount: Decimal) {
        let newVal = hours + amount
        if newVal >= 0 {
            hours = newVal
            hoursText = formatHoursRaw(hours)
        }
    }

    private func formatHours(_ val: Decimal) -> String {
        let num = NSDecimalNumber(decimal: val).doubleValue
        return String(format: "%.2fh", num)
    }

    private func formatHoursRaw(_ val: Decimal) -> String {
        let num = NSDecimalNumber(decimal: val).doubleValue
        return String(format: "%.2f", num)
    }

    private func saveEntry() {
        let adjSign: AdjustmentSign? = (action == .adjustment) ? adjustmentSign : nil
        let noteStr: String? = notes.isEmpty ? nil : notes

        if let existing = editingEntry {
            viewModel.updateEntry(
                existing,
                date: date,
                leaveType: leaveType,
                action: action,
                hours: hours,
                adjustmentSign: adjSign,
                notes: noteStr
            )
        } else {
            viewModel.addEntry(
                date: date,
                leaveType: leaveType,
                action: action,
                hours: hours,
                adjustmentSign: adjSign,
                notes: noteStr
            )
        }
    }
}
