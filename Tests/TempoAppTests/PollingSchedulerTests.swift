import Foundation
import XCTest
@testable import TempoApp

final class PollingSchedulerTests: XCTestCase {
    func testFirstLaunchSchedulesFromNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord()

        let result = scheduler.updateState(state, settings: settings, eventDate: now)

        XCTAssertEqual(result.nextCheckInAt, now.addingTimeInterval(25 * 60))
        XCTAssertFalse(result.isPromptOverdue)
        XCTAssertEqual(result.accountableElapsedInterval, 25 * 60)
    }

    func testRelaunchPreservesFutureCheckIn() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nextCheckInAt = now.addingTimeInterval(10 * 60)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-15 * 60),
            nextCheckInAt: nextCheckInAt,
            lastAppLaunchAt: now.addingTimeInterval(-60)
        )

        let result = scheduler.updateState(state, settings: settings, eventDate: now)

        XCTAssertEqual(result.nextCheckInAt, nextCheckInAt)
        XCTAssertFalse(result.isPromptOverdue)
        XCTAssertEqual(result.accountableElapsedInterval, 25 * 60)
    }

    func testOverdueWakeMarksPromptOverdue() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let overdueCheckInAt = now.addingTimeInterval(-10 * 60)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-35 * 60),
            nextCheckInAt: overdueCheckInAt,
            lastAppLaunchAt: now.addingTimeInterval(-90)
        )

        let result = scheduler.updateState(state, settings: settings, eventDate: now)

        XCTAssertEqual(result.nextCheckInAt, overdueCheckInAt)
        XCTAssertTrue(result.isPromptOverdue)
        XCTAssertEqual(result.accountableElapsedInterval, 35 * 60)
    }
}

private struct FixedSchedulerClock: SchedulerClock {
    let now: Date
}
