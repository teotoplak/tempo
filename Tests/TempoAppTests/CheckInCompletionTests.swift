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
        appModel.isPromptOverdue = true
        appModel.refreshCheckInPromptState()

        try appModel.selectProjectForPrompt(project)

        let checkIns = try appModel.modelContext.fetch(FetchDescriptor<CheckInRecord>())
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns[0].project?.name, "Client Work")
        XCTAssertEqual(checkIns[0].timestamp, now)
        XCTAssertEqual(checkIns[0].kind, "project")
        XCTAssertEqual(checkIns[0].source, "check-in")
        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(25 * 60))
        XCTAssertFalse(appModel.isIdlePending)
    }

    @MainActor
    func testSubmitPromptSearchWithEmptyQueryUsesSelectedProject() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let alpha = ProjectRecord(name: "Alpha", sortOrder: 0)
        let beta = ProjectRecord(name: "Beta", sortOrder: 1)
        appModel.modelContext.insert(alpha)
        appModel.modelContext.insert(beta)
        appModel.modelContext.insert(projectCheckIn(project: beta, at: now.addingTimeInterval(-300)))
        try appModel.modelContext.save()
        appModel.accountableElapsedInterval = 25 * 60
        appModel.isPromptOverdue = true
        appModel.updatePromptSearchText("")
        appModel.refreshCheckInPromptState()

        try appModel.submitPromptSearch()

        let checkIns = try appModel.modelContext.fetch(
            FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp)])
        )
        XCTAssertEqual(checkIns.count, 2)
        XCTAssertEqual(checkIns[1].project?.name, "Beta")
        XCTAssertEqual(checkIns[1].timestamp, now)
        XCTAssertEqual(checkIns[1].source, "check-in")
    }

    @MainActor
    func testCreateAndSelectProjectPersistsProjectAndCheckIn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        appModel.isPromptOverdue = true
        appModel.refreshCheckInPromptState()

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
    func testSubmitPromptSearchUsesHighlightedExistingProjectBeforeCreateAction() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let linkedin = ProjectRecord(name: "linkedin", sortOrder: 0)
        appModel.modelContext.insert(linkedin)
        try appModel.modelContext.save()
        appModel.accountableElapsedInterval = 25 * 60
        appModel.isPromptOverdue = true
        appModel.refreshCheckInPromptState()

        appModel.updatePromptSearchText("link")
        try appModel.submitPromptSearch()

        let projects = try appModel.modelContext.fetch(
            FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        let checkIns = try appModel.modelContext.fetch(FetchDescriptor<CheckInRecord>())

        XCTAssertEqual(projects.map(\.name), ["linkedin"])
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns[0].project?.name, "linkedin")
    }

    @MainActor
    func testSubmitPromptSearchCreatesProjectWhenCreateActionIsHighlighted() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let linkedin = ProjectRecord(name: "linkedin", sortOrder: 0)
        appModel.modelContext.insert(linkedin)
        try appModel.modelContext.save()
        appModel.accountableElapsedInterval = 25 * 60
        appModel.isPromptOverdue = true
        appModel.refreshCheckInPromptState()

        appModel.updatePromptSearchText("link")
        appModel.movePromptSelection(by: 1)
        try appModel.submitPromptSearch()

        let projects = try appModel.modelContext.fetch(
            FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        let checkIns = try appModel.modelContext.fetch(FetchDescriptor<CheckInRecord>())

        XCTAssertEqual(projects.map(\.name), ["linkedin", "link"])
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns[0].project?.name, "link")
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
        appModel.refreshCheckInPromptState()
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
        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(25 * 60))
    }

    @MainActor
    func testSelectingProjectTwiceAfterIdleReturnIgnoresSecondPromptSubmission() throws {
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
                source: "screen-locked",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try appModel.modelContext.save()
        appModel.recoverSchedulerState(eventDate: now, activityDate: now)

        try appModel.selectProjectForPrompt(project)
        try appModel.selectProjectForPrompt(project)

        let checkIns = try appModel.modelContext.fetch(
            FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp)])
        )
        XCTAssertEqual(checkIns.count, 2)
        XCTAssertEqual(checkIns[0].kind, "idle")
        XCTAssertEqual(checkIns[1].kind, "project")
        XCTAssertEqual(checkIns[1].source, "idle-return")
        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(25 * 60))
    }

    @MainActor
    func testSelectingProjectAfterUnansweredPromptIdleStoresFreshCheckIn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let idleStart = now.addingTimeInterval(-(15 * 60))
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCompletionClock(now: now)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        appModel.modelContext.insert(project)
        appModel.modelContext.insert(
            CheckInRecord(
                timestamp: idleStart,
                kind: "idle",
                source: "unanswered-prompt",
                idleKind: TimeAllocationIdleKind.unansweredPrompt.rawValue
            )
        )
        try appModel.modelContext.save()
        appModel.recoverSchedulerState(
            eventDate: now,
            activityDate: idleStart.addingTimeInterval(-60)
        )

        try appModel.selectProjectForPrompt(project)

        let checkIns = try appModel.modelContext.fetch(
            FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp)])
        )
        XCTAssertEqual(checkIns.count, 2)
        XCTAssertEqual(checkIns[0].kind, "idle")
        XCTAssertEqual(checkIns[0].source, "unanswered-prompt")
        XCTAssertEqual(checkIns[1].project?.name, "Client Work")
        XCTAssertEqual(checkIns[1].timestamp, now)
        XCTAssertEqual(checkIns[1].source, "check-in")
        XCTAssertFalse(appModel.isIdlePending)
        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(25 * 60))
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

    private func projectCheckIn(project: ProjectRecord, at date: Date) -> CheckInRecord {
        CheckInRecord(
            timestamp: date,
            kind: "project",
            source: "test",
            project: project
        )
    }
}

private struct FixedCompletionClock: SchedulerClock {
    let now: Date
}
