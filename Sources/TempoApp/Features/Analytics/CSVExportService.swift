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

    func exportRows(range: AnalyticsRange, referenceDate: Date) -> [CSVExportRow] {
        let analyticsStore = AnalyticsStore(modelContext: modelContext)
        let period = analyticsStore.period(for: range, referenceDate: referenceDate, calendar: calendar)
        let descriptor = FetchDescriptor<TimeEntryRecord>(sortBy: [SortDescriptor(\.startAt)])
        let entries = ((try? modelContext.fetch(descriptor)) ?? []).filter { entry in
            entry.endAt >= period.startDate && entry.endAt < period.endDate
        }

        return entries.sorted { $0.startAt < $1.startAt }.map { entry in
            CSVExportRow(
                date: dateFormatter.string(from: entry.startAt),
                startTime: timeFormatter.string(from: entry.startAt),
                endTime: timeFormatter.string(from: entry.endAt),
                durationMinutes: max(Int(entry.endAt.timeIntervalSince(entry.startAt) / 60), 0),
                projectName: entry.project?.name ?? "Unassigned"
            )
        }
    }

    func csvString(range: AnalyticsRange, referenceDate: Date) -> String {
        let header = "date,start_time,end_time,duration_minutes,project_name"
        let rows = exportRows(range: range, referenceDate: referenceDate).map { row in
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
