import AppKit
import Foundation
import XCTest
@testable import TempoApp

final class CheckInPromptPresentationTests: XCTestCase {
    @MainActor
    func testBackdropBlocksMouseEventsAndStaysAboveApps() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let window = CheckInPromptWindowController.makeBackdropWindow(screenFrame: screenFrame)

        XCTAssertEqual(window.frame, screenFrame)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(window.level, .screenSaver)
    }

    @MainActor
    func testPromptUsesFullScreenAuxiliary() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let panel = CheckInPromptWindowController.makePromptWindow(screenFrame: screenFrame)

        XCTAssertEqual(panel.level, .screenSaver)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.canBecomeKey)
    }

    func testElapsedFormattingUsesMinutes() {
        XCTAssertEqual(
            TempoAppModel.formattedElapsedText(for: 25 * 60),
            "Elapsed 25 min"
        )
    }

    func testPromptFooterShowsDedicatedDoneForDayButton() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let promptSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/Features/CheckIn/CheckInPromptContent.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(promptSource.contains("Done for day"))
        XCTAssertFalse(promptSource.contains("Image(systemName: \"ellipsis\")"))
        XCTAssertFalse(promptSource.contains("Menu {"))
    }

    func testPromptDoesNotRenderQuestionMarkHelpIcon() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let promptSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/Features/CheckIn/CheckInPromptContent.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(promptSource.contains("Image(systemName: \"questionmark\")"))
        XCTAssertTrue(promptSource.contains(".help(\"Select an existing project or create one from what you type.\")"))
    }

    @MainActor
    func testPromptAlwaysUsesStandardSize() {
        let state = CheckInPromptState(
            isPresented: true,
            elapsedDuration: 0,
            isOverdue: false,
            promptTitle: "What are you currently doing",
            supportingSubtitle: "Idle detected"
        )

        XCTAssertEqual(CheckInPromptWindowController.promptSize(for: state), CGSize(width: 360, height: 320))
        XCTAssertEqual(CheckInPromptWindowController.promptSize(for: .hidden), CGSize(width: 360, height: 320))
    }

    @MainActor
    func testStandardPromptCentersOnScreen() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 840)
        let anchorRect = CGRect(x: 80, y: 760, width: 288, height: 320)

        let frame = CheckInPromptWindowController.promptFrame(
            in: visibleFrame,
            state: .hidden,
            anchorRect: anchorRect
        )

        XCTAssertEqual(frame.origin.x, 540)
        XCTAssertEqual(frame.origin.y, 260)
        XCTAssertEqual(frame.size, CGSize(width: 360, height: 320))
    }

    @MainActor
    func testNextRuntimeUpdateUsesNextCheckInWhenPromptIsNotShown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )

        appModel.nextCheckInAt = now.addingTimeInterval(300)
        appModel.silenceEndsAt = now.addingTimeInterval(900)
        appModel.isPromptOverdue = false

        XCTAssertEqual(appModel.nextRuntimeUpdateAt(referenceDate: now), now.addingTimeInterval(300))
    }

    @MainActor
    func testNextRuntimeUpdateUsesIdleDeadlineWhenPromptIsShown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )

        appModel.nextCheckInAt = now.addingTimeInterval(300)
        appModel.isPromptOverdue = true
        appModel.accountableElapsedInterval = 25 * 60
        appModel.presentCheckInPromptIfNeeded()

        XCTAssertEqual(appModel.nextRuntimeUpdateAt(referenceDate: now), now.addingTimeInterval(5 * 60))
    }

    @MainActor
    func testNextRuntimeUpdateDoesNotBackdateIdleDeadlineBeforePromptIsShown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )

        appModel.nextCheckInAt = now.addingTimeInterval(-(60 * 60))
        appModel.isPromptOverdue = true
        appModel.accountableElapsedInterval = 85 * 60

        XCTAssertNil(appModel.nextRuntimeUpdateAt(referenceDate: now))
    }

    @MainActor
    func testRecoverSchedulerStateMarksPersistedDeadlineOverdueWithoutSavedCheckIns() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let overdueDeadline = now.addingTimeInterval(-60)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )

        appModel.schedulerStateRecord.nextCheckInAt = overdueDeadline
        appModel.recoverSchedulerState(eventDate: now)

        XCTAssertTrue(appModel.isPromptOverdue)
        XCTAssertEqual(appModel.nextCheckInAt, overdueDeadline)
        XCTAssertEqual(appModel.accountableElapsedInterval, (26 * 60))
    }

    @MainActor
    func testAttachedPromptControllerDoesNotHidePromptWhenMenuBarWindowIsVisible() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )
        let controller = CheckInPromptWindowController()
        appModel.setMenuBarWindowVisible(true)
        appModel.checkInPromptState = CheckInPromptState(
            isPresented: true,
            elapsedDuration: 25 * 60,
            isOverdue: true,
            promptTitle: "What are you currently doing",
            supportingSubtitle: "Elapsed 25 min"
        )

        appModel.attachCheckInPromptWindowController(controller)

        XCTAssertTrue(controller.promptWindow?.isVisible ?? false)
        controller.hide()
    }

    @MainActor
    func testInitialLaunchShowsPromptAsSoonAsControllerIsAttached() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )
        let controller = CheckInPromptWindowController()
        appModel.attachCheckInPromptWindowController(controller)

        appModel.performInitialLaunchIfNeeded()
        appModel.presentCheckInPromptIfNeeded()

        XCTAssertTrue(appModel.checkInPromptState.isPresented)
        XCTAssertTrue(controller.promptWindow?.isVisible ?? false)
        controller.hide()
    }
}

private struct FixedPresentationClock: SchedulerClock {
    let now: Date
}

@MainActor
private final class FixedPresentationLaunchAtLoginController: LaunchAtLoginControlling {
    let isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {}
}

private func fixedPresentationCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}
