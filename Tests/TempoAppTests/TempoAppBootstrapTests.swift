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
    func testDetectInactivityIfNeededMarksIdlePending() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-(30 * 60))
        model.schedulerStateRecord.nextCheckInAt = now.addingTimeInterval(-(5 * 60))

        model.detectInactivityIfNeeded(activityDate: now.addingTimeInterval(-(7 * 60)))

        XCTAssertTrue(model.isIdlePending)
        XCTAssertFalse(model.checkInPromptState.isPresented)
        XCTAssertEqual(model.accountableElapsedInterval, 0)
        XCTAssertEqual(model.pendingIdleDuration, 7 * 60)
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

        XCTAssertEqual(model.checkInPromptState.promptTitle, "Resolve idle time")
        XCTAssertNotEqual(model.checkInPromptState.promptTitle, "What are you currently doing")
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

        XCTAssertTrue(menuSource.contains("Open Analytics"))
        XCTAssertTrue(menuSource.contains("Settings"))
        XCTAssertTrue(menuSource.contains("Quit Tempo"))
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
        model.schedulerStateRecord.silencedAt = now.addingTimeInterval(-(4 * 60 * 60))
        model.schedulerStateRecord.silenceEndsAt = now.addingTimeInterval(-(90 * 60))

        model.performInitialLaunchIfNeeded()

        XCTAssertFalse(model.isSilenced)
        XCTAssertNil(model.silenceEndsAt)
        XCTAssertEqual(model.nextCheckInAt, now.addingTimeInterval(25 * 60))
        XCTAssertEqual(model.accountableElapsedInterval, 25 * 60)
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
        model.schedulerStateRecord.lastAppLaunchAt = now.addingTimeInterval(-(40 * 60))

        model.handleSceneActivation()

        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertEqual(model.accountableElapsedInterval, 40 * 60)
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
