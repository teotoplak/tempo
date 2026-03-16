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
        model.modelContext.insert(
            CheckInRecord(
                timestamp: pendingIdleStart,
                kind: "idle",
                source: "screen-locked",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try? model.modelContext.save()
        model.recoverSchedulerState(eventDate: now, activityDate: now)

        model.checkInNow()

        XCTAssertTrue(model.isIdlePending)
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
        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(21 * 60)),
                kind: "idle",
                source: "inactivity",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try model.modelContext.save()
        model.recoverSchedulerState(eventDate: now, activityDate: now)
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

        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(21 * 60)),
                kind: "idle",
                source: "inactivity",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try model.modelContext.save()
        model.recoverSchedulerState(eventDate: now, activityDate: now)
        model.updatePromptSearchText("")
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
        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(21 * 60)),
                kind: "idle",
                source: "inactivity",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try model.modelContext.save()
        model.recoverSchedulerState(eventDate: now, activityDate: now)
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
        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(12 * 60)),
                kind: "idle",
                source: "screen-locked",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try? model.modelContext.save()
        model.recoverSchedulerState(eventDate: now, activityDate: now)
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
        XCTAssertTrue(menuSource.contains("summaryDateTitle"))
        XCTAssertTrue(menuSource.contains("Troubleshooting check-ins"))
        XCTAssertFalse(menuSource.contains("label: \"Tracked\""))
        XCTAssertFalse(menuSource.contains("label: \"Started\""))
        XCTAssertFalse(menuSource.contains("label: \"Finished\""))
    }

    func testMenuBarSceneUsesDedicatedLabelView() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/App/TempoApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appSource.contains("MenuBarLabelView(appModel: appModel)"))
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
        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(20 * 60 * 60)),
                kind: "idle",
                source: "done-for-day",
                idleKind: TimeAllocationIdleKind.doneForDay.rawValue
            )
        )
        try? model.modelContext.save()

        model.performInitialLaunchIfNeeded()

        XCTAssertFalse(model.isSilenced)
        XCTAssertNil(model.silenceEndsAt)
        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertGreaterThanOrEqual(model.accountableElapsedInterval, 25 * 60)
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
        let project = ProjectRecord(name: "Focus", sortOrder: 0)
        model.modelContext.insert(project)
        model.modelContext.insert(
            CheckInRecord(
                timestamp: now.addingTimeInterval(-(4 * 60 * 60)),
                kind: "project",
                source: "check-in",
                project: project
            )
        )
        try? model.modelContext.save()

        model.handleSceneActivation()

        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertEqual(model.accountableElapsedInterval, 4 * 60 * 60)
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
        model.modelContext.insert(
            CheckInRecord(
                timestamp: pendingIdleStart,
                kind: "idle",
                source: "inactivity",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
        try? model.modelContext.save()

        model.handleSceneActivation(activityDate: now)

        XCTAssertTrue(model.isIdlePending)
        XCTAssertEqual(model.pendingIdleEndedAt, now)
        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertNil(model.nextCheckInAt)
    }

    @MainActor
    func testRecoverSchedulerStateHealsStalePendingIdleWhenNewerProjectCheckInExists() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let projectCheckInAt = now.addingTimeInterval(-(5 * 60))
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now),
            calendar: fixedBootstrapCalendar(),
            launchAtLoginController: FixedLaunchAtLoginController(isEnabled: true)
        )
        let project = ProjectRecord(name: "Client Work", sortOrder: 0)
        model.modelContext.insert(project)
        model.modelContext.insert(
            CheckInRecord(
                timestamp: projectCheckInAt,
                kind: "project",
                source: "idle-return",
                project: project
            )
        )
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-(40 * 60))
        model.schedulerStateRecord.pendingIdleStartedAt = now.addingTimeInterval(-(20 * 60))
        model.schedulerStateRecord.pendingIdleEndedAt = now.addingTimeInterval(-(15 * 60))
        model.schedulerStateRecord.pendingIdleReason = "screen-locked"
        try model.modelContext.save()

        model.recoverSchedulerState(eventDate: now)

        XCTAssertFalse(model.isIdlePending)
        XCTAssertEqual(model.nextCheckInAt, projectCheckInAt.addingTimeInterval(25 * 60))
        XCTAssertFalse(model.isPromptOverdue)
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
