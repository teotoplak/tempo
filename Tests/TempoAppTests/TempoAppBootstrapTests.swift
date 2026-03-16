import Foundation
import XCTest
@testable import TempoApp

final class TempoAppBootstrapTests: XCTestCase {
    @MainActor
    func testTempoAppModelBootstraps() throws {
        let model = TempoAppModel(modelContainer: TempoModelContainer.inMemory())

        XCTAssertEqual(model.launchState, .launching)
        XCTAssertEqual(model.settings.pollingIntervalMinutes, 25)
        XCTAssertEqual(model.settings.idleThresholdMinutes, 5)
        XCTAssertEqual(model.settings.analyticsDayCutoffHour, 6)
    }

    @MainActor
    func testSilenceForRestOfDayHidesPrompt() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.schedulerStateRecord.nextCheckInAt = now
        model.isPromptOverdue = true
        model.accountableElapsedInterval = 30 * 60
        model.promptSearchText = "client"
        model.refreshCheckInPromptState()

        try model.silenceForRestOfDay()

        XCTAssertTrue(model.isSilenced)
        XCTAssertFalse(model.checkInPromptState.isPresented)
        XCTAssertEqual(model.accountableElapsedInterval, 0)
        XCTAssertEqual(model.promptSearchText, "")
    }

    @MainActor
    func testCheckInNowShowsPrompt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-20 * 60)
        model.schedulerStateRecord.nextCheckInAt = now.addingTimeInterval(5 * 60)

        model.checkInNow()

        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertGreaterThanOrEqual(model.accountableElapsedInterval, 25 * 60)
    }

    @MainActor
    func testCheckInNowMarksReturnedIdleAsResolved() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        let pendingIdleStart = now.addingTimeInterval(-(15 * 60))
        let pendingIdleDetectedAt = now.addingTimeInterval(-(10 * 60))
        model.schedulerStateRecord.pendingIdleStartedAt = pendingIdleStart
        model.schedulerStateRecord.pendingIdleEndedAt = pendingIdleDetectedAt
        model.schedulerStateRecord.pendingIdleReason = "inactivity"
        model.pendingIdleStartedAt = pendingIdleStart
        model.pendingIdleEndedAt = pendingIdleDetectedAt
        model.pendingIdleReason = "inactivity"
        model.pendingIdleDuration = pendingIdleDetectedAt.timeIntervalSince(pendingIdleStart)
        model.isIdlePending = true

        model.checkInNow()

        XCTAssertTrue(model.isIdlePending)
        XCTAssertEqual(model.schedulerStateRecord.idleResolvedAt, now)
        XCTAssertEqual(model.pendingIdleEndedAt, now)
        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertNil(model.nextCheckInAt)
    }

    @MainActor
    func testPerformInitialLaunchShowsPromptImmediately() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-(30 * 60))

        model.performInitialLaunchIfNeeded()

        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertFalse(model.isIdlePending)
    }

    @MainActor
    func testHandleScreenLockMarksIdlePending() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-(20 * 60))
        model.schedulerStateRecord.nextCheckInAt = now.addingTimeInterval(5 * 60)

        model.handleScreenLock()

        XCTAssertTrue(model.isIdlePending)
        XCTAssertEqual(model.pendingIdleReason, "screen-locked")
        XCTAssertFalse(model.checkInPromptState.isPresented)
        XCTAssertEqual(model.accountableElapsedInterval, 0)
        XCTAssertEqual(model.pendingIdleDuration, 0)
    }

    @MainActor
    func testSubmitPromptSearchCreatesProjectWhenQueryIsNew() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.pendingIdleStartedAt = now.addingTimeInterval(-(21 * 60))
        model.pendingIdleEndedAt = now
        model.pendingIdleDuration = 21 * 60
        model.pendingIdleReason = "inactivity"
        model.isIdlePending = true
        model.refreshCheckInPromptState()

        model.updatePromptSearchText("test")
        try model.submitPromptSearch()

        XCTAssertFalse(model.canCreatePromptProject(named: "test"))
        XCTAssertEqual(model.selectedPromptProject?.name, "test")
    }

    @MainActor
    func testIdleResolutionDefaultsToLatestAssignedProject() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        try model.createProject(named: "Alpha")
        try model.createProject(named: "Beta")

        let latestProject = try XCTUnwrap(model.recentPromptProjects.first(where: { $0.name == "Beta" }))
        let earlierProject = try XCTUnwrap(model.recentPromptProjects.first(where: { $0.name == "Alpha" }))
        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(40 * 60)),
                kind: "project",
                source: "test",
                project: earlierProject
            )
        )
        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(10 * 60)),
                kind: "project",
                source: "test",
                project: latestProject
            )
        )
        try model.modelContext.save()

        model.pendingIdleStartedAt = now.addingTimeInterval(-(21 * 60))
        model.pendingIdleEndedAt = now
        model.pendingIdleDuration = 21 * 60
        model.pendingIdleReason = "inactivity"
        model.isIdlePending = true

        model.refreshCheckInPromptState()

        XCTAssertEqual(model.selectedPromptProject?.name, "Beta")
    }

    @MainActor
    func testUpdatePromptSearchTextSelectsExactMatchForOneClickIdleAssignment() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        try model.createProject(named: "Alpha")
        try model.createProject(named: "Beta")
        model.pendingIdleStartedAt = now.addingTimeInterval(-(21 * 60))
        model.pendingIdleEndedAt = now
        model.pendingIdleDuration = 21 * 60
        model.pendingIdleReason = "inactivity"
        model.isIdlePending = true
        model.refreshCheckInPromptState()

        model.updatePromptSearchText("beta")

        XCTAssertEqual(model.selectedPromptProject?.name, "Beta")
    }

    @MainActor
    func testIdleResolutionPromptBlocksStandardCheckInCopy() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.pendingIdleStartedAt = now.addingTimeInterval(-(12 * 60))
        model.pendingIdleEndedAt = now
        model.pendingIdleReason = "screen-locked"
        model.pendingIdleDuration = 12 * 60
        model.isIdlePending = true
        model.schedulerStateRecord.idleResolvedAt = now

        model.refreshCheckInPromptState()

        XCTAssertEqual(model.checkInPromptState.promptTitle, "What are you currently doing")
        XCTAssertEqual(model.pendingIdleReasonDisplayText, "Screen locked")
    }

    func testPackageManifestStaysLocalOnly() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = rootURL.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

        XCTAssertTrue(manifest.contains("platforms: ["))
        XCTAssertTrue(manifest.contains(".executableTarget("))
        XCTAssertFalse(manifest.contains(".package(url:"))
    }

    func testMenuBarQuickActionsRemainAvailable() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/Views/MenuBarRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(menuSource.contains("Check In Now"))
        XCTAssertTrue(menuSource.contains("Analytics"))
        XCTAssertTrue(menuSource.contains("Projects"))
        XCTAssertTrue(menuSource.contains("Settings"))
        XCTAssertTrue(menuSource.contains("Quit Tempo"))
        XCTAssertTrue(menuSource.contains("appModel.setMenuBarWindowVisible(true)"))
        XCTAssertFalse(menuSource.contains("inlinePromptContent"))
    }

    func testMenuBarIncludesDailySummaryContent() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/Views/MenuBarRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(menuSource.contains("No tracked time today"))
        XCTAssertTrue(menuSource.contains("Tracked"))
        XCTAssertTrue(menuSource.contains("Started"))
        XCTAssertTrue(menuSource.contains("Finished"))
        XCTAssertTrue(menuSource.contains("summaryDateTitle"))
    }

    @MainActor
    func testAnalyticsWindowSectionStillExists() {
        XCTAssertTrue(TempoAppModel.WindowSection.allCases.contains(.analytics))
    }

    @MainActor
    func testPerformInitialLaunchRecoversExpiredSilenceState() {
        let now = Date(timeIntervalSince1970: 1_700_006_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now),
            calendar: fixedBootstrapCalendar(),
            launchAtLoginController: FixedLaunchAtLoginController(isEnabled: false)
        )
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-(3 * 60 * 60))
        model.schedulerStateRecord.nextCheckInAt = now.addingTimeInterval(-(2 * 60 * 60))
        model.schedulerStateRecord.silenceEndsAt = now.addingTimeInterval(-(90 * 60))

        model.performInitialLaunchIfNeeded()

        XCTAssertFalse(model.isSilenced)
        XCTAssertNil(model.silenceEndsAt)
        XCTAssertEqual(model.nextCheckInAt, now.addingTimeInterval(25 * 60))
        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertEqual(model.accountableElapsedInterval, 3 * 60 * 60)
    }

    @MainActor
    func testHandleSceneActivationRecoversOverduePromptAfterRelaunch() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now),
            calendar: fixedBootstrapCalendar(),
            launchAtLoginController: FixedLaunchAtLoginController(isEnabled: true)
        )
        model.settings.idleThresholdMinutes = 10_000
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-(4 * 60 * 60))
        model.schedulerStateRecord.nextCheckInAt = now.addingTimeInterval(-(2 * 60 * 60))

        model.handleSceneActivation()

        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertEqual(model.accountableElapsedInterval, (2 * 60 * 60) + (25 * 60))
    }

    @MainActor
    func testHandleSceneActivationMarksReturnedIdleAsResolvedWhenActivityResumes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now),
            calendar: fixedBootstrapCalendar(),
            launchAtLoginController: FixedLaunchAtLoginController(isEnabled: true)
        )
        model.settings.idleThresholdMinutes = 10_000
        let pendingIdleStart = now.addingTimeInterval(-(15 * 60))
        let pendingIdleDetectedAt = now.addingTimeInterval(-(10 * 60))
        model.schedulerStateRecord.pendingIdleStartedAt = pendingIdleStart
        model.schedulerStateRecord.pendingIdleEndedAt = pendingIdleDetectedAt
        model.schedulerStateRecord.pendingIdleReason = "inactivity"
        model.pendingIdleStartedAt = pendingIdleStart
        model.pendingIdleEndedAt = pendingIdleDetectedAt
        model.pendingIdleReason = "inactivity"
        model.pendingIdleDuration = pendingIdleDetectedAt.timeIntervalSince(pendingIdleStart)
        model.isIdlePending = true

        model.handleSceneActivation(activityDate: now)

        XCTAssertTrue(model.isIdlePending)
        XCTAssertEqual(model.schedulerStateRecord.idleResolvedAt, now)
        XCTAssertEqual(model.pendingIdleEndedAt, now)
        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertNil(model.nextCheckInAt)
    }
}

private struct FixedBootstrapClock: SchedulerClock {
    let now: Date
}

@MainActor
private final class FixedLaunchAtLoginController: LaunchAtLoginControlling {
    let isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {}
}

private func fixedBootstrapCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}
