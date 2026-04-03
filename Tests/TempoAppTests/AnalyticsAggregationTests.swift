import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class AnalyticsAggregationTests: XCTestCase {
    @MainActor
    func testDailySummaryBuildsProjectAndIdleBreakdownFromCheckIns() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let store = AnalyticsStore(modelContext: context)
        let client = ProjectRecord(name: "Client Work", sortOrder: 0)
        let admin = ProjectRecord(name: "Admin", sortOrder: 1)
        context.insert(client)
        context.insert(admin)
        context.insert(projectCheckIn(project: client, at: date(2026, 3, 16, 9, 0, 0)))
        context.insert(projectCheckIn(project: admin, at: date(2026, 3, 16, 9, 30, 0)))
        context.insert(idleCheckIn(.automaticThreshold, at: date(2026, 3, 16, 10, 0, 0)))
        context.insert(projectCheckIn(project: admin, at: date(2026, 3, 16, 10, 20, 0)))
        try context.save()

        let summary = store.summary(
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.period.startDate, date(2026, 3, 16, 6, 0, 0))
        XCTAssertEqual(summary.period.endDate, date(2026, 3, 17, 6, 0, 0))
        XCTAssertEqual(summary.totalDuration, 80 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries.map(\.projectName), ["Idle", "Admin", "Client Work"])
        XCTAssertEqual(summary.projectSummaries[0].totalDuration, 50 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries[1].totalDuration, 15 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries[2].totalDuration, 15 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.timelineIntervals.count, 4)
        XCTAssertEqual(summary.checkIns.count, 4)
        XCTAssertEqual(summary.allocatedIntervals.count, 4)
    }

    @MainActor
    func testDailySummaryDoesNotCarryIntervalsAcrossCutoff() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let store = AnalyticsStore(modelContext: context)
        let project = ProjectRecord(name: "Deep Work", sortOrder: 0)
        context.insert(project)
        context.insert(idleCheckIn(.doneForDay, at: date(2026, 3, 16, 23, 0, 0)))
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 8, 0, 0)))
        try context.save()

        let previousDay = store.summary(
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )
        let nextDay = store.summary(
            range: .day,
            referenceDate: date(2026, 3, 17, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(previousDay.totalDuration, 0, accuracy: 0.001)
        XCTAssertTrue(previousDay.timelineIntervals.isEmpty)
        XCTAssertEqual(nextDay.totalDuration, 0, accuracy: 0.001)
        XCTAssertTrue(nextDay.timelineIntervals.isEmpty)
    }

    @MainActor
    func testWeeklySummaryAnchorsPeriodToConfiguredCutoff() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let store = AnalyticsStore(modelContext: context)
        let project = ProjectRecord(name: "Deep Work", sortOrder: 0)
        context.insert(project)
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 16, 8, 0, 0)))
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 16, 9, 0, 0)))
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 23, 8, 0, 0)))
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 23, 9, 0, 0)))
        try context.save()

        let summary = store.summary(
            range: .week,
            referenceDate: date(2026, 3, 18, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.period.startDate, date(2026, 3, 16, 6, 0, 0))
        XCTAssertEqual(summary.period.endDate, date(2026, 3, 23, 6, 0, 0))
        XCTAssertEqual(summary.totalDuration, 60 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.projectSummaries.count, 1)
    }

    @MainActor
    func testAnalyticsWeekNavigationMovesAcrossWeeksAndStopsAtCurrentWeek() throws {
        let now = date(2026, 3, 25, 12, 0, 0)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedAnalyticsClock(now: now),
            calendar: testCalendar
        )
        let project = ProjectRecord(name: "Deep Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 9, 0, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 11, 0, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 24, 9, 0, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 24, 10, 0, 0)))
        try appModel.modelContext.save()

        appModel.prepareWeeklyAnalyticsPresentation()

        XCTAssertEqual(appModel.analyticsPeriod.startDate, date(2026, 3, 23, 6, 0, 0))
        XCTAssertFalse(appModel.canShowNextAnalyticsPeriod)

        appModel.showPreviousAnalyticsPeriod()

        XCTAssertEqual(appModel.analyticsPeriod.startDate, date(2026, 3, 16, 6, 0, 0))
        XCTAssertEqual(appModel.analyticsTotalDuration, 2 * 60 * 60, accuracy: 0.001)
        XCTAssertTrue(appModel.canShowNextAnalyticsPeriod)

        appModel.showNextAnalyticsPeriod()

        XCTAssertEqual(appModel.analyticsPeriod.startDate, date(2026, 3, 23, 6, 0, 0))
        XCTAssertEqual(appModel.analyticsTotalDuration, 60 * 60, accuracy: 0.001)
        XCTAssertFalse(appModel.canShowNextAnalyticsPeriod)
    }

    @MainActor
    func testAppModelUsesConfiguredCutoffForTodaySummary() throws {
        let now = date(2026, 3, 17, 7, 0, 0)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedAnalyticsClock(now: now),
            calendar: testCalendar
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.settings.analyticsDayCutoffHour = 6
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 5, 30, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 7, 0, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 7, 30, 0)))
        try appModel.modelContext.save()

        appModel.selectAnalyticsRange(.day)

        XCTAssertEqual(appModel.analyticsPeriod.startDate, date(2026, 3, 17, 6, 0, 0))
        XCTAssertEqual(appModel.analyticsPeriod.endDate, date(2026, 3, 18, 6, 0, 0))
        XCTAssertEqual(appModel.analyticsTotalDuration, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(appModel.analyticsProjectSummaries.count, 1)
        XCTAssertEqual(appModel.analyticsFirstEntryStartDate, date(2026, 3, 17, 7, 0, 0))
    }

    @MainActor
    func testMenuBarDayNavigationShowsPreviousDaySummary() throws {
        let now = date(2026, 3, 18, 8, 0, 0)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedAnalyticsClock(now: now),
            calendar: testCalendar
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 9, 0, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 9, 15, 0)))
        appModel.modelContext.insert(idleCheckIn(.automaticThreshold, at: date(2026, 3, 17, 9, 30, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 10, 30, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 18, 7, 30, 0)))
        try appModel.modelContext.save()

        appModel.refreshAnalytics(referenceDate: now)
        appModel.showPreviousMenuBarDay()

        XCTAssertEqual(appModel.menuBarDayPeriod.startDate, date(2026, 3, 17, 6, 0, 0))
        XCTAssertEqual(appModel.menuBarDayPeriod.endDate, date(2026, 3, 18, 6, 0, 0))
        XCTAssertEqual(appModel.menuBarDayProjectSummaries.count, 1)
        XCTAssertEqual(appModel.menuBarDayProjectSummaries[0].projectName, "Client Work")
        XCTAssertEqual(appModel.menuBarDayProjectSummaries[0].totalDuration, 15 * 60, accuracy: 0.001)
        XCTAssertEqual(appModel.menuBarDayProjectSummaries[0].percentageOfTotal, 1, accuracy: 0.001)
        XCTAssertEqual(appModel.menuBarDayWorkedDuration, 15 * 60, accuracy: 0.001)
        XCTAssertEqual(appModel.menuBarDayCheckIns.count, 4)
        XCTAssertTrue(appModel.canShowNextMenuBarDay)
    }

    @MainActor
    func testMenuBarDayNavigationStopsAtCurrentDay() throws {
        let now = date(2026, 3, 18, 8, 0, 0)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedAnalyticsClock(now: now),
            calendar: testCalendar
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 9, 0, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 10, 30, 0)))
        try appModel.modelContext.save()

        appModel.refreshAnalytics(referenceDate: now)
        appModel.showPreviousMenuBarDay()
        appModel.showNextMenuBarDay()

        XCTAssertEqual(appModel.menuBarDayPeriod.startDate, date(2026, 3, 18, 6, 0, 0))
        XCTAssertEqual(appModel.menuBarDayPeriod.endDate, date(2026, 3, 19, 6, 0, 0))
        XCTAssertFalse(appModel.canShowNextMenuBarDay)

        let currentPeriod = appModel.menuBarDayPeriod
        appModel.showNextMenuBarDay()

        XCTAssertEqual(appModel.menuBarDayPeriod, currentPeriod)
    }

    private func projectCheckIn(project: ProjectRecord, at date: Date) -> CheckInRecord {
        CheckInRecord(
            timestamp: date,
            kind: "project",
            source: "test",
            project: project
        )
    }

    private func idleCheckIn(_ idleKind: TimeAllocationIdleKind, at date: Date) -> CheckInRecord {
        CheckInRecord(
            timestamp: date,
            kind: "idle",
            source: "test",
            idleKind: idleKind.rawValue
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var components = DateComponents()
        components.calendar = testCalendar
        components.timeZone = testCalendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
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
