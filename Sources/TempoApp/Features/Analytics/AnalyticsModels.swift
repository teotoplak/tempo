import Foundation

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:
            return "Daily"
        case .week:
            return "Weekly"
        case .month:
            return "Monthly"
        case .year:
            return "Yearly"
        }
    }
}

struct AnalyticsPeriod: Equatable {
    let startDate: Date
    let endDate: Date
    let label: String
}

struct AnalyticsProjectSummary: Equatable, Identifiable {
    let projectID: UUID?
    let projectName: String
    let totalDuration: TimeInterval
    let percentageOfTotal: Double
    let entryCount: Int

    var id: String {
        projectID?.uuidString ?? "unassigned"
    }
}

struct AnalyticsTimelineInterval: Equatable, Identifiable {
    let startDate: Date
    let endDate: Date
    let projectName: String

    var id: String {
        "\(projectName)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)"
    }
}

struct AnalyticsSummarySnapshot: Equatable {
    let period: AnalyticsPeriod
    let totalDuration: TimeInterval
    let projectSummaries: [AnalyticsProjectSummary]
    let topProjectName: String?
    let firstEntryStartDate: Date?
    let timelineIntervals: [AnalyticsTimelineInterval]
}
