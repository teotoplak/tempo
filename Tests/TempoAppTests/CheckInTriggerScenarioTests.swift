import Foundation
import XCTest
@testable import TempoApp

final class CheckInTriggerScenarioTests: XCTestCase {
    func test_relaunchBeforeIntervalEnds_keepsFutureCheckInScheduled() {
        let scenario = CheckInTriggerScenario()
            .givenProjectCheckIn(at: time(1, 0))
            .whenAppRelaunches(at: time(1, 10))

        XCTAssertFalse(scenario.outcome.showsPrompt)
        XCTAssertEqual(scenario.outcome.prompt, .hidden)
        XCTAssertEqual(scenario.outcome.state.nextCheckInAt, time(1, 25))
        XCTAssertFalse(scenario.outcome.state.isPromptOverdue)
    }

    func test_relaunchAfterIntervalEnds_showsFreshCheckInPrompt() {
        let scenario = CheckInTriggerScenario()
            .givenProjectCheckIn(at: time(1, 0))
            .whenAppRelaunches(at: time(1, 25))

        XCTAssertTrue(scenario.outcome.showsPrompt)
        XCTAssertEqual(scenario.outcome.prompt, .freshCheckIn)
        XCTAssertEqual(scenario.outcome.state.nextCheckInAt, time(1, 25))
        XCTAssertTrue(scenario.outcome.state.isPromptOverdue)
        XCTAssertEqual(scenario.outcome.state.accountableElapsedInterval, 25 * 60)
    }

    func test_timerElapsedAfterPollingInterval_showsFreshCheckInPrompt() {
        let scenario = CheckInTriggerScenario()
            .givenProjectCheckIn(at: time(1, 0))
            .whenTimerElapses(at: time(1, 25))

        XCTAssertTrue(scenario.outcome.showsPrompt)
        XCTAssertEqual(scenario.outcome.prompt, .freshCheckIn)
        XCTAssertEqual(scenario.outcome.promptPresentedAt, time(1, 25))
        XCTAssertEqual(scenario.outcome.state.accountableElapsedInterval, 25 * 60)
    }

    func test_screenUnlockBeforeIdleThreshold_promptsToResolveLockedTime() {
        let scenario = CheckInTriggerScenario()
            .withIdleThreshold(minutes: 5)
            .givenProjectCheckIn(at: time(1, 0))
            .whenScreenLocks(at: time(1, 10))
            .whenScreenUnlocks(at: time(1, 13))

        XCTAssertTrue(scenario.outcome.showsPrompt)
        XCTAssertEqual(
            scenario.outcome.prompt,
            .returnedIdle(
                reason: "screen-locked",
                startedAt: time(1, 10),
                endedAt: time(1, 13)
            )
        )
        XCTAssertTrue(scenario.outcome.state.isIdlePending)
        XCTAssertNil(scenario.outcome.state.nextCheckInAt)
    }

    func test_screenUnlockAtOrAfterIdleThreshold_promptsToResolveLockedTime() {
        let scenario = CheckInTriggerScenario()
            .withIdleThreshold(minutes: 5)
            .givenProjectCheckIn(at: time(1, 0))
            .whenScreenLocks(at: time(1, 10))
            .whenScreenUnlocks(at: time(1, 15))

        XCTAssertTrue(scenario.outcome.showsPrompt)
        XCTAssertEqual(
            scenario.outcome.prompt,
            .returnedIdle(
                reason: "screen-locked",
                startedAt: time(1, 10),
                endedAt: time(1, 15)
            )
        )
        XCTAssertTrue(scenario.outcome.state.isIdlePending)
        XCTAssertNil(scenario.outcome.state.nextCheckInAt)
    }

    func test_screenUnlockUsesFallbackWhenActivitySampleLooksStale() {
        let scenario = CheckInTriggerScenario()
            .givenProjectCheckIn(at: time(1, 0))
            .whenScreenLocks(at: time(1, 10))
            .whenScreenUnlocks(
                at: time(1, 15),
                sampledActivityDate: time(1, 10),
                allowScreenLockReturnFallback: true
            )

        XCTAssertEqual(
            scenario.outcome.prompt,
            .returnedIdle(
                reason: "screen-locked",
                startedAt: time(1, 10),
                endedAt: time(1, 15)
            )
        )
    }

    func test_doneForDayBeforeCutoff_keepsPromptsHidden() {
        let scenario = CheckInTriggerScenario()
            .givenDoneForDay(at: time(18, 0))
            .whenAppRelaunches(at: time(23, 0))

        XCTAssertFalse(scenario.outcome.showsPrompt)
        XCTAssertTrue(scenario.outcome.state.isSilenced)
        XCTAssertEqual(scenario.outcome.state.silenceEndsAt, time(6, 0, dayOffset: 1))
    }

    func test_doneForDayAfterCutoff_becomesFreshCheckInPrompt() {
        let scenario = CheckInTriggerScenario()
            .givenDoneForDay(at: time(18, 0))
            .whenAppRelaunches(at: time(9, 0, dayOffset: 1))

        XCTAssertTrue(scenario.outcome.showsPrompt)
        XCTAssertEqual(scenario.outcome.prompt, .freshCheckIn)
        XCTAssertFalse(scenario.outcome.state.isSilenced)
        XCTAssertEqual(scenario.outcome.state.nextCheckInAt, time(6, 25, dayOffset: 1))
        XCTAssertTrue(scenario.outcome.state.isPromptOverdue)
    }

    func test_overduePromptThatGoesUnanswered_marksUnansweredPromptIdle() {
        let scenario = CheckInTriggerScenario()
            .givenProjectCheckIn(at: time(1, 0))
            .whenTimerElapses(at: time(1, 25))
            .whenTimerElapses(at: time(1, 30))

        XCTAssertTrue(scenario.outcome.showsPrompt)
        XCTAssertEqual(
            scenario.outcome.prompt,
            .unansweredPrompt(startedAt: time(1, 30))
        )
        XCTAssertTrue(scenario.outcome.state.isIdlePending)
        XCTAssertEqual(scenario.outcome.state.pendingIdleReason, "unanswered-prompt")
        XCTAssertEqual(
            scenario.outcome.effects,
            [.persistIdleCheckIn(at: time(1, 30), idleKind: .unansweredPrompt, source: "unanswered-prompt")]
        )
    }
}

private struct CheckInTriggerScenario {
    private let engine: CheckInTriggerEngine
    private let settings: CheckInTriggerSettings
    private var context: CheckInTriggerContext
    private var lastDecision = CheckInTriggerDecision(
        runtimeState: DerivedRuntimeState(
            nextCheckInAt: nil,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            isSilenced: false,
            silenceEndsAt: nil,
            isIdlePending: false,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil
        ),
        prompt: .hidden
    )

    init(
        pollingIntervalMinutes: Int = 25,
        idleThresholdMinutes: Int = 5,
        analyticsDayCutoffHour: Int = 6
    ) {
        let initialRuntimeState = DerivedRuntimeState(
            nextCheckInAt: nil,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            isSilenced: false,
            silenceEndsAt: nil,
            isIdlePending: false,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil
        )
        let settings = CheckInTriggerSettings(
            pollingIntervalMinutes: pollingIntervalMinutes,
            idleThresholdMinutes: idleThresholdMinutes,
            analyticsDayCutoffHour: analyticsDayCutoffHour
        )
        self.engine = CheckInTriggerEngine(calendar: fixedTriggerScenarioCalendar())
        self.settings = settings
        self.context = CheckInTriggerContext(
            settings: settings,
            latestCheckIn: nil,
            knownNextCheckInAt: nil,
            runtimeState: initialRuntimeState,
            promptPresentedAt: nil
        )
        self.lastDecision = CheckInTriggerDecision(runtimeState: initialRuntimeState, prompt: .hidden)
    }

    var outcome: CheckInTriggerScenarioOutcome {
        CheckInTriggerScenarioOutcome(
            prompt: lastDecision.prompt,
            state: context.runtimeState,
            effects: lastDecision.effects,
            promptPresentedAt: context.promptPresentedAt
        )
    }

    func givenProjectCheckIn(at timestamp: Date) -> Self {
        var scenario = self
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        scenario.context.latestCheckIn = CheckInTriggerLatestCheckIn(
            timestamp: timestamp,
            kind: .project,
            source: "check-in"
        )
        scenario.context.runtimeState = DerivedRuntimeState(
            nextCheckInAt: timestamp.addingTimeInterval(pollingInterval),
            isPromptOverdue: false,
            accountableElapsedInterval: pollingInterval,
            isSilenced: false,
            silenceEndsAt: nil,
            isIdlePending: false,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil
        )
        scenario.context.knownNextCheckInAt = scenario.context.runtimeState.nextCheckInAt
        scenario.context.promptPresentedAt = nil
        scenario.lastDecision = CheckInTriggerDecision(runtimeState: scenario.context.runtimeState, prompt: .hidden)
        return scenario
    }

    func withIdleThreshold(minutes: Int) -> Self {
        var scenario = self
        scenario.context.settings.idleThresholdMinutes = minutes
        return scenario
    }

    func givenDoneForDay(at timestamp: Date) -> Self {
        var scenario = self
        scenario.context.latestCheckIn = CheckInTriggerLatestCheckIn(
            timestamp: timestamp,
            kind: .idle(.doneForDay),
            source: "done-for-day"
        )
        scenario.context.runtimeState = DerivedRuntimeState(
            nextCheckInAt: nil,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            isSilenced: true,
            silenceEndsAt: nil,
            isIdlePending: false,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil
        )
        scenario.context.knownNextCheckInAt = nil
        scenario.context.promptPresentedAt = nil
        scenario.lastDecision = CheckInTriggerDecision(runtimeState: scenario.context.runtimeState, prompt: .hidden)
        return scenario
    }

    func whenAppRelaunches(at timestamp: Date) -> Self {
        applying(
            .recover(
                eventDate: timestamp,
                activityDate: nil,
                allowScreenLockReturnFallback: true
            ),
            eventDate: timestamp
        )
    }

    func whenScreenLocks(at timestamp: Date) -> Self {
        applying(.screenLocked(at: timestamp), eventDate: timestamp)
    }

    func whenScreenUnlocks(
        at timestamp: Date,
        sampledActivityDate: Date? = nil,
        allowScreenLockReturnFallback: Bool = true
    ) -> Self {
        applying(
            .recover(
                eventDate: timestamp,
                activityDate: sampledActivityDate ?? timestamp,
                allowScreenLockReturnFallback: allowScreenLockReturnFallback
            ),
            eventDate: timestamp
        )
    }

    func whenTimerElapses(at timestamp: Date) -> Self {
        applying(.timerElapsed(at: timestamp), eventDate: timestamp)
    }

    private func applying(
        _ signal: CheckInTriggerSignal,
        eventDate: Date
    ) -> Self {
        var scenario = self
        let decision = scenario.engine.decide(signal: signal, context: scenario.context)
        scenario.lastDecision = decision
        scenario.applyEffects(decision.effects)
        scenario.context.runtimeState = decision.runtimeState
        scenario.context.knownNextCheckInAt = decision.runtimeState.nextCheckInAt
        if decision.runtimeState.isPromptOverdue, decision.prompt == .freshCheckIn {
            scenario.context.promptPresentedAt = scenario.context.promptPresentedAt ?? eventDate
        } else if !decision.runtimeState.isPromptOverdue {
            scenario.context.promptPresentedAt = nil
        }
        return scenario
    }

    private mutating func applyEffects(_ effects: [CheckInTriggerEffect]) {
        for effect in effects {
            switch effect {
            case let .persistIdleCheckIn(timestamp, idleKind, source):
                context.latestCheckIn = CheckInTriggerLatestCheckIn(
                    timestamp: timestamp,
                    kind: .idle(idleKind),
                    source: source
                )
            }
        }
    }
}

private struct CheckInTriggerScenarioOutcome {
    var prompt: CheckInTriggerPrompt
    var state: DerivedRuntimeState
    var effects: [CheckInTriggerEffect]
    var promptPresentedAt: Date?

    var showsPrompt: Bool {
        prompt.isPresented
    }
}

private func fixedTriggerScenarioCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

private func time(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
    let calendar = fixedTriggerScenarioCalendar()
    let baseDate = calendar.date(
        from: DateComponents(
            timeZone: .gmt,
            year: 2026,
            month: 3,
            day: 30 + dayOffset,
            hour: hour,
            minute: minute
        )
    )

    return baseDate!
}
