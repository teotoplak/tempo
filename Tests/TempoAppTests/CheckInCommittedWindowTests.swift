import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CheckInCommittedWindowTests: XCTestCase {
    func testWindowLengthDisplayNames() {
        XCTAssertEqual(
            CheckInWindowLength.pollingDefault.displayName(pollingIntervalMinutes: 25),
            "Default (25 min)"
        )
        XCTAssertEqual(
            CheckInWindowLength.fixed(minutes: 30).displayName(pollingIntervalMinutes: 25),
            "30 min"
        )
        XCTAssertEqual(
            CheckInWindowLength.fixed(minutes: 60).displayName(pollingIntervalMinutes: 25),
            "1 hour"
        )
        XCTAssertEqual(
            CheckInWindowLength.fixed(minutes: 480).displayName(pollingIntervalMinutes: 25),
            "8 hours"
        )
    }

    func testWindowLengthCommittedEnd() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(CheckInWindowLength.pollingDefault.committedWindowEnd(from: now))
        XCTAssertEqual(
            CheckInWindowLength.fixed(minutes: 120).committedWindowEnd(from: now),
            now.addingTimeInterval(2 * 60 * 60)
        )
    }

    func testSelectableOptionsCoverDefaultThroughEightHours() {
        XCTAssertEqual(
            CheckInWindowLength.selectableOptions.map(\.id),
            [0, 30, 60, 120, 180, 240, 300, 360, 420, 480]
        )
    }

    @MainActor
    func testSelectingProjectWithFixedWindowCommitsUntilWindowEnd() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCommittedWindowClock(now: now)
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)

        try appModel.selectProjectForPrompt(project)

        let checkIns = try fetchCheckIns(in: appModel)
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertEqual(checkIns[0].committedWindowEndsAt, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertTrue(appModel.isCommittedWindowActive)
        XCTAssertFalse(appModel.isPromptOverdue)
        XCTAssertFalse(appModel.checkInPromptState.isPresented)
        XCTAssertEqual(appModel.promptWindowLength, .pollingDefault)
        XCTAssertEqual(appModel.committedWindowActivityName, "Team Offsite")
    }

    @MainActor
    func testSelectingProjectWithDefaultWindowKeepsPollingInterval() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCommittedWindowClock(now: now)
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Client Work")

        try appModel.selectProjectForPrompt(project)

        let checkIns = try fetchCheckIns(in: appModel)
        XCTAssertNil(checkIns[0].committedWindowEndsAt)
        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(25 * 60))
        XCTAssertFalse(appModel.isCommittedWindowActive)
    }

    @MainActor
    func testUntrackedSelectionSupportsFixedWindow() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCommittedWindowClock(now: now)
        )
        _ = try presentedPrompt(in: appModel, projectNamed: "Client Work")
        appModel.promptWindowLength = .fixed(minutes: 60)

        try appModel.selectUntrackedForPrompt()

        let checkIns = try fetchCheckIns(in: appModel)
        XCTAssertEqual(checkIns[0].kind, "untracked")
        XCTAssertEqual(checkIns[0].committedWindowEndsAt, now.addingTimeInterval(60 * 60))
        XCTAssertEqual(appModel.committedWindowActivityName, "Untracked")
    }

    @MainActor
    func testScreenLockInsideCommittedWindowDoesNotRecordIdle() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableCommittedWindowClock(now: now)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: clock
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)
        try appModel.selectProjectForPrompt(project)

        clock.now = now.addingTimeInterval(20 * 60)
        appModel.handleScreenLock(activityDate: clock.now)
        clock.now = now.addingTimeInterval(90 * 60)
        appModel.handleScreenWake(activityDate: clock.now)

        let checkIns = try fetchCheckIns(in: appModel)
        XCTAssertEqual(checkIns.count, 1)
        XCTAssertFalse(appModel.isIdlePending)
        XCTAssertFalse(appModel.checkInPromptState.isPresented)
        XCTAssertTrue(appModel.isCommittedWindowActive)
    }

    @MainActor
    func testElapsedCommittedWindowIsClosedAtWindowEndAndPromptsImmediately() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableCommittedWindowClock(now: now)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: clock
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)
        try appModel.selectProjectForPrompt(project)
        let windowEnd = now.addingTimeInterval(2 * 60 * 60)

        clock.now = windowEnd.addingTimeInterval(10 * 60)
        appModel.recoverSchedulerState(eventDate: clock.now, activityDate: clock.now)

        let checkIns = try fetchCheckIns(in: appModel)
        XCTAssertEqual(checkIns.count, 2)
        XCTAssertEqual(checkIns[1].timestamp, windowEnd)
        XCTAssertEqual(checkIns[1].kind, "project")
        XCTAssertEqual(checkIns[1].project?.name, "Team Offsite")
        XCTAssertEqual(checkIns[1].source, "committed-window-end")
        XCTAssertNil(checkIns[1].committedWindowEndsAt)
        XCTAssertFalse(appModel.isCommittedWindowActive)
        XCTAssertTrue(appModel.isPromptOverdue)
        XCTAssertEqual(appModel.accountableElapsedInterval, 10 * 60)
        XCTAssertEqual(allocatedSeconds(in: appModel, forProjectNamed: "Team Offsite"), 2 * 60 * 60)
    }

    @MainActor
    func testElapsedCommittedWindowIsClosedOnlyOnce() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableCommittedWindowClock(now: now)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: clock
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)
        try appModel.selectProjectForPrompt(project)

        clock.now = now.addingTimeInterval(3 * 60 * 60)
        appModel.recoverSchedulerState(eventDate: clock.now, activityDate: clock.now)
        appModel.recoverSchedulerState(eventDate: clock.now, activityDate: clock.now)
        appModel.handleAppWake()

        XCTAssertEqual(try fetchCheckIns(in: appModel).count, 2)
    }

    @MainActor
    func testRelaunchInsideCommittedWindowKeepsWindowIntact() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableCommittedWindowClock(now: now)
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container, clock: clock)
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)
        try appModel.selectProjectForPrompt(project)

        clock.now = now.addingTimeInterval(30 * 60)
        let relaunchedModel = TempoAppModel(modelContainer: container, clock: clock)
        relaunchedModel.performInitialLaunchIfNeeded(activityDate: clock.now)

        XCTAssertEqual(try fetchCheckIns(in: relaunchedModel).count, 1)
        XCTAssertTrue(relaunchedModel.isCommittedWindowActive)
        XCTAssertFalse(relaunchedModel.checkInPromptState.isPresented)
        XCTAssertEqual(relaunchedModel.nextCheckInAt, now.addingTimeInterval(2 * 60 * 60))
    }

    @MainActor
    func testCheckInNowEndsCommittedWindowEarlyAndBanksElapsedTime() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableCommittedWindowClock(now: now)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: clock
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)
        try appModel.selectProjectForPrompt(project)

        clock.now = now.addingTimeInterval(40 * 60)
        appModel.checkInNow(trigger: "hotkey")

        let checkIns = try fetchCheckIns(in: appModel)
        XCTAssertEqual(checkIns.count, 2)
        XCTAssertEqual(checkIns[1].timestamp, clock.now)
        XCTAssertEqual(checkIns[1].source, "committed-window-end")
        XCTAssertFalse(appModel.isCommittedWindowActive)
        XCTAssertTrue(appModel.checkInPromptState.isPresented)
        XCTAssertEqual(allocatedSeconds(in: appModel, forProjectNamed: "Team Offsite"), 40 * 60)
    }

    @MainActor
    func testDoneForDayDuringCommittedWindowBanksElapsedTime() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = MutableCommittedWindowClock(now: now)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: clock
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)
        try appModel.selectProjectForPrompt(project)

        clock.now = now.addingTimeInterval(30 * 60)
        try appModel.silenceForRestOfDay(trigger: "test")

        let checkIns = try fetchCheckIns(in: appModel)
        XCTAssertEqual(checkIns.count, 2)
        XCTAssertEqual(checkIns[1].idleKind, "done-for-day")
        XCTAssertTrue(appModel.isSilenced)
        XCTAssertFalse(appModel.isCommittedWindowActive)
        XCTAssertEqual(allocatedSeconds(in: appModel, forProjectNamed: "Team Offsite"), 30 * 60)
    }

    @MainActor
    func testChangingPollingIntervalKeepsCommittedWindow() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedCommittedWindowClock(now: now)
        )
        let project = try presentedPrompt(in: appModel, projectNamed: "Team Offsite")
        appModel.promptWindowLength = .fixed(minutes: 120)
        try appModel.selectProjectForPrompt(project)

        appModel.settings.pollingIntervalMinutes = 45
        try appModel.saveSettings()

        XCTAssertTrue(appModel.isCommittedWindowActive)
        XCTAssertEqual(appModel.nextCheckInAt, now.addingTimeInterval(2 * 60 * 60))
    }

    @MainActor
    private func presentedPrompt(
        in appModel: TempoAppModel,
        projectNamed name: String
    ) throws -> ProjectRecord {
        let project = ProjectRecord(name: name, sortOrder: 0)
        appModel.modelContext.insert(project)
        try appModel.modelContext.save()
        appModel.accountableElapsedInterval = 25 * 60
        appModel.isPromptOverdue = true
        appModel.refreshCheckInPromptState()
        return project
    }

    @MainActor
    private func fetchCheckIns(in appModel: TempoAppModel) throws -> [CheckInRecord] {
        try appModel.modelContext.fetch(
            FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp)])
        )
    }

    @MainActor
    private func allocatedSeconds(
        in appModel: TempoAppModel,
        forProjectNamed name: String
    ) -> TimeInterval {
        let checkIns = (try? fetchCheckIns(in: appModel)) ?? []
        let allocationCheckIns = checkIns.compactMap { record -> TimeAllocationCheckIn? in
            switch record.kind {
            case "project":
                guard let project = record.project else {
                    return nil
                }

                return TimeAllocationCheckIn(
                    id: record.id,
                    timestamp: record.timestamp,
                    kind: .project(id: project.id, name: project.name),
                    source: record.source
                )
            case "untracked":
                return TimeAllocationCheckIn(
                    id: record.id,
                    timestamp: record.timestamp,
                    kind: .untracked,
                    source: record.source
                )
            case "idle":
                guard
                    let idleKindRawValue = record.idleKind,
                    let idleKind = TimeAllocationIdleKind(persistedValue: idleKindRawValue)
                else {
                    return nil
                }

                return TimeAllocationCheckIn(
                    id: record.id,
                    timestamp: record.timestamp,
                    kind: .idle(kind: idleKind),
                    source: record.source
                )
            default:
                return nil
            }
        }

        return TimeAllocationEngine()
            .summary(
                checkIns: allocationCheckIns,
                range: .year,
                referenceDate: allocationCheckIns.first?.timestamp ?? Date(),
                dayCutoffHour: 6
            )
            .bucketSummaries
            .first { $0.bucket.displayName == name }?
            .totalDuration ?? 0
    }
}

private struct FixedCommittedWindowClock: SchedulerClock {
    let now: Date
}

private final class MutableCommittedWindowClock: SchedulerClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
