import AppKit
import Foundation
import XCTest
@testable import TempoApp

final class CheckInPromptPresentationTests: XCTestCase {
    @MainActor
    func testBackdropIgnoresMouseEvents() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let window = CheckInPromptWindowController.makeBackdropWindow(screenFrame: screenFrame)

        XCTAssertEqual(window.frame, screenFrame)
        XCTAssertTrue(window.ignoresMouseEvents)
    }

    @MainActor
    func testPromptUsesFullScreenAuxiliary() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let panel = CheckInPromptWindowController.makePromptWindow(screenFrame: screenFrame)

        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.canBecomeKey)
    }

    func testElapsedFormattingUsesMinutes() {
        XCTAssertEqual(
            TempoAppModel.formattedElapsedText(for: 25 * 60),
            "Elapsed 25 min"
        )
    }

    @MainActor
    func testStandardPromptSizeIsLargeEnoughForProjectSelection() {
        XCTAssertEqual(
            CheckInPromptWindowController.promptSize(for: .hidden),
            CGSize(width: 360, height: 320)
        )
    }

    @MainActor
    func testIdleResolutionPromptUsesExpandedSize() {
        let idleState = CheckInPromptState(
            isPresented: true,
            elapsedDuration: 0,
            isOverdue: false,
            promptTitle: "Resolve idle time",
            supportingSubtitle: "Elapsed 0 min"
        )

        XCTAssertEqual(
            CheckInPromptWindowController.promptSize(for: idleState),
            CGSize(width: 392, height: 420)
        )
    }

    @MainActor
    func testStandardPromptDoesNotUseBackdrop() {
        XCTAssertFalse(CheckInPromptWindowController.wantsBackdrop(for: .hidden))
    }

    @MainActor
    func testIdleResolutionPromptUsesBackdrop() {
        let idleState = CheckInPromptState(
            isPresented: true,
            elapsedDuration: 0,
            isOverdue: false,
            promptTitle: "Resolve idle time",
            supportingSubtitle: "Elapsed 0 min"
        )

        XCTAssertFalse(CheckInPromptWindowController.wantsBackdrop(for: idleState))
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
        appModel.delayedUntilAt = now.addingTimeInterval(600)
        appModel.silenceEndsAt = now.addingTimeInterval(900)
        appModel.isPromptOverdue = false

        XCTAssertEqual(appModel.nextRuntimeUpdateAt(referenceDate: now), now.addingTimeInterval(300))
    }

    @MainActor
    func testNextRuntimeUpdateStopsWhenPromptIsAlreadyOverdue() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )

        appModel.nextCheckInAt = now.addingTimeInterval(300)
        appModel.isPromptOverdue = true

        XCTAssertNil(appModel.nextRuntimeUpdateAt(referenceDate: now))
    }

    @MainActor
    func testDetachedPromptStateHidesWhileMenuBarWindowIsVisible() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let appModel = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedPresentationClock(now: now),
            calendar: fixedPresentationCalendar(),
            launchAtLoginController: FixedPresentationLaunchAtLoginController(isEnabled: false)
        )

        appModel.isPromptOverdue = true
        appModel.accountableElapsedInterval = 25 * 60
        appModel.refreshCheckInPromptState()

        XCTAssertTrue(appModel.checkInPromptState.isPresented)
        XCTAssertTrue(appModel.detachedCheckInPromptState.isPresented)

        appModel.setMenuBarWindowVisible(true)

        XCTAssertFalse(appModel.detachedCheckInPromptState.isPresented)
        XCTAssertTrue(appModel.checkInPromptState.isPresented)

        appModel.setMenuBarWindowVisible(false)

        XCTAssertTrue(appModel.detachedCheckInPromptState.isPresented)
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
