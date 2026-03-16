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
        XCTAssertEqual(result.accountableElapsedInterval, 25 * 60)
    }

    func testCompleteCheckInSchedulesFromCompletionDate() {
        let completionDate = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: completionDate))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: completionDate.addingTimeInterval(-45 * 60),
            nextCheckInAt: completionDate.addingTimeInterval(-5 * 60),
            lastAppLaunchAt: completionDate.addingTimeInterval(-10)
        )

        let result = scheduler.completeCheckIn(
            state: state,
            settings: settings,
            completionDate: completionDate
        )

        XCTAssertEqual(result.lastCheckInAt, completionDate)
        XCTAssertEqual(result.nextCheckInAt, completionDate.addingTimeInterval(25 * 60))
        XCTAssertFalse(result.isPromptOverdue)
        XCTAssertEqual(result.accountableElapsedInterval, 25 * 60)
    }

    func testDelayCheckInSchedulesFuturePrompt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-25 * 60),
            nextCheckInAt: now,
            lastAppLaunchAt: now.addingTimeInterval(-60)
        )

        let result = scheduler.delayCheckIn(
            state: state,
            settings: settings,
            delayMinutes: 15,
            delayDate: now
        )

        XCTAssertEqual(result.nextCheckInAt, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(result.delayedUntilAt, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(result.delayedFromPromptAt, now)
        XCTAssertTrue(result.snapshot.isPromptDelayed)
        XCTAssertFalse(result.snapshot.isSilenced)
    }

    func testDelayedPromptBecomesDueAfterDelayExpires() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-25 * 60),
            nextCheckInAt: now.addingTimeInterval(15 * 60),
            lastAppLaunchAt: now,
            delayedUntilAt: now.addingTimeInterval(15 * 60),
            delayedFromPromptAt: now
        )

        let result = scheduler.updateState(
            state,
            settings: settings,
            eventDate: now.addingTimeInterval(20 * 60)
        )

        XCTAssertTrue(result.isPromptOverdue)
        XCTAssertFalse(result.snapshot.isPromptDelayed)
        XCTAssertNil(result.delayedUntilAt)
        XCTAssertEqual(result.accountableElapsedInterval, 25 * 60)
    }

    func testSilenceUntilEndOfDaySuppressesPrompt() {
        let eventDate = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: eventDate))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: eventDate.addingTimeInterval(-25 * 60),
            nextCheckInAt: eventDate,
            lastAppLaunchAt: eventDate.addingTimeInterval(-60)
        )

        let result = scheduler.silenceUntilEndOfDay(
            state: state,
            settings: settings,
            eventDate: eventDate
        )

        let expectedMidnight = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: eventDate)
        )

        XCTAssertEqual(result.silenceEndsAt, expectedMidnight)
        XCTAssertTrue(result.snapshot.isSilenced)
        XCTAssertFalse(result.isPromptOverdue)
        XCTAssertEqual(result.accountableElapsedInterval, 0)
    }

    func testSilenceClearsAtMidnight() {
        let eventDate = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: eventDate))
        let settings = AppSettingsRecord()
        let midnight = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: eventDate)
        )!
        let state = SchedulerStateRecord(
            lastCheckInAt: eventDate.addingTimeInterval(-25 * 60),
            nextCheckInAt: midnight,
            lastAppLaunchAt: eventDate,
            silencedAt: eventDate,
            silenceEndsAt: midnight
        )

        let result = scheduler.updateState(
            state,
            settings: settings,
            eventDate: midnight
        )

        XCTAssertFalse(result.snapshot.isSilenced)
        XCTAssertNil(result.silenceEndsAt)
        XCTAssertEqual(result.nextCheckInAt, midnight.addingTimeInterval(25 * 60))
        XCTAssertEqual(result.accountableElapsedInterval, 25 * 60)
    }

    func testEndSilenceSchedulesFromUnsilenceTime() {
        let eventDate = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: eventDate))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: eventDate.addingTimeInterval(-25 * 60),
            nextCheckInAt: eventDate.addingTimeInterval(60 * 60),
            lastAppLaunchAt: eventDate,
            silencedAt: eventDate.addingTimeInterval(-10),
            silenceEndsAt: eventDate.addingTimeInterval(60 * 60)
        )

        let result = scheduler.endSilence(
            state: state,
            settings: settings,
            eventDate: eventDate
        )

        XCTAssertEqual(result.nextCheckInAt, eventDate.addingTimeInterval(25 * 60))
        XCTAssertFalse(result.snapshot.isSilenced)
        XCTAssertNil(result.silenceEndsAt)
    }

    func testBeginIdleIntervalSuspendsAccountableElapsed() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-(40 * 60)),
            nextCheckInAt: now.addingTimeInterval(-(15 * 60)),
            lastAppLaunchAt: now.addingTimeInterval(-(10 * 60))
        )

        let result = scheduler.beginIdleInterval(
            state: state,
            settings: settings,
            eventDate: now,
            reason: "inactivity"
        )

        XCTAssertTrue(result.snapshot.isIdlePending)
        XCTAssertEqual(result.pendingIdleStartedAt, now)
        XCTAssertEqual(result.pendingIdleEndedAt, now)
        XCTAssertEqual(result.pendingIdleReason, "inactivity")
        XCTAssertEqual(result.accountableElapsedInterval, 0)
        XCTAssertNil(result.nextCheckInAt)
    }

    func testScreenLockCreatesPendingIdleInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-(25 * 60)),
            nextCheckInAt: now.addingTimeInterval(5 * 60),
            lastAppLaunchAt: now.addingTimeInterval(-(60)),
            delayedUntilAt: now.addingTimeInterval(15 * 60),
            delayedFromPromptAt: now,
            silencedAt: now.addingTimeInterval(-(30)),
            silenceEndsAt: now.addingTimeInterval(60 * 60)
        )

        let result = scheduler.beginIdleInterval(
            state: state,
            settings: settings,
            eventDate: now,
            reason: "screen-locked"
        )

        XCTAssertTrue(result.snapshot.isIdlePending)
        XCTAssertEqual(result.pendingIdleReason, "screen-locked")
        XCTAssertNil(result.delayedUntilAt)
        XCTAssertNil(result.silenceEndsAt)
        XCTAssertFalse(result.snapshot.isPromptDelayed)
        XCTAssertFalse(result.snapshot.isSilenced)
    }

    func testResolveReturnedIdleStateKeepsPendingIdleUnscheduled() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now))
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-(45 * 60)),
            lastAppLaunchAt: now.addingTimeInterval(-(10 * 60)),
            idleBeganAt: now.addingTimeInterval(-(12 * 60)),
            idleDetectedAt: now.addingTimeInterval(-(10 * 60)),
            pendingIdleStartedAt: now.addingTimeInterval(-(12 * 60)),
            pendingIdleEndedAt: now.addingTimeInterval(-(10 * 60)),
            pendingIdleReason: "inactivity"
        )

        let result = scheduler.resolveReturnedIdleState(
            state: state,
            settings: settings,
            eventDate: now
        )

        XCTAssertTrue(result.snapshot.isIdlePending)
        XCTAssertEqual(result.pendingIdleStartedAt, now.addingTimeInterval(-(12 * 60)))
        XCTAssertEqual(result.pendingIdleEndedAt, now)
        XCTAssertEqual(result.pendingIdleReason, "inactivity")
        XCTAssertEqual(result.accountableElapsedInterval, 0)
        XCTAssertNil(result.nextCheckInAt)
        XCTAssertEqual(result.idleResolvedAt, now)
    }

    func testOverdueRelaunchClampsElapsedToLastLaunchAt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now), calendar: fixedSchedulerCalendar())
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-(4 * 60 * 60)),
            nextCheckInAt: now.addingTimeInterval(-(2 * 60 * 60)),
            lastAppLaunchAt: now.addingTimeInterval(-(40 * 60))
        )

        let result = scheduler.updateState(state, settings: settings, eventDate: now)

        XCTAssertTrue(result.isPromptOverdue)
        XCTAssertEqual(result.accountableElapsedInterval, 40 * 60)
    }

    func testDelayedPromptAfterRelaunchUsesLastLaunchAsReferenceStart() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let delayedUntilAt = now.addingTimeInterval(-(10 * 60))
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: now), calendar: fixedSchedulerCalendar())
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: now.addingTimeInterval(-(3 * 60 * 60)),
            nextCheckInAt: delayedUntilAt,
            lastAppLaunchAt: now.addingTimeInterval(-(35 * 60)),
            delayedUntilAt: delayedUntilAt,
            delayedFromPromptAt: now.addingTimeInterval(-(50 * 60))
        )

        let result = scheduler.updateState(state, settings: settings, eventDate: now)

        XCTAssertTrue(result.isPromptOverdue)
        XCTAssertFalse(result.snapshot.isPromptDelayed)
        XCTAssertEqual(result.accountableElapsedInterval, 35 * 60)
    }

    func testSilenceExpiredAcrossMidnightSchedulesFromWakeTime() {
        var calendar = fixedSchedulerCalendar()
        calendar.timeZone = TimeZone(secondsFromGMT: 3600) ?? .gmt
        let midnight = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 16,
            hour: 0,
            minute: 0
        ))!
        let eventDate = midnight.addingTimeInterval(45 * 60)
        let scheduler = PollingScheduler(clock: FixedSchedulerClock(now: eventDate), calendar: calendar)
        let settings = AppSettingsRecord()
        let state = SchedulerStateRecord(
            lastCheckInAt: midnight.addingTimeInterval(-(30 * 60)),
            nextCheckInAt: midnight,
            lastAppLaunchAt: midnight.addingTimeInterval(-(5 * 60)),
            silencedAt: midnight.addingTimeInterval(-(2 * 60 * 60)),
            silenceEndsAt: midnight
        )

        let result = scheduler.updateState(state, settings: settings, eventDate: eventDate)

        XCTAssertFalse(result.snapshot.isSilenced)
        XCTAssertNil(result.silenceEndsAt)
        XCTAssertEqual(result.nextCheckInAt, eventDate.addingTimeInterval(25 * 60))
        XCTAssertEqual(result.accountableElapsedInterval, 25 * 60)
    }
}

private struct FixedSchedulerClock: SchedulerClock {
    let now: Date
}

private func fixedSchedulerCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}
