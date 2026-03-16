import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class AnalyticsAggregationTests: XCTestCase {
    @MainActor
    func testDailySummaryGroupsDurationsByProject() throws {
        let now = date(2026, 3, 16, 14, 0)
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let store = AnalyticsStore(modelContext: context)
        let client = ProjectRecord(name: "Client Work", sortOrder: 0)
        let admin = ProjectRecord(name: "Admin", sortOrder: 1)
        context.insert(client)
        context.insert(admin)

        context.insert(entry(project: client, start: date(2026, 3, 16, 9, 0), end: date(2026, 3, 16, 10, 0)))
        context.insert(entry(project: client, start: date(2026, 3, 16, 11, 0), end: date(2026, 3, 16, 11, 30)))
        context.insert(entry(project: admin, start: date(2026, 3, 16, 12, 0), end: date(2026, 3, 16, 12, 45)))
        context.insert(entry(project: admin, start: date(2026, 3, 15, 12, 0), end: date(2026, 3, 15, 12, 30)))
        try context.save()

        let summary = store.summary(range: .day, referenceDate: now, calendar: testCalendar)

        XCTAssertEqual(summary.period.startDate, date(2026, 3, 16, 0, 0))
        XCTAssertEqual(summary.period.endDate, date(2026, 3, 17, 0, 0))
        XCTAssertEqual(summary.totalDuration, 8_100, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries.map(\.projectName), ["Client Work", "Admin"])
        XCTAssertEqual(summary.projectSummaries[0].totalDuration, 5_400, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries[0].entryCount, 2)
        XCTAssertEqual(summary.projectSummaries[1].totalDuration, 2_700, accuracy: 0.001)
        XCTAssertEqual(summary.topProjectName, "Client Work")
    }

    @MainActor
    func testWeeklySummaryFiltersEntriesOutsidePeriod() throws {
        let referenceDate = date(2026, 3, 18, 8, 0)
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let store = AnalyticsStore(modelContext: context)
        let project = ProjectRecord(name: "Deep Work", sortOrder: 0)
        context.insert(project)

        context.insert(entry(project: project, start: date(2026, 3, 16, 9, 0), end: date(2026, 3, 16, 10, 0)))
        context.insert(entry(project: project, start: date(2026, 3, 18, 13, 0), end: date(2026, 3, 18, 14, 30)))
        context.insert(entry(project: project, start: date(2026, 3, 22, 15, 0), end: date(2026, 3, 22, 15, 45)))
        context.insert(entry(project: project, start: date(2026, 3, 23, 9, 0), end: date(2026, 3, 23, 9, 30)))
        try context.save()

        let summary = store.summary(range: .week, referenceDate: referenceDate, calendar: testCalendar)

        XCTAssertEqual(summary.period.startDate, date(2026, 3, 16, 0, 0))
        XCTAssertEqual(summary.period.endDate, date(2026, 3, 23, 0, 0))
        XCTAssertEqual(summary.totalDuration, 11_700, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries.count, 1)
        XCTAssertEqual(summary.projectSummaries[0].entryCount, 3)
    }

    @MainActor
    func testMonthlySummaryComputesPercentagesFromProjectTotals() throws {
        let referenceDate = date(2026, 3, 20, 8, 0)
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let store = AnalyticsStore(modelContext: context)
        let client = ProjectRecord(name: "Client Work", sortOrder: 0)
        let admin = ProjectRecord(name: "Admin", sortOrder: 1)
        let research = ProjectRecord(name: "Research", sortOrder: 2)
        context.insert(client)
        context.insert(admin)
        context.insert(research)

        context.insert(entry(project: client, start: date(2026, 3, 5, 9, 0), end: date(2026, 3, 5, 10, 0)))
        context.insert(entry(project: admin, start: date(2026, 3, 7, 10, 0), end: date(2026, 3, 7, 11, 0)))
        context.insert(entry(project: research, start: date(2026, 3, 9, 12, 0), end: date(2026, 3, 9, 13, 0)))
        context.insert(entry(project: client, start: date(2026, 3, 12, 9, 0), end: date(2026, 3, 12, 10, 0)))
        context.insert(entry(project: client, start: date(2026, 2, 27, 9, 0), end: date(2026, 2, 27, 10, 0)))
        try context.save()

        let summary = store.summary(range: .month, referenceDate: referenceDate, calendar: testCalendar)

        XCTAssertEqual(summary.period.startDate, date(2026, 3, 1, 0, 0))
        XCTAssertEqual(summary.period.endDate, date(2026, 4, 1, 0, 0))
        XCTAssertEqual(summary.totalDuration, 14_400, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries.count, 3)
        XCTAssertEqual(summary.projectSummaries[0].projectName, "Client Work")
        XCTAssertEqual(summary.projectSummaries[0].percentageOfTotal, 0.5, accuracy: 0.0001)
        XCTAssertEqual(summary.projectSummaries[1].percentageOfTotal, 0.25, accuracy: 0.0001)
        XCTAssertEqual(summary.projectSummaries[2].percentageOfTotal, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func testSelectingAnalyticsRangeRefreshesAppModelSnapshot() throws {
        let now = date(2026, 3, 16, 14, 0)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedAnalyticsClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.modelContext.insert(entry(project: project, start: date(2026, 3, 16, 9, 0), end: date(2026, 3, 16, 10, 0)))
        appModel.modelContext.insert(entry(project: project, start: date(2026, 3, 10, 9, 0), end: date(2026, 3, 10, 11, 0)))
        try appModel.modelContext.save()

        appModel.selectAnalyticsRange(.week)

        let expectedInterval = Calendar.current.dateInterval(of: .weekOfYear, for: now)

        XCTAssertEqual(appModel.selectedAnalyticsRange, .week)
        XCTAssertEqual(appModel.analyticsPeriod.startDate, expectedInterval?.start)
        XCTAssertEqual(appModel.analyticsPeriod.endDate, expectedInterval?.end)
        XCTAssertEqual(appModel.analyticsTotalDuration, 3_600, accuracy: 0.001)
        XCTAssertEqual(appModel.analyticsProjectSummaries.count, 1)
        XCTAssertEqual(appModel.analyticsTopProjectName, "Client Work")
    }

    private func entry(project: ProjectRecord?, start: Date, end: Date) -> TimeEntryRecord {
        TimeEntryRecord(project: project, startAt: start, endAt: end, source: "check-in")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = testCalendar
        components.timeZone = testCalendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}

private struct FixedAnalyticsClock: SchedulerClock {
    let now: Date
}
