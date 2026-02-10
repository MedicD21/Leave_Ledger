import SwiftUI

struct CalendarGridView: View {
    let displayedMonth: Date
    let selectedDate: Date
    let entriesByDate: [Date: [LeaveEntry]]
    let notesByDate: [Date: DateNote]
    let anchorPayday: Date
    let onDateTap: (Date) -> Void
    let onBalanceTap: (Date) -> Void

    private let calendar = Calendar.current
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var monthDates: [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        let firstOfMonth = calendar.date(from: comps)!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) // 1=Sun
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count

        var dates: [Date?] = []
        // Leading empty cells
        for _ in 0..<(firstWeekday - 1) {
            dates.append(nil)
        }
        for day in 1...daysInMonth {
            var dc = comps
            dc.day = day
            dc.hour = 12
            dates.append(calendar.date(from: dc))
        }
        // Trailing empty cells to fill last row
        while dates.count % 7 != 0 {
            dates.append(nil)
        }
        return dates
    }

    var body: some View {
        VStack(spacing: 0) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            // Day grid
            let rows = monthDates.chunked(into: 7)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, dateOpt in
                        if let date = dateOpt {
                            DayCellView(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                isPayday: PayPeriodService.isPayday(date, anchorPayday: anchorPayday),
                                entries: entriesByDate[calendar.startOfDay(for: date)] ?? [],
                                note: notesByDate[calendar.startOfDay(for: date)],
                                onTap: { onDateTap(date) },
                                onBalanceTap: { onBalanceTap(date) }
                            )
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 60)
                        }
                    }
                }
            }
        }
    }
}

struct DayCellView: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isPayday: Bool
    let entries: [LeaveEntry]
    let note: DateNote?
    let onTap: () -> Void
    let onBalanceTap: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : .primary)
                    .frame(width: 22, height: 22)
                    .background(isToday ? Color.blue : Color.clear)
                    .clipShape(Circle())

                Spacer()

                if !entries.isEmpty {
                    Button(action: onBalanceTap) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isPayday {
                Text("Payday")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }

            // Note chip (if exists)
            if let note = note {
                NoteChipView(note: note)
            }

            // Entry chips (max 2 shown, then "+N")
            let displayEntries = Array(entries.prefix(2))
            ForEach(displayEntries, id: \.id) { entry in
                EntryChipView(entry: entry)
            }
            if entries.count > 2 {
                Text("+\(entries.count - 2)")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(2)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.blue.opacity(0.5) : Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct NoteChipView: View {
    let note: DateNote

    var body: some View {
        Text(note.title)
            .font(.system(size: 7, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(note.color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .lineLimit(1)
    }
}

struct EntryChipView: View {
    let entry: LeaveEntry

    var chipColor: Color {
        switch entry.action {
        case .accrued:
            return entry.leaveType == .comp ? .green : .teal
        case .used:
            return .red
        case .adjustment:
            if let sign = entry.adjustmentSign {
                return sign == .positive ? .green.opacity(0.8) : .red.opacity(0.8)
            }
            return .orange
        }
    }

    var body: some View {
        let h = NSDecimalNumber(decimal: entry.hours).doubleValue
        let sign = entry.action == .used ? "-" : (entry.action == .accrued ? "+" : (entry.adjustmentSign == .negative ? "-" : "+"))
        Text("\(entry.leaveType.displayName.prefix(1))\(sign)\(String(format: "%.0f", h))")
            .font(.system(size: 7, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(chipColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .lineLimit(1)
    }
}

// Array chunking helper
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
