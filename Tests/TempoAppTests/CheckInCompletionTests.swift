import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CheckInCompletionTests: XCTestCase {
    @MainActor
    func testSelectingExistingProjectStoresProjectCheckIn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        try appModel.modelContext.save()
        appModel.accountableElapsedInterval = 25 * 60

        try appModel.selectProjectForPrompt(project)

        let checkIns = try appModel.modelContext.fetch(FetchDescriptor<CheckInRecord>())
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns[0].project?.name, "Client Work")
        XCTAssertEqual(checkIns[0].timestamp, now)
        XCTAssertEqual(checkIns[0].kind, "project")
        XCTAssertEqual(checkIns[0].source, "check-in")
        XCTAssertEqual(appModel.schedulerStateRecord.lastCheckInAt, now)
        XCTAssertEqual(appModel.schedulerStateRecord.nextCheckInAt, now.addingTimeInterval(25 * 60))
    }

    @MainActor
    func testCreateAndSelectProjectPersistsProjectAndCheckIn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )

        try appModel.createAndSelectProjectForPrompt(named: "  Deep Work  ")

        let projects = try appModel.modelContext.fetch(
            FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        let checkIns = try appModel.modelContext.fetch(FetchDescriptor<CheckInRecord>())

        XCTAssertEqual(projects.map(\.name), ["Deep Work"])
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns[0].project?.name, "Deep Work")
        XCTAssertEqual(checkIns[0].kind, "project")
    }

    @MainActor
    func testDelayPromptDoesNotCreateCheckIn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        appModel.schedulerStateRecord.nextCheckInAt = now
        appModel.isPromptOverdue = true

        try appModel.delayPrompt(byMinutes: 15)

        let checkIns = try appModel.modelContext.fetch(FetchDescriptor<CheckInRecord>())
        XCTAssertTrue(checkIns.isEmpty)
        XCTAssertEqual(appModel.schedulerStateRecord.delayedUntilAt, now.addingTimeInterval(15 * 60))
    }

    @MainActor
    func testSelectingProjectAfterIdleReturnStoresOnlyTheReturningProjectCheckIn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(15 * 60)),
                kind: "idle",
                source: "inactivity",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        appModel.pendingIdleStartedAt = now.addingTimeInterval(-(15 * 60))
        appModel.pendingIdleEndedAt = now
        appModel.pendingIdleDuration = 15 * 60
        appModel.isIdlePending = true
        try appModel.modelContext.save()

        try appModel.selectProjectForPrompt(project)

        let checkIns = try appModel.modelContext.fetch(
            FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp)])
        )
        XCTAssertEqual(checkIns.count, 2)
        XCTAssertEqual(checkIns[0].kind, "idle")
        XCTAssertEqual(checkIns[1].project?.name, "Client Work")
        XCTAssertEqual(checkIns[1].timestamp, now)
        XCTAssertEqual(checkIns[1].source, "idle-return")
        XCTAssertFalse(appModel.isIdlePending)
    }

    @MainActor
    func testDoneForDayStoresIdleCheckInAndSilencesUntilCutoff() throws {
        let now = date(2026, 3, 16, 21, 15, 0)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now),
            calendar: testCalendar
        )
        appModel.settings.analyticsDayCutoffHour = 6

        try appModel.silenceForRestOfDay()

        let checkIns = try appModel.modelContext.fetch(FetchDescriptor<CheckInRecord>())
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns[0].kind, "idle")
        XCTAssertEqual(checkIns[0].idleKind, TimeAllocationIdleKind.doneForDay.rawValue)
        XCTAssertTrue(appModel.isSilenced)
        XCTAssertEqual(appModel.silenceEndsAt, date(2026, 3, 17, 6, 0, 0))
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

private struct FixedCompletionClock: SchedulerClock {
    let now: Date
}
