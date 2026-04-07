import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CSVExportTests: XCTestCase {
    @MainActor
    func testCSVStringExportsDerivedIntervals() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let service = CSVExportService(modelContext: context, calendar: testCalendar)
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        context.insert(project)
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 16, 9, 0, 0)))
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 16, 10, 30, 0)))
        try context.save()

        let csv = service.csvString(range: .day, referenceDate: date(2026, 3, 16, 12, 0, 0))

        XCTAssertTrue(csv.contains("date,start_time,end_time,duration_minutes,project_name"))
        XCTAssertTrue(csv.contains("2026-03-16,09:00,10:30,90,Client Work"))
    }

    @MainActor
    func testCSVStringFormatsRowsInAllocatedIntervalOrder() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let service = CSVExportService(modelContext: context, calendar: testCalendar)
        let alpha = ProjectRecord(name: "Alpha", sortOrder: 0)
        let beta = ProjectRecord(name: "Beta", sortOrder: 1)
        context.insert(alpha)
        context.insert(beta)
        context.insert(projectCheckIn(project: alpha, at: date(2026, 3, 16, 8, 30, 0)))
        context.insert(projectCheckIn(project: beta, at: date(2026, 3, 16, 9, 0, 0)))
        context.insert(idleCheckIn(.automaticThreshold, at: date(2026, 3, 16, 9, 30, 0)))
        try context.save()

        let csv = service.csvString(range: .day, referenceDate: date(2026, 3, 16, 16, 0, 0))
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines[1], "2026-03-16,08:30,08:45,15,Alpha")
        XCTAssertEqual(lines[2], "2026-03-16,08:45,09:00,15,Beta")
        XCTAssertEqual(lines[3], "2026-03-16,09:00,09:30,30,Beta")
    }

    @MainActor
    func testCSVStringUsesConfiguredCutoffForDailyPeriod() throws {
        let container = TempoModelContainer.inMemory()
        let context = ModelContext(container)
        let service = CSVExportService(modelContext: context, calendar: testCalendar)
        let project = ProjectRecord(name: "Deep Work", sortOrder: 0)
        context.insert(project)
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 5, 30, 0)))
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 7, 0, 0)))
        context.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 7, 30, 0)))
        try context.save()

        let csv = service.csvString(
            range: .day,
            referenceDate: date(2026, 3, 17, 12, 0, 0),
            dayCutoffHour: 6
        )

        XCTAssertTrue(csv.contains("2026-03-17,07:00,07:30,30,Deep Work"))
        XCTAssertFalse(csv.contains("05:30"))
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
