import Foundation
import UIKit
import OSLog

/// Handles CSV and PDF export of leave entries.
struct ExportService {
    // MARK: - CSV Export

    /// Properly escapes a CSV field according to RFC 4180.
    /// Wraps the field in quotes if it contains comma, quote, or newline.
    /// Doubles any quotes within the field.
    private func escapeCSVField(_ field: String) -> String {
        // Check if field needs quoting
        let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")

        if needsQuoting {
            // Double any existing quotes and wrap in quotes
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    func exportCSV(entries: [LeaveEntry]) -> URL? {
        os_log(.info, log: Logger.export, "Starting CSV export with %d entries", entries.count)

        var csv = "Date,Leave Type,Action,Hours,Adjustment Sign,Notes,Source,Created At\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let date = escapeCSVField(dateFormatter.string(from: entry.date))
            let type = escapeCSVField(entry.leaveType.displayName)
            let action = escapeCSVField(entry.action.displayName)
            let hours = String(format: "%.2f", NSDecimalNumber(decimal: entry.hours).doubleValue)
            let sign = escapeCSVField(entry.adjustmentSign?.rawValue ?? "")
            let notes = escapeCSVField(entry.notes ?? "")
            let source = escapeCSVField(entry.source.rawValue)
            let created = escapeCSVField(dateFormatter.string(from: entry.createdAt))

            csv += "\(date),\(type),\(action),\(hours),\(sign),\(notes),\(source),\(created)\n"
        }

        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            os_log(.error, log: Logger.export, "Failed to access documents directory")
            return nil
        }
        let fileURL = documentsDir.appendingPathComponent("LeaveLedger_Export_\(dateFormatter.string(from: Date())).csv")

        os_log(.info, log: Logger.export, "CSV content size: %d bytes", csv.utf8.count)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)

            // Set file attributes to ensure it's accessible for sharing
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = fileURL
            try mutableURL.setResourceValues(resourceValues)

            os_log(.info, log: Logger.export, "CSV export successful: %@", fileURL.path)
            return fileURL
        } catch {
            os_log(.error, log: Logger.export, "Failed to write CSV file: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - PDF Export

    // PDF page constants (US Letter size)
    private enum PDFConstants {
        static let pageWidth: CGFloat = 612      // 8.5 inches at 72 DPI
        static let pageHeight: CGFloat = 792     // 11 inches at 72 DPI
        static let margin: CGFloat = 50
        static let titleFontSize: CGFloat = 20
        static let headerFontSize: CGFloat = 16
        static let subtitleFontSize: CGFloat = 10
        static let bodyFontSize: CGFloat = 11
        static let tableFontSize: CGFloat = 10
        static let lineWidth: CGFloat = 1.0
        static let lightLineWidth: CGFloat = 0.5
    }

    func exportPDF(
        entries: [LeaveEntry],
        officialBalance: BalanceSnapshot,
        forecastBalance: BalanceSnapshot,
        month: Date
    ) -> URL? {
        let pageWidth = PDFConstants.pageWidth
        let pageHeight = PDFConstants.pageHeight
        let margin = PDFConstants.margin

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
                .font: UIFont.boldSystemFont(ofSize: PDFConstants.titleFontSize),
                .foregroundColor: UIColor.black
            ]
            let title = "Leave Ledger - \(monthStr)"
            title.draw(at: CGPoint(x: margin, y: yPos), withAttributes: titleAttrs)
            yPos += 28

            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: PDFConstants.subtitleFontSize),
                .foregroundColor: UIColor.gray
            ]
            "Generated: \(dateStr)".draw(at: CGPoint(x: margin, y: yPos), withAttributes: subtitleAttrs)
            yPos += 20

            // Horizontal line under header
            drawHorizontalLine(from: margin, to: pageWidth - margin, at: yPos, width: PDFConstants.lineWidth, color: UIColor.black)
            yPos += 25

            // Balance Summary
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: PDFConstants.headerFontSize),
                .foregroundColor: UIColor.black
            ]
            "Balance Summary".draw(at: CGPoint(x: margin, y: yPos), withAttributes: headerAttrs)
            yPos += 25

            // Balance table headers
            let tableHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: PDFConstants.bodyFontSize),
                .foregroundColor: UIColor.darkGray
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: PDFConstants.bodyFontSize, weight: .regular),
                .foregroundColor: UIColor.black
            ]

            // Column positions
            let col1X = margin + 10
            let col2X = margin + 200
            let col3X = margin + 320

            // Draw table header background
            let headerRect = CGRect(x: margin, y: yPos - 2, width: pageWidth - 2 * margin, height: 20)
            UIColor(white: 0.95, alpha: 1.0).setFill()
            UIBezierPath(rect: headerRect).fill()

            "Leave Type".draw(at: CGPoint(x: col1X, y: yPos), withAttributes: tableHeaderAttrs)
            "Official".draw(at: CGPoint(x: col2X, y: yPos), withAttributes: tableHeaderAttrs)
            "Forecast".draw(at: CGPoint(x: col3X, y: yPos), withAttributes: tableHeaderAttrs)
            yPos += 22

            // Light line under header
            drawHorizontalLine(from: margin, to: pageWidth - margin, at: yPos, width: PDFConstants.lightLineWidth, color: UIColor.lightGray)
            yPos += 12

            // Balance rows
            let balanceData = [
                ("Comp", officialBalance.comp, forecastBalance.comp),
                ("Vacation", officialBalance.vacation, forecastBalance.vacation),
                ("Sick", officialBalance.sick, forecastBalance.sick)
            ]

            for (type, official, forecast) in balanceData {
                type.draw(at: CGPoint(x: col1X, y: yPos), withAttributes: bodyAttrs)
                String(format: "%.2f hours", NSDecimalNumber(decimal: official).doubleValue)
                    .draw(at: CGPoint(x: col2X, y: yPos), withAttributes: bodyAttrs)
                String(format: "%.2f hours", NSDecimalNumber(decimal: forecast).doubleValue)
                    .draw(at: CGPoint(x: col3X, y: yPos), withAttributes: bodyAttrs)
                yPos += 18
            }

            // Bottom line of balance table
            drawHorizontalLine(from: margin, to: pageWidth - margin, at: yPos, width: PDFConstants.lightLineWidth, color: UIColor.lightGray)
            yPos += 30

            // Entries table
            "Entries".draw(at: CGPoint(x: margin, y: yPos), withAttributes: headerAttrs)
            yPos += 25

            // Entries table header
            let entryHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: PDFConstants.tableFontSize),
                .foregroundColor: UIColor.darkGray
            ]
            let entryBodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: PDFConstants.tableFontSize, weight: .regular),
                .foregroundColor: UIColor.black
            ]

            // Column positions for entries
            let entryCol1X = margin + 10      // Date
            let entryCol2X = margin + 110     // Type
            let entryCol3X = margin + 200     // Action
            let entryCol4X = margin + 280     // Hours
            let entryCol5X = margin + 350     // Notes

            // Draw entry header background
            let entryHeaderRect = CGRect(x: margin, y: yPos - 2, width: pageWidth - 2 * margin, height: 20)
            UIColor(white: 0.95, alpha: 1.0).setFill()
            UIBezierPath(rect: entryHeaderRect).fill()

            "Date".draw(at: CGPoint(x: entryCol1X, y: yPos), withAttributes: entryHeaderAttrs)
            "Type".draw(at: CGPoint(x: entryCol2X, y: yPos), withAttributes: entryHeaderAttrs)
            "Action".draw(at: CGPoint(x: entryCol3X, y: yPos), withAttributes: entryHeaderAttrs)
            "Hours".draw(at: CGPoint(x: entryCol4X, y: yPos), withAttributes: entryHeaderAttrs)
            "Notes".draw(at: CGPoint(x: entryCol5X, y: yPos), withAttributes: entryHeaderAttrs)
            yPos += 22

            // Light line under header
            drawHorizontalLine(from: margin, to: pageWidth - margin, at: yPos, width: PDFConstants.lightLineWidth, color: UIColor.lightGray)
            yPos += 12

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"

            // Filter entries for the displayed month
            let cal = Calendar.current
            let monthEntries = entries
                .filter {
                    cal.isDate($0.date, equalTo: month, toGranularity: .month)
                }
                .sorted { $0.date < $1.date }

            for entry in monthEntries {
                if yPos > pageHeight - margin - 30 {
                    context.beginPage()
                    yPos = margin
                    "Entries (continued)".draw(at: CGPoint(x: margin, y: yPos), withAttributes: headerAttrs)
                    yPos += 25
                }

                let h = NSDecimalNumber(decimal: entry.hours).doubleValue
                let sign = entry.action == .used ? "-" : (entry.adjustmentSign == .negative ? "-" : "+")
                let dateStr = dateFormatter.string(from: entry.date)
                let typeStr = entry.leaveType.displayName
                let actionStr = entry.action.displayName
                let hoursStr = String(format: "%@%.2f", sign, h)
                let notes = entry.notes ?? ""

                dateStr.draw(at: CGPoint(x: entryCol1X, y: yPos), withAttributes: entryBodyAttrs)
                typeStr.draw(at: CGPoint(x: entryCol2X, y: yPos), withAttributes: entryBodyAttrs)
                actionStr.draw(at: CGPoint(x: entryCol3X, y: yPos), withAttributes: entryBodyAttrs)
                hoursStr.draw(at: CGPoint(x: entryCol4X, y: yPos), withAttributes: entryBodyAttrs)

                // Truncate notes if too long
                let maxNotesLength = 30
                let displayNotes = notes.count > maxNotesLength ? String(notes.prefix(maxNotesLength)) + "..." : notes
                displayNotes.draw(at: CGPoint(x: entryCol5X, y: yPos), withAttributes: entryBodyAttrs)

                yPos += 16
            }

            if monthEntries.isEmpty {
                yPos += 10
                "No entries for this month.".draw(at: CGPoint(x: margin + 10, y: yPos), withAttributes: subtitleAttrs)
            } else {
                // Bottom line of entries table
                drawHorizontalLine(from: margin, to: pageWidth - margin, at: yPos, width: PDFConstants.lightLineWidth, color: UIColor.lightGray)
            }
        }

        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            os_log(.error, log: Logger.export, "Failed to access documents directory")
            return nil
        }
        let fileURL = documentsDir.appendingPathComponent("LeaveLedger_\(monthStr.replacingOccurrences(of: " ", with: "_")).pdf")

        do {
            try data.write(to: fileURL)

            // Set file attributes to ensure it's accessible for sharing
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = fileURL
            try mutableURL.setResourceValues(resourceValues)

            os_log(.info, log: Logger.export, "PDF export successful: %@", fileURL.path)
            return fileURL
        } catch {
            os_log(.error, log: Logger.export, "Failed to write PDF file: %@", error.localizedDescription)
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

    private func drawHorizontalLine(from x1: CGFloat, to x2: CGFloat, at y: CGFloat, width: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x1, y: y))
        path.addLine(to: CGPoint(x: x2, y: y))
        color.setStroke()
        path.lineWidth = width
        path.stroke()
    }
}

