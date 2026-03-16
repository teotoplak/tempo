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
