import Foundation
import UIKit

/// Handles CSV and PDF export of leave entries.
struct ExportService {
    // MARK: - CSV Export

    func exportCSV(entries: [LeaveEntry]) -> URL? {
        var csv = "Date,Leave Type,Action,Hours,Adjustment Sign,Notes,Source,Created At\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let date = dateFormatter.string(from: entry.date)
            let type = entry.leaveType.displayName
            let action = entry.action.displayName
            let hours = NSDecimalNumber(decimal: entry.hours).doubleValue
            let sign = entry.adjustmentSign?.rawValue ?? ""
            let notes = (entry.notes ?? "").replacingOccurrences(of: ",", with: ";")
            let source = entry.source.rawValue
            let created = dateFormatter.string(from: entry.createdAt)

            csv += "\(date),\(type),\(action),\(String(format: "%.2f", hours)),\(sign),\(notes),\(source),\(created)\n"
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("LeaveLedger_Export_\(dateFormatter.string(from: Date())).csv")

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - PDF Export

    func exportPDF(
        entries: [LeaveEntry],
        officialBalance: BalanceSnapshot,
        forecastBalance: BalanceSnapshot,
        month: Date
    ) -> URL? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40

        let monthStr = DateUtils.monthYear(for: month)
        let dateStr = DateUtils.shortDate(Date())

        let pdfRenderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        let data = pdfRenderer.pdfData { context in
            context.beginPage()
            var yPos: CGFloat = margin

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.label
            ]
            let title = "Leave Ledger - \(monthStr)"
            title.draw(at: CGPoint(x: margin, y: yPos), withAttributes: titleAttrs)
            yPos += 30

            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.secondaryLabel
            ]
            "Generated: \(dateStr)".draw(at: CGPoint(x: margin, y: yPos), withAttributes: subtitleAttrs)
            yPos += 25

            // Balance Summary
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.label
            ]
            "Balance Summary".draw(at: CGPoint(x: margin, y: yPos), withAttributes: headerAttrs)
            yPos += 22

            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label
            ]

            let balanceLines = [
                "                  Official      Forecast",
                String(format: "Comp:            %8.2fh     %8.2fh",
                       NSDecimalNumber(decimal: officialBalance.comp).doubleValue,
                       NSDecimalNumber(decimal: forecastBalance.comp).doubleValue),
                String(format: "Vacation:        %8.2fh     %8.2fh",
                       NSDecimalNumber(decimal: officialBalance.vacation).doubleValue,
                       NSDecimalNumber(decimal: forecastBalance.vacation).doubleValue),
                String(format: "Sick:            %8.2fh     %8.2fh",
                       NSDecimalNumber(decimal: officialBalance.sick).doubleValue,
                       NSDecimalNumber(decimal: forecastBalance.sick).doubleValue)
            ]

            for line in balanceLines {
                line.draw(at: CGPoint(x: margin, y: yPos), withAttributes: bodyAttrs)
                yPos += 16
            }
            yPos += 15

            // Entries table
            "Entries".draw(at: CGPoint(x: margin, y: yPos), withAttributes: headerAttrs)
            yPos += 22

            let tableHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]

            let tableHeader = "\(pad("Date", to: 12)) \(pad("Type", to: 10)) \(pad("Action", to: 10)) \(pad("Hours", to: 8))  Notes"
            tableHeader.draw(at: CGPoint(x: margin, y: yPos), withAttributes: tableHeaderAttrs)
            yPos += 14

            let entryAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.label
            ]

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            // Filter entries for the displayed month
            let cal = Calendar.current
            let monthEntries = entries
                .filter {
                    cal.isDate($0.date, equalTo: month, toGranularity: .month)
                }
                .sorted { $0.date < $1.date }

            for entry in monthEntries {
                if yPos > pageHeight - margin - 20 {
                    context.beginPage()
                    yPos = margin
                }

                let h = NSDecimalNumber(decimal: entry.hours).doubleValue
                let sign = entry.action == .used ? "-" : (entry.adjustmentSign == .negative ? "-" : "+")
                let dateStr = dateFormatter.string(from: entry.date)
                let typeStr = entry.leaveType.displayName
                let actionStr = entry.action.displayName
                let hoursStr = String(format: "%7.2f", h)
                let notes = entry.notes ?? ""
                let line = "\(pad(dateStr, to: 12)) \(pad(typeStr, to: 10)) \(pad(actionStr, to: 10)) \(sign)\(hoursStr)  \(notes)"
                line.draw(at: CGPoint(x: margin, y: yPos), withAttributes: entryAttrs)
                yPos += 13
            }

            if monthEntries.isEmpty {
                "No entries for this month.".draw(at: CGPoint(x: margin, y: yPos), withAttributes: subtitleAttrs)
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("LeaveLedger_\(monthStr.replacingOccurrences(of: " ", with: "_")).pdf")

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    private func pad(_ value: String, to width: Int) -> String {
        let trimmed = value.replacingOccurrences(of: "\n", with: " ")
        if trimmed.count >= width {
            return String(trimmed.prefix(width))
        }
        return trimmed + String(repeating: " ", count: width - trimmed.count)
    }
}

