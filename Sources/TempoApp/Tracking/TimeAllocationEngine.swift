import Foundation

enum TimeAllocationIdleKind: String, CaseIterable, Codable {
    case automaticThreshold = "automatic-threshold"
    case doneForDay = "done-for-day"
    case snoozed = "snoozed"
}

enum TimeAllocationBucket: Hashable, Equatable, Identifiable {
    case project(id: UUID, name: String)
    case idle

    var id: String {
        switch self {
        case let .project(id, _):
            return id.uuidString
        case .idle:
            return "idle"
        }
    }

    var displayName: String {
        switch self {
        case let .project(_, name):
            return name
        case .idle:
            return "Idle"
        }
    }
}

enum TimeAllocationCheckInKind: Equatable {
    case project(id: UUID, name: String)
    case idle(kind: TimeAllocationIdleKind)

    var bucket: TimeAllocationBucket {
        switch self {
        case let .project(id, name):
            return .project(id: id, name: name)
        case .idle:
            return .idle
        }
    }
}

enum TimeAllocationRule: String, Equatable {
    case sameBucket = "same-bucket"
    case splitBetweenProjects = "split-between-projects"
    case idleDominates = "idle-dominates"
}

struct TimeAllocationCheckIn: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: TimeAllocationCheckInKind
    let source: String
}

struct TimeAllocationInterval: Equatable, Identifiable {
    let startDate: Date
    let endDate: Date
    let bucket: TimeAllocationBucket
    let rule: TimeAllocationRule
    let leadingCheckInID: UUID
    let trailingCheckInID: UUID

    var id: String {
        "\(bucket.id)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)"
    }

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

struct TimeAllocationBucketSummary: Equatable, Identifiable {
    let bucket: TimeAllocationBucket
    let totalDuration: TimeInterval
    let intervalCount: Int

    var id: String { bucket.id }
}

struct TimeAllocationSummary: Equatable {
    let period: AnalyticsPeriod
    let checkIns: [TimeAllocationCheckIn]
    let allocatedIntervals: [TimeAllocationInterval]
    let bucketSummaries: [TimeAllocationBucketSummary]
    let totalDuration: TimeInterval
    let firstAllocatedIntervalStartDate: Date?
}

struct TimeAllocationEngine {
    func period(
        for range: AnalyticsRange,
        referenceDate: Date,
        calendar: Calendar = .current,
        dayCutoffHour: Int
    ) -> AnalyticsPeriod {
        let shiftedReferenceDate = shifted(referenceDate, byHours: -dayCutoffHour, calendar: calendar)
        let startDate: Date
        let endDate: Date

        switch range {
        case .day:
            startDate = calendar.startOfDay(for: shiftedReferenceDate)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: shiftedReferenceDate)
            startDate = interval?.start ?? calendar.startOfDay(for: shiftedReferenceDate)
            endDate = interval?.end ?? (calendar.date(byAdding: .day, value: 7, to: startDate) ?? startDate)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: shiftedReferenceDate)
            startDate = interval?.start ?? calendar.startOfDay(for: shiftedReferenceDate)
            endDate = interval?.end ?? (calendar.date(byAdding: .month, value: 1, to: startDate) ?? startDate)
        case .year:
            let interval = calendar.dateInterval(of: .year, for: shiftedReferenceDate)
            startDate = interval?.start ?? calendar.startOfDay(for: shiftedReferenceDate)
            endDate = interval?.end ?? (calendar.date(byAdding: .year, value: 1, to: startDate) ?? startDate)
        }

        let adjustedStartDate = shifted(startDate, byHours: dayCutoffHour, calendar: calendar)
        let adjustedEndDate = shifted(endDate, byHours: dayCutoffHour, calendar: calendar)

        return AnalyticsPeriod(
            startDate: adjustedStartDate,
            endDate: adjustedEndDate,
            label: Self.periodLabel(
                for: range,
                startDate: adjustedStartDate,
                endDate: adjustedEndDate,
                calendar: calendar,
                dayCutoffHour: dayCutoffHour
            )
        )
    }

    func summary(
        checkIns: [TimeAllocationCheckIn],
        range: AnalyticsRange,
        referenceDate: Date,
        calendar: Calendar = .current,
        dayCutoffHour: Int
    ) -> TimeAllocationSummary {
        let period = period(
            for: range,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCutoffHour: dayCutoffHour
        )
        let sortedCheckIns = checkIns
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timestamp != rhs.element.timestamp {
                    return lhs.element.timestamp < rhs.element.timestamp
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
        let periodCheckIns = sortedCheckIns.filter { checkIn in
            checkIn.timestamp >= period.startDate && checkIn.timestamp < period.endDate
        }

        var allocatedIntervals: [TimeAllocationInterval] = []
        for window in dailyWindows(in: period, calendar: calendar) {
            let windowCheckIns = periodCheckIns.filter { checkIn in
                checkIn.timestamp >= window.start && checkIn.timestamp < window.end
            }
            allocatedIntervals.append(contentsOf: allocateIntervals(in: windowCheckIns))
        }

        var grouped: [TimeAllocationBucket: (duration: TimeInterval, count: Int)] = [:]
        for interval in allocatedIntervals {
            let current = grouped[interval.bucket] ?? (duration: 0, count: 0)
            grouped[interval.bucket] = (
                duration: current.duration + interval.duration,
                count: current.count + 1
            )
        }

        let totalDuration = allocatedIntervals.reduce(into: 0.0) { total, interval in
            total += interval.duration
        }

        let bucketSummaries = grouped.map { bucket, groupedValue in
            TimeAllocationBucketSummary(
                bucket: bucket,
                totalDuration: groupedValue.duration,
                intervalCount: groupedValue.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalDuration != rhs.totalDuration {
                return lhs.totalDuration > rhs.totalDuration
            }

            return lhs.bucket.displayName.localizedCaseInsensitiveCompare(rhs.bucket.displayName) == .orderedAscending
        }

        return TimeAllocationSummary(
            period: period,
            checkIns: periodCheckIns,
            allocatedIntervals: allocatedIntervals,
            bucketSummaries: bucketSummaries,
            totalDuration: totalDuration,
            firstAllocatedIntervalStartDate: allocatedIntervals.first?.startDate
        )
    }

    private func dailyWindows(in period: AnalyticsPeriod, calendar: Calendar) -> [DateInterval] {
        var windows: [DateInterval] = []
        var startDate = period.startDate

        while startDate < period.endDate {
            let nextDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? period.endDate
            windows.append(DateInterval(start: startDate, end: min(nextDate, period.endDate)))
            startDate = nextDate
        }

        return windows
    }

    private func allocateIntervals(in checkIns: [TimeAllocationCheckIn]) -> [TimeAllocationInterval] {
        guard checkIns.count > 1 else {
            return []
        }

        var intervals: [TimeAllocationInterval] = []

        for index in checkIns.indices.dropLast() {
            let leadingCheckIn = checkIns[index]
            let trailingCheckIn = checkIns[index + 1]
            let totalSeconds = max(
                Int(trailingCheckIn.timestamp.timeIntervalSince(leadingCheckIn.timestamp).rounded(.towardZero)),
                0
            )

            guard totalSeconds > 0 else {
                continue
            }

            switch (leadingCheckIn.kind, trailingCheckIn.kind) {
            case let (.project(id: leadingID, name: leadingName), .project(id: trailingID, name: _))
                where leadingID == trailingID:
                intervals.append(
                    TimeAllocationInterval(
                        startDate: leadingCheckIn.timestamp,
                        endDate: trailingCheckIn.timestamp,
                        bucket: .project(id: leadingID, name: leadingName),
                        rule: .sameBucket,
                        leadingCheckInID: leadingCheckIn.id,
                        trailingCheckInID: trailingCheckIn.id
                    )
                )
            case let (.project(id: leadingID, name: leadingName), .project(id: trailingID, name: trailingName)):
                let leadingSeconds = totalSeconds / 2
                let trailingSeconds = totalSeconds - leadingSeconds
                let splitDate = leadingCheckIn.timestamp.addingTimeInterval(TimeInterval(leadingSeconds))

                if leadingSeconds > 0 {
                    intervals.append(
                        TimeAllocationInterval(
                            startDate: leadingCheckIn.timestamp,
                            endDate: splitDate,
                            bucket: .project(id: leadingID, name: leadingName),
                            rule: .splitBetweenProjects,
                            leadingCheckInID: leadingCheckIn.id,
                            trailingCheckInID: trailingCheckIn.id
                        )
                    )
                }

                if trailingSeconds > 0 {
                    intervals.append(
                        TimeAllocationInterval(
                            startDate: splitDate,
                            endDate: trailingCheckIn.timestamp,
                            bucket: .project(id: trailingID, name: trailingName),
                            rule: .splitBetweenProjects,
                            leadingCheckInID: leadingCheckIn.id,
                            trailingCheckInID: trailingCheckIn.id
                        )
                    )
                }
            default:
                intervals.append(
                    TimeAllocationInterval(
                        startDate: leadingCheckIn.timestamp,
                        endDate: trailingCheckIn.timestamp,
                        bucket: .idle,
                        rule: .idleDominates,
                        leadingCheckInID: leadingCheckIn.id,
                        trailingCheckInID: trailingCheckIn.id
                    )
                )
            }
        }

        return intervals
    }

    private func shifted(_ date: Date, byHours hours: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: date) ?? date
    }

    private static func periodLabel(
        for range: AnalyticsRange,
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        dayCutoffHour: Int
    ) -> String {
        let inclusiveEndDate = calendar.date(byAdding: .second, value: -1, to: endDate) ?? endDate
        let displayStartDate = calendar.date(byAdding: .hour, value: -dayCutoffHour, to: startDate) ?? startDate
        let displayEndDate = calendar.date(byAdding: .hour, value: -dayCutoffHour, to: inclusiveEndDate) ?? inclusiveEndDate

        switch range {
        case .day:
            return displayStartDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            return "\(displayStartDate.formatted(date: .abbreviated, time: .omitted)) – \(displayEndDate.formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return displayStartDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return displayStartDate.formatted(.dateTime.year())
        }
    }
}
