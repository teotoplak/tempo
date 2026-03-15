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
        XCTAssertEqual(appModel.settings.delayPresetMinutes, [15, 30])
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
    func testTodaysTrackedDurationOnlyCountsCurrentDay() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPersistenceClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)

        let currentDayEntry = TimeEntryRecord(
            project: project,
            startAt: now.addingTimeInterval(-(90 * 60)),
            endAt: now.addingTimeInterval(-(30 * 60)),
            source: "check-in"
        )
        let previousDayEnd = Calendar.current.date(
            byAdding: .minute,
            value: -5,
            to: Calendar.current.startOfDay(for: now)
        )!
        let previousDayEntry = TimeEntryRecord(
            project: project,
            startAt: previousDayEnd.addingTimeInterval(-(45 * 60)),
            endAt: previousDayEnd,
            source: "check-in"
        )
        appModel.modelContext.insert(currentDayEntry)
        appModel.modelContext.insert(previousDayEntry)
        try appModel.modelContext.save()

        XCTAssertEqual(appModel.todaysTrackedDuration, 60 * 60)
    }

    @MainActor
    func testCurrentProjectContextUsesLatestEntry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPersistenceClock(now: now)
        )
        let olderProject = ProjectRecord(name: "Admin", sortOrder: 0)
        let latestProject = ProjectRecord(name: "Client Work", sortOrder: 1)
        appModel.modelContext.insert(olderProject)
        appModel.modelContext.insert(latestProject)

        appModel.modelContext.insert(
            TimeEntryRecord(
                project: olderProject,
                startAt: now.addingTimeInterval(-(4 * 60 * 60)),
                endAt: now.addingTimeInterval(-(3 * 60 * 60)),
                source: "check-in"
            )
        )
        appModel.modelContext.insert(
            TimeEntryRecord(
                project: latestProject,
                startAt: now.addingTimeInterval(-(90 * 60)),
                endAt: now.addingTimeInterval(-(30 * 60)),
                source: "check-in"
            )
        )
        try appModel.modelContext.save()

        XCTAssertEqual(appModel.currentProjectContextLabel, "Client Work")
    }
}

private struct FixedPersistenceClock: SchedulerClock {
    let now: Date
}
