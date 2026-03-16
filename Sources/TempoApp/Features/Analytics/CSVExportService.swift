import Foundation
import SwiftData

struct CSVExportRow: Equatable {
    let date: String
    let startTime: String
    let endTime: String
    let durationMinutes: Int
    let projectName: String
}

@MainActor
final class CSVExportService {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func exportRows(range: AnalyticsRange, referenceDate: Date, dayCutoffHour: Int = 6) -> [CSVExportRow] {
        let analyticsStore = AnalyticsStore(modelContext: modelContext)
        let summary = analyticsStore.summary(
            range: range,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCutoffHour: dayCutoffHour
        )

        return summary.allocatedIntervals.map { interval in
            CSVExportRow(
                date: dateFormatter.string(from: interval.startDate),
                startTime: timeFormatter.string(from: interval.startDate),
                endTime: timeFormatter.string(from: interval.endDate),
                durationMinutes: max(Int(interval.duration / 60), 0),
                projectName: interval.bucket.displayName
            )
        }
    }

    func csvString(range: AnalyticsRange, referenceDate: Date, dayCutoffHour: Int = 6) -> String {
        let header = "date,start_time,end_time,duration_minutes,project_name"
        let rows = exportRows(range: range, referenceDate: referenceDate, dayCutoffHour: dayCutoffHour).map { row in
            [
                row.date,
                row.startTime,
                row.endTime,
                String(row.durationMinutes),
                Self.escape(row.projectName),
            ]
            .joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }

        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
