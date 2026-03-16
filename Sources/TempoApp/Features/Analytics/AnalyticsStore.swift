import Foundation
import SwiftData

@MainActor
final class AnalyticsStore {
    private let modelContext: ModelContext
    private let engine = TimeAllocationEngine()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func period(
        for range: AnalyticsRange,
        referenceDate: Date,
        calendar: Calendar = .current,
        dayCutoffHour: Int = 6
    ) -> AnalyticsPeriod {
        engine.period(
            for: range,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCutoffHour: dayCutoffHour
        )
    }

    func summary(
        range: AnalyticsRange,
        referenceDate: Date,
        calendar: Calendar = .current,
        dayCutoffHour: Int = 6
    ) -> AnalyticsSummarySnapshot {
        let descriptor = FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp)])
        let records = (try? modelContext.fetch(descriptor)) ?? []
        let allocationSummary = engine.summary(
            checkIns: records.compactMap(Self.checkIn(from:)),
            range: range,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCutoffHour: dayCutoffHour
        )

        let projectSummaries = allocationSummary.bucketSummaries.map { summary in
            let projectID: UUID?
            switch summary.bucket {
            case let .project(id, _):
                projectID = id
            case .idle:
                projectID = nil
            }

            return AnalyticsProjectSummary(
                projectID: projectID,
                projectName: summary.bucket.displayName,
                totalDuration: summary.totalDuration,
                percentageOfTotal: allocationSummary.totalDuration > 0 ? summary.totalDuration / allocationSummary.totalDuration : 0,
                entryCount: summary.intervalCount
            )
        }
        let timelineIntervals = allocationSummary.allocatedIntervals.map { interval in
            AnalyticsTimelineInterval(
                startDate: interval.startDate,
                endDate: interval.endDate,
                projectName: interval.bucket.displayName
            )
        }

        return AnalyticsSummarySnapshot(
            period: allocationSummary.period,
            totalDuration: allocationSummary.totalDuration,
            projectSummaries: projectSummaries,
            firstEntryStartDate: range == .day ? allocationSummary.firstAllocatedIntervalStartDate : nil,
            checkIns: allocationSummary.checkIns,
            allocatedIntervals: allocationSummary.allocatedIntervals,
            timelineIntervals: range == .day ? timelineIntervals : []
        )
    }

    private static func checkIn(from record: CheckInRecord) -> TimeAllocationCheckIn? {
        switch record.kind {
        case "project":
            guard let project = record.project else {
                return nil
            }

            return TimeAllocationCheckIn(
                id: record.id,
                timestamp: record.timestamp,
                kind: .project(id: project.id, name: project.name),
                source: record.source
            )
        case "idle":
            guard let idleKindRawValue = record.idleKind, let idleKind = TimeAllocationIdleKind(persistedValue: idleKindRawValue) else {
                return nil
            }

            return TimeAllocationCheckIn(
                id: record.id,
                timestamp: record.timestamp,
                kind: .idle(kind: idleKind),
                source: record.source
            )
        default:
            return nil
        }
    }
}
