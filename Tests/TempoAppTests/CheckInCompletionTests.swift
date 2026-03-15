import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CheckInCompletionTests: XCTestCase {
    @MainActor
    func testSelectingExistingProjectCreatesTimeEntry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        try appModel.modelContext.save()
        appModel.accountableElapsedInterval = 25 * 60
        appModel.promptSearchText = "Client"

        try appModel.selectProjectForPrompt(project)

        let entries = try appModel.modelContext.fetch(FetchDescriptor<TimeEntryRecord>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].project?.name, "Client Work")
        XCTAssertEqual(entries[0].startAt, now.addingTimeInterval(-(25 * 60)))
        XCTAssertEqual(entries[0].endAt, now)
        XCTAssertEqual(entries[0].source, "check-in")
        XCTAssertEqual(appModel.schedulerStateRecord.lastCheckInAt, now)
        XCTAssertEqual(appModel.schedulerStateRecord.nextCheckInAt, now.addingTimeInterval(25 * 60))
        XCTAssertEqual(appModel.promptSearchText, "")
        XCTAssertFalse(appModel.checkInPromptState.isPresented)
    }

    @MainActor
    func testCreateAndSelectProjectPersistsProjectAndEntry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        appModel.accountableElapsedInterval = 15 * 60

        try appModel.createAndSelectProjectForPrompt(named: "  Deep Work  ")

        let projects = try appModel.modelContext.fetch(
            FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        let entries = try appModel.modelContext.fetch(FetchDescriptor<TimeEntryRecord>())

        XCTAssertEqual(projects.map(\.name), ["Deep Work"])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].project?.name, "Deep Work")
        XCTAssertEqual(entries[0].source, "check-in")
        XCTAssertEqual(entries[0].startAt, now.addingTimeInterval(-(15 * 60)))
        XCTAssertEqual(entries[0].endAt, now)
    }

    @MainActor
    func testDelayPromptDoesNotCreateTimeEntry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        try appModel.modelContext.save()
        appModel.accountableElapsedInterval = 25 * 60
        appModel.promptSearchText = "client"
        appModel.schedulerStateRecord.nextCheckInAt = now

        try appModel.delayPrompt(byMinutes: 15)

        let entries = try appModel.modelContext.fetch(FetchDescriptor<TimeEntryRecord>())
        XCTAssertEqual(entries.count, 0)
        XCTAssertEqual(appModel.promptSearchText, "")
        XCTAssertEqual(appModel.schedulerStateRecord.nextCheckInAt, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(appModel.schedulerStateRecord.delayedUntilAt, now.addingTimeInterval(15 * 60))
        XCTAssertFalse(appModel.checkInPromptState.isPresented)
    }

    func testCompletionFlowRemainsSilent() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appModelSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/App/TempoAppModel.swift"),
            encoding: .utf8
        )
        let promptSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/Features/CheckIn/CheckInPromptContent.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(appModelSource.contains("NSSound"))
        XCTAssertFalse(appModelSource.contains("NSBeep"))
        XCTAssertFalse(promptSource.contains("NSSound"))
        XCTAssertFalse(promptSource.contains("NSBeep"))
    }
}

private struct FixedCompletionClock: SchedulerClock {
    let now: Date
}
