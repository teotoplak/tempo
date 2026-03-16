import Foundation
import XCTest
@testable import TempoApp

final class TimeAllocationEngineTests: XCTestCase {
    private let engine = TimeAllocationEngine()

    func testSameProjectAllocatesEntireIntervalToThatProject() {
        let summary = engine.summary(
            checkIns: [
                projectCheckIn("Client Work", id: projectID(1), at: date(2026, 3, 16, 9, 0, 0)),
                projectCheckIn("Client Work", id: projectID(1), at: date(2026, 3, 16, 9, 30, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.totalDuration, 30 * 60)
        XCTAssertEqual(summary.checkIns.count, 2)
        XCTAssertEqual(summary.allocatedIntervals.count, 1)
        XCTAssertEqual(summary.allocatedIntervals[0].bucket, .project(id: projectID(1), name: "Client Work"))
        XCTAssertEqual(summary.allocatedIntervals[0].rule, .sameBucket)
        XCTAssertEqual(summary.bucketSummaries.count, 1)
        XCTAssertEqual(summary.bucketSummaries[0].totalDuration, 30 * 60)
    }

    func testDifferentProjectsSplitIntervalInHalf() {
        let summary = engine.summary(
            checkIns: [
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 16, 9, 0, 0)),
                projectCheckIn("Project B", id: projectID(2), at: date(2026, 3, 16, 9, 30, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.totalDuration, 30 * 60)
        XCTAssertEqual(summary.allocatedIntervals.count, 2)
        XCTAssertEqual(summary.allocatedIntervals[0].bucket, .project(id: projectID(1), name: "Project A"))
        XCTAssertEqual(summary.allocatedIntervals[0].duration, 15 * 60)
        XCTAssertEqual(summary.allocatedIntervals[1].bucket, .project(id: projectID(2), name: "Project B"))
        XCTAssertEqual(summary.allocatedIntervals[1].duration, 15 * 60)
    }

    func testOddSecondSplitGivesExtraSecondToLaterCheckIn() {
        let summary = engine.summary(
            checkIns: [
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 16, 9, 0, 0)),
                projectCheckIn("Project B", id: projectID(2), at: date(2026, 3, 16, 9, 1, 1)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.allocatedIntervals.count, 2)
        XCTAssertEqual(summary.allocatedIntervals[0].duration, 30)
        XCTAssertEqual(summary.allocatedIntervals[1].duration, 31)
    }

    func testProjectThenIdleAllocatesWholeIntervalToIdle() {
        let summary = engine.summary(
            checkIns: [
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 16, 9, 0, 0)),
                idleCheckIn(.automaticThreshold, at: date(2026, 3, 16, 9, 10, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.allocatedIntervals.count, 1)
        XCTAssertEqual(summary.allocatedIntervals[0].bucket, .idle)
        XCTAssertEqual(summary.allocatedIntervals[0].duration, 10 * 60)
        XCTAssertEqual(summary.bucketSummaries.map(\.bucket), [.idle])
    }

    func testIdleThenProjectAllocatesWholeIntervalToIdle() {
        let summary = engine.summary(
            checkIns: [
                idleCheckIn(.doneForDay, at: date(2026, 3, 16, 9, 0, 0)),
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 16, 9, 30, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.totalDuration, 30 * 60)
        XCTAssertEqual(summary.allocatedIntervals.count, 1)
        XCTAssertEqual(summary.allocatedIntervals[0].bucket, .idle)
        XCTAssertEqual(summary.allocatedIntervals[0].rule, .idleDominates)
    }

    func testSameTimestampProducesNoAllocatedTime() {
        let summary = engine.summary(
            checkIns: [
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 16, 9, 0, 0)),
                projectCheckIn("Project B", id: projectID(2), at: date(2026, 3, 16, 9, 0, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertTrue(summary.allocatedIntervals.isEmpty)
        XCTAssertTrue(summary.bucketSummaries.isEmpty)
    }

    func testTrailingCheckInWithoutLaterCheckInAllocatesNothing() {
        let summary = engine.summary(
            checkIns: [
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 16, 9, 0, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.checkIns.count, 1)
        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertTrue(summary.allocatedIntervals.isEmpty)
    }

    func testCutoffPreventsIntervalsFromCrossingIntoNextDay() {
        let summary = engine.summary(
            checkIns: [
                idleCheckIn(.doneForDay, at: date(2026, 3, 16, 23, 0, 0)),
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 17, 8, 0, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.period.startDate, date(2026, 3, 16, 6, 0, 0))
        XCTAssertEqual(summary.period.endDate, date(2026, 3, 17, 6, 0, 0))
        XCTAssertEqual(summary.checkIns.count, 1)
        XCTAssertEqual(summary.totalDuration, 0)
        XCTAssertTrue(summary.allocatedIntervals.isEmpty)
    }

    func testFirstMorningCheckInAfterDoneForDayAllocatesZeroUntilNextCheckIn() {
        let summary = engine.summary(
            checkIns: [
                idleCheckIn(.doneForDay, at: date(2026, 3, 16, 23, 0, 0)),
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 17, 8, 0, 0)),
                projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 17, 8, 30, 0)),
            ],
            range: .day,
            referenceDate: date(2026, 3, 17, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.checkIns.count, 2)
        XCTAssertEqual(summary.totalDuration, 30 * 60)
        XCTAssertEqual(summary.allocatedIntervals.count, 1)
        XCTAssertEqual(summary.allocatedIntervals[0].startDate, date(2026, 3, 17, 8, 0, 0))
        XCTAssertEqual(summary.allocatedIntervals[0].endDate, date(2026, 3, 17, 8, 30, 0))
        XCTAssertEqual(summary.allocatedIntervals[0].bucket, .project(id: projectID(1), name: "Project A"))
    }

    func testUnansweredPromptIdleIsReturnedInTroubleshootingOutput() {
        let leading = idleCheckIn(.unansweredPrompt, at: date(2026, 3, 16, 10, 0, 0))
        let trailing = projectCheckIn("Project A", id: projectID(1), at: date(2026, 3, 16, 10, 20, 0))
        let summary = engine.summary(
            checkIns: [leading, trailing],
            range: .day,
            referenceDate: date(2026, 3, 16, 12, 0, 0),
            calendar: testCalendar,
            dayCutoffHour: 6
        )

        XCTAssertEqual(summary.checkIns, [leading, trailing])
        XCTAssertEqual(summary.allocatedIntervals.count, 1)
        XCTAssertEqual(summary.allocatedIntervals[0].bucket, .idle)
        XCTAssertEqual(summary.bucketSummaries[0].bucket, .idle)
    }

    private func projectCheckIn(_ name: String, id: UUID, at date: Date) -> TimeAllocationCheckIn {
        TimeAllocationCheckIn(
            id: UUID(),
            timestamp: date,
            kind: .project(id: id, name: name),
            source: "test"
        )
    }

    private func idleCheckIn(_ idleKind: TimeAllocationIdleKind, at date: Date) -> TimeAllocationCheckIn {
        TimeAllocationCheckIn(
            id: UUID(),
            timestamp: date,
            kind: .idle(kind: idleKind),
            source: "test"
        )
    }

    private func projectID(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
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
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}
