import Foundation
import SwiftData

@MainActor
final class AnalyticsStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func period(
        for range: AnalyticsRange,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> AnalyticsPeriod {
        let startDate: Date
        let endDate: Date

        switch range {
        case .day:
            startDate = calendar.startOfDay(for: referenceDate)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            startDate = interval?.start ?? calendar.startOfDay(for: referenceDate)
            endDate = interval?.end ?? (calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: referenceDate)
            startDate = interval?.start ?? calendar.startOfDay(for: referenceDate)
            endDate = interval?.end ?? (calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate)
        case .year:
            let interval = calendar.dateInterval(of: .year, for: referenceDate)
            startDate = interval?.start ?? calendar.startOfDay(for: referenceDate)
            endDate = interval?.end ?? (calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate)
        }

        return AnalyticsPeriod(
            startDate: startDate,
            endDate: endDate,
            label: Self.periodLabel(for: range, startDate: startDate, endDate: endDate, calendar: calendar)
        )
    }

    func summary(
        range: AnalyticsRange,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> AnalyticsSummarySnapshot {
        let period = period(for: range, referenceDate: referenceDate, calendar: calendar)
        let descriptor = FetchDescriptor<TimeEntryRecord>(sortBy: [SortDescriptor(\.startAt)])
        let entries = ((try? modelContext.fetch(descriptor)) ?? []).filter { entry in
            entry.endAt >= period.startDate && entry.endAt < period.endDate
        }

        let totalDuration = entries.reduce(into: 0.0) { total, entry in
            total += entry.endAt.timeIntervalSince(entry.startAt)
        }

        var grouped: [UUID?: (name: String, duration: TimeInterval, count: Int)] = [:]
        for entry in entries {
            let projectID = entry.project?.id
            let projectName = entry.project?.name ?? "Unassigned"
            let duration = entry.endAt.timeIntervalSince(entry.startAt)
            let current = grouped[projectID] ?? (name: projectName, duration: 0, count: 0)
            grouped[projectID] = (
                name: projectName,
                duration: current.duration + duration,
                count: current.count + 1
            )
        }

        let projectSummaries = grouped.map { projectID, group in
            AnalyticsProjectSummary(
                projectID: projectID,
                projectName: group.name,
                totalDuration: group.duration,
                percentageOfTotal: totalDuration > 0 ? group.duration / totalDuration : 0,
                entryCount: group.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalDuration != rhs.totalDuration {
                return lhs.totalDuration > rhs.totalDuration
            }

            return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
        }

        return AnalyticsSummarySnapshot(
            period: period,
            totalDuration: totalDuration,
            projectSummaries: projectSummaries,
            topProjectName: projectSummaries.first?.projectName
        )
    }

    private static func periodLabel(
        for range: AnalyticsRange,
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> String {
        let inclusiveEndDate = calendar.date(byAdding: .second, value: -1, to: endDate) ?? endDate
        switch range {
        case .day:
            return startDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(inclusiveEndDate.formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return startDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return startDate.formatted(.dateTime.year())
        }
    }
}
