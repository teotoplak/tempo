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

    @MainActor
    func testAssignPendingIdleCreatesIdleAssignedEntry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.schedulerStateRecord.pendingIdleStartedAt = now.addingTimeInterval(-(20 * 60))
        appModel.schedulerStateRecord.pendingIdleEndedAt = now.addingTimeInterval(-(5 * 60))
        appModel.schedulerStateRecord.pendingIdleReason = "inactivity"
        appModel.schedulerStateRecord.idleResolvedAt = now
        appModel.pendingIdleStartedAt = now.addingTimeInterval(-(20 * 60))
        appModel.pendingIdleEndedAt = now.addingTimeInterval(-(5 * 60))
        appModel.pendingIdleReason = "inactivity"
        appModel.pendingIdleDuration = 15 * 60
        appModel.isIdlePending = true

        try appModel.assignPendingIdle(to: project)

        let entries = try appModel.modelContext.fetch(FetchDescriptor<TimeEntryRecord>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].source, "idle-assigned")
        XCTAssertEqual(entries[0].startAt, now.addingTimeInterval(-(20 * 60)))
        XCTAssertEqual(entries[0].endAt, now.addingTimeInterval(-(5 * 60)))
        XCTAssertEqual(appModel.schedulerStateRecord.nextCheckInAt, now.addingTimeInterval(25 * 60))
        XCTAssertNil(appModel.schedulerStateRecord.pendingIdleStartedAt)
    }

    @MainActor
    func testDiscardPendingIdleClearsPendingStateWithoutWritingEntry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        appModel.schedulerStateRecord.pendingIdleStartedAt = now.addingTimeInterval(-(15 * 60))
        appModel.schedulerStateRecord.pendingIdleEndedAt = now.addingTimeInterval(-(5 * 60))
        appModel.schedulerStateRecord.pendingIdleReason = "screen-locked"
        appModel.schedulerStateRecord.idleResolvedAt = now
        appModel.pendingIdleStartedAt = now.addingTimeInterval(-(15 * 60))
        appModel.pendingIdleEndedAt = now.addingTimeInterval(-(5 * 60))
        appModel.pendingIdleReason = "screen-locked"
        appModel.pendingIdleDuration = 10 * 60
        appModel.isIdlePending = true

        try appModel.discardPendingIdle()

        let entries = try appModel.modelContext.fetch(FetchDescriptor<TimeEntryRecord>())
        XCTAssertEqual(entries.count, 0)
        XCTAssertNil(appModel.schedulerStateRecord.pendingIdleStartedAt)
        XCTAssertEqual(appModel.schedulerStateRecord.nextCheckInAt, now.addingTimeInterval(25 * 60))
    }

    @MainActor
    func testSplitPendingIdleCreatesContiguousEntries() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let firstProject = ProjectRecord(name: "Client Work", sortOrder: 0)
        let secondProject = ProjectRecord(name: "Admin", sortOrder: 1)
        appModel.modelContext.insert(firstProject)
        appModel.modelContext.insert(secondProject)
        appModel.schedulerStateRecord.pendingIdleStartedAt = now.addingTimeInterval(-(18 * 60))
        appModel.schedulerStateRecord.pendingIdleEndedAt = now.addingTimeInterval(-(3 * 60))
        appModel.schedulerStateRecord.pendingIdleReason = "inactivity"
        appModel.schedulerStateRecord.idleResolvedAt = now
        appModel.pendingIdleStartedAt = now.addingTimeInterval(-(18 * 60))
        appModel.pendingIdleEndedAt = now.addingTimeInterval(-(3 * 60))
        appModel.pendingIdleReason = "inactivity"
        appModel.pendingIdleDuration = 15 * 60
        appModel.isIdlePending = true

        try appModel.splitPendingIdle(
            firstProject: firstProject,
            firstDurationMinutes: 6,
            secondProject: secondProject
        )

        let entries = try appModel.modelContext.fetch(
            FetchDescriptor<TimeEntryRecord>(sortBy: [SortDescriptor(\.startAt)])
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.source), ["idle-split", "idle-split"])
        XCTAssertEqual(entries[0].startAt, now.addingTimeInterval(-(18 * 60)))
        XCTAssertEqual(entries[0].endAt, now.addingTimeInterval(-(12 * 60)))
        XCTAssertEqual(entries[1].startAt, now.addingTimeInterval(-(12 * 60)))
        XCTAssertEqual(entries[1].endAt, now.addingTimeInterval(-(3 * 60)))
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
