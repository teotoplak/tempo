import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class PersistenceModelTests: XCTestCase {
    @MainActor
    func testDefaultSettingsValues() throws {
        let appModel = TempoAppModel(modelContainer: TempoModelContainer.inMemory())

        XCTAssertEqual(appModel.settings.pollingIntervalMinutes, 25)
        XCTAssertEqual(appModel.settings.idleThresholdMinutes, 5)
        XCTAssertEqual(appModel.settings.analyticsDayCutoffHour, 6)
        XCTAssertTrue(appModel.settings.launchAtLoginEnabled)
    }

    @MainActor
    func testProjectRenamePersists() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)

        try appModel.createProject(named: "Client Work")

        let fetch = FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let project = try XCTUnwrap(appModel.modelContext.fetch(fetch).first)

        try appModel.renameProject(project, to: "Deep Work")

        let renamed = try XCTUnwrap(appModel.modelContext.fetch(fetch).first)
        XCTAssertEqual(renamed.name, "Deep Work")
    }

    @MainActor
    func testTodaysTrackedDurationUsesCutoffAwareAllocatedIntervals() throws {
        let now = date(2026, 3, 17, 8, 0, 0)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPersistenceClock(now: now),
            calendar: testCalendar
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.settings.analyticsDayCutoffHour = 6
        appModel.modelContext.insert(project)
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 5, 30, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 7, 0, 0)))
        appModel.modelContext.insert(projectCheckIn(project: project, at: date(2026, 3, 17, 8, 0, 0)))
        try appModel.modelContext.save()

        XCTAssertEqual(appModel.todaysTrackedDuration, 60 * 60)
    }

    @MainActor
    func testCurrentProjectContextUsesLatestProjectCheckIn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPersistenceClock(now: now)
        )
        let olderProject = ProjectRecord(name: "Admin", sortOrder: 0)
        let latestProject = ProjectRecord(name: "Client Work", sortOrder: 1)
        appModel.modelContext.insert(olderProject)
        appModel.modelContext.insert(latestProject)
        appModel.modelContext.insert(projectCheckIn(project: olderProject, at: now.addingTimeInterval(-(4 * 60 * 60))))
        appModel.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(2 * 60 * 60)),
                kind: "idle",
                source: "test",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        appModel.modelContext.insert(projectCheckIn(project: latestProject, at: now.addingTimeInterval(-(30 * 60))))
        try appModel.modelContext.save()

        XCTAssertEqual(appModel.currentProjectContextLabel, "Client Work")
    }

    @MainActor
    func testSaveSettingsReschedulesNextCheckInWhenPollingIntervalChanges() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPersistenceClock(now: now)
        )
        appModel.schedulerStateRecord.nextCheckInAt = now.addingTimeInterval(20 * 60)
        appModel.nextCheckInAt = now.addingTimeInterval(20 * 60)
        appModel.settings.pollingIntervalMinutes = 5

        try appModel.saveSettings()

        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(5 * 60))
        XCTAssertFalse(appModel.isPromptOverdue)
        XCTAssertEqual(appModel.accountableElapsedInterval, 5 * 60)
    }

    @MainActor
    func testMenuBarCountdownMinutesTextUsesMinuteOnlyCountdown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPersistenceClock(now: now)
        )
        appModel.nextCheckInAt = now.addingTimeInterval((21 * 60) + 45)

        XCTAssertEqual(appModel.menuBarCountdownMinutesText(at: now), "21")
    }

    @MainActor
    func testMenuBarCountdownMinutesTextHidesWhileSilenced() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPersistenceClock(now: now)
        )
        appModel.isSilenced = true
        appModel.nextCheckInAt = now.addingTimeInterval(15 * 60)

        XCTAssertNil(appModel.menuBarCountdownMinutesText(at: now))
    }

    private func projectCheckIn(project: ProjectRecord, at date: Date) -> CheckInRecord {
        CheckInRecord(
            timestamp: date,
            kind: "project",
            source: "test",
            project: project
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
        calendar.timeZone = .gmt
        return calendar
    }
}

private struct FixedPersistenceClock: SchedulerClock {
    let now: Date
}
