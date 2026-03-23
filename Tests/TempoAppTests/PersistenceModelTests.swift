import Foundation
import SQLite3
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

    func testPersistentStoreURLUsesTempoApplicationSupportSubdirectory() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/TempoTests/Application Support", isDirectory: true)

        let storeURL = TempoModelContainer.persistentStoreURL(applicationSupportURL: applicationSupportURL)

        XCTAssertEqual(storeURL.path, "/tmp/TempoTests/Application Support/Tempo/tempo.store")
    }

    func testLegacyStoreURLsIncludePreviousDefaultStoreLocations() {
        let applicationSupportURL = URL(fileURLWithPath: "/tmp/TempoTests/Application Support", isDirectory: true)

        let legacyPaths = Set(
            TempoModelContainer.legacyStoreURLs(applicationSupportURL: applicationSupportURL).map(\.path)
        )

        XCTAssertEqual(
            legacyPaths,
            [
                "/tmp/TempoTests/Application Support/default.store",
                "/tmp/TempoTests/Application Support/Tempo/default.store",
                "/tmp/TempoTests/Application Support/TempoApp/default.store",
            ]
        )
    }

    func testCopyLegacyStoreIfNeededCopiesTempoSchemaFromLegacyDefaultStore() throws {
        let applicationSupportURL = try makeTemporaryApplicationSupportDirectory()
        let legacyStoreURL = applicationSupportURL.appending(path: TempoModelContainer.legacyStoreFileName, directoryHint: .notDirectory)
        let destinationStoreURL = TempoModelContainer.persistentStoreURL(applicationSupportURL: applicationSupportURL)

        try createSQLiteStore(at: legacyStoreURL, tableNames: [
            "ZAPPSETTINGSRECORD",
            "ZCHECKINRECORD",
            "ZPROJECTRECORD",
            "ZSCHEDULERSTATERECORD",
        ])

        TempoModelContainer.copyLegacyStoreIfNeeded(
            to: destinationStoreURL,
            applicationSupportURL: applicationSupportURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationStoreURL.path))
        XCTAssertTrue(TempoModelContainer.appearsToBeTempoStore(at: destinationStoreURL))
    }

    func testCopyLegacyStoreIfNeededIgnoresForeignDefaultStoreSchema() throws {
        let applicationSupportURL = try makeTemporaryApplicationSupportDirectory()
        let legacyStoreURL = applicationSupportURL.appending(path: TempoModelContainer.legacyStoreFileName, directoryHint: .notDirectory)
        let destinationStoreURL = TempoModelContainer.persistentStoreURL(applicationSupportURL: applicationSupportURL)

        try createSQLiteStore(at: legacyStoreURL, tableNames: [
            "ZAPIREQUESTMODEL",
            "Z_METADATA",
        ])

        TempoModelContainer.copyLegacyStoreIfNeeded(
            to: destinationStoreURL,
            applicationSupportURL: applicationSupportURL
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationStoreURL.path))
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

    private func makeTemporaryApplicationSupportDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "TempoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let applicationSupportURL = rootURL.appending(path: "Application Support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return applicationSupportURL
    }

    private func createSQLiteStore(at storeURL: URL, tableNames: [String]) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(storeURL.path, &database), SQLITE_OK)
        defer {
            sqlite3_close(database)
        }

        for tableName in tableNames {
            let sql = "CREATE TABLE \(tableName) (Z_PK INTEGER PRIMARY KEY);"
            XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        }
    }
}

private struct FixedPersistenceClock: SchedulerClock {
    let now: Date
}
