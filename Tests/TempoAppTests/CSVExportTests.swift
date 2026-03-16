import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CSVExportTests: XCTestCase {
    @MainActor
    func testCSVStringIncludesRequiredColumns() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let service = CSVExportService(modelContext: context, calendar: testCalendar)
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        context.insert(project)
        context.insert(entry(project: project, start: date(2026, 3, 16, 9, 0), end: date(2026, 3, 16, 10, 30)))
        try context.save()

        let csv = service.csvString(range: .day, referenceDate: date(2026, 3, 16, 12, 0))

        XCTAssertTrue(csv.contains("date,start_time,end_time,duration_minutes,project_name"))
        XCTAssertTrue(csv.contains("2026-03-16,09:00,10:30,90,Client Work"))
    }

    @MainActor
    func testCSVStringFormatsRowsInStartTimeOrder() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let service = CSVExportService(modelContext: context, calendar: testCalendar)
        let admin = ProjectRecord(name: "Admin", sortOrder: 0)
        context.insert(admin)
        context.insert(entry(project: admin, start: date(2026, 3, 16, 14, 0), end: date(2026, 3, 16, 14, 30)))
        context.insert(entry(project: admin, start: date(2026, 3, 16, 8, 30), end: date(2026, 3, 16, 9, 0)))
        try context.save()

        let csv = service.csvString(range: .day, referenceDate: date(2026, 3, 16, 16, 0))
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines[1], "2026-03-16,08:30,09:00,30,Admin")
        XCTAssertEqual(lines[2], "2026-03-16,14:00,14:30,30,Admin")
    }

    @MainActor
    func testCSVStringUsesSelectedAnalyticsPeriodBoundaries() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let service = CSVExportService(modelContext: context, calendar: testCalendar)
        let project = ProjectRecord(name: "Deep Work", sortOrder: 0)
        context.insert(project)
        context.insert(entry(project: project, start: date(2026, 3, 16, 9, 0), end: date(2026, 3, 16, 10, 0)))
        context.insert(entry(project: nil, start: date(2026, 3, 17, 11, 0), end: date(2026, 3, 17, 11, 30)))
        context.insert(entry(project: project, start: date(2026, 3, 26, 9, 0), end: date(2026, 3, 26, 10, 0)))
        try context.save()

        let csv = service.csvString(range: .week, referenceDate: date(2026, 3, 18, 12, 0))

        XCTAssertTrue(csv.contains("2026-03-16,09:00,10:00,60,Deep Work"))
        XCTAssertTrue(csv.contains("2026-03-17,11:00,11:30,30,Unassigned"))
        XCTAssertFalse(csv.contains("2026-03-26"))
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
