import Foundation

struct CheckInTriggerSettings: Equatable {
    var pollingIntervalMinutes: Int
    var idleThresholdMinutes: Int
    var analyticsDayCutoffHour: Int

    init(
        pollingIntervalMinutes: Int,
        idleThresholdMinutes: Int,
        analyticsDayCutoffHour: Int
    ) {
        self.pollingIntervalMinutes = pollingIntervalMinutes
        self.idleThresholdMinutes = idleThresholdMinutes
        self.analyticsDayCutoffHour = analyticsDayCutoffHour
    }

    init(_ settings: AppSettingsRecord) {
        self.init(
            pollingIntervalMinutes: settings.pollingIntervalMinutes,
            idleThresholdMinutes: settings.idleThresholdMinutes,
            analyticsDayCutoffHour: settings.analyticsDayCutoffHour
        )
    }
}

struct CheckInTriggerLatestCheckIn: Equatable {
    enum Kind: Equatable {
        case project
        case resume
        case idle(TimeAllocationIdleKind)
    }

    var timestamp: Date
    var kind: Kind
    var source: String
}

struct CheckInTriggerContext: Equatable {
    var settings: CheckInTriggerSettings
    var latestCheckIn: CheckInTriggerLatestCheckIn?
    var knownNextCheckInAt: Date?
    var runtimeState: DerivedRuntimeState
    var promptPresentedAt: Date?
}

enum CheckInTriggerSignal: Equatable {
    case recover(eventDate: Date, activityDate: Date?, allowScreenLockReturnFallback: Bool)
    case screenLocked(at: Date)
    case timerElapsed(at: Date)
}

enum CheckInTriggerEffect: Equatable {
    case persistIdleCheckIn(at: Date, idleKind: TimeAllocationIdleKind, source: String)
}

enum CheckInTriggerPrompt: Equatable {
    case hidden
    case freshCheckIn
    case returnedIdle(reason: String, startedAt: Date, endedAt: Date)
    case unansweredPrompt(startedAt: Date)

    var isPresented: Bool {
        switch self {
        case .hidden:
            return false
        case .freshCheckIn, .returnedIdle, .unansweredPrompt:
            return true
        }
    }
}

struct CheckInTriggerDecision: Equatable {
    var runtimeState: DerivedRuntimeState
    var prompt: CheckInTriggerPrompt
    var effects: [CheckInTriggerEffect] = []

    var shouldPresentPrompt: Bool {
        prompt.isPresented
    }

    var triggeredUnansweredPromptIdle: Bool {
        effects.contains { effect in
            guard case let .persistIdleCheckIn(_, idleKind, source) = effect else {
                return false
            }

            return idleKind == .unansweredPrompt && source == "unanswered-prompt"
        }
    }
}

struct CheckInTriggerEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func decide(
        signal: CheckInTriggerSignal,
        context: CheckInTriggerContext
    ) -> CheckInTriggerDecision {
        switch signal {
        case let .recover(eventDate, activityDate, allowScreenLockReturnFallback):
            let runtimeState = recoverRuntimeState(
                context: context,
                eventDate: eventDate,
                activityDate: activityDate,
                allowScreenLockReturnFallback: allowScreenLockReturnFallback
            )
            return CheckInTriggerDecision(
                runtimeState: runtimeState,
                prompt: prompt(for: runtimeState)
            )

        case let .screenLocked(eventDate):
            return decisionForScreenLock(context: context, eventDate: eventDate)

        case let .timerElapsed(eventDate):
            return decisionForTimerElapsed(context: context, eventDate: eventDate)
        }
    }

    private func decisionForScreenLock(
        context: CheckInTriggerContext,
        eventDate: Date
    ) -> CheckInTriggerDecision {
        if case .idle? = context.latestCheckIn?.kind {
            let runtimeState = recoverRuntimeState(
                context: context,
                eventDate: eventDate,
                activityDate: eventDate,
                allowScreenLockReturnFallback: false
            )
            return CheckInTriggerDecision(
                runtimeState: runtimeState,
                prompt: prompt(for: runtimeState)
            )
        }

        let runtimeState = DerivedRuntimeState(
            nextCheckInAt: nil,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            isSilenced: false,
            silenceEndsAt: nil,
            isIdlePending: true,
            pendingIdleStartedAt: eventDate,
            pendingIdleEndedAt: nil,
            pendingIdleReason: "screen-locked"
        )

        return CheckInTriggerDecision(
            runtimeState: runtimeState,
            prompt: .hidden,
            effects: [
                .persistIdleCheckIn(
                    at: eventDate,
                    idleKind: .automaticThreshold,
                    source: "screen-locked"
                )
            ]
        )
    }

    private func decisionForTimerElapsed(
        context: CheckInTriggerContext,
        eventDate: Date
    ) -> CheckInTriggerDecision {
        if
            let promptIdleMarkAt = promptIdleMarkAt(for: context),
            eventDate >= promptIdleMarkAt,
            context.latestCheckIn?.isIdle != true
        {
            let runtimeState = DerivedRuntimeState(
                nextCheckInAt: nil,
                isPromptOverdue: false,
                accountableElapsedInterval: 0,
                isSilenced: false,
                silenceEndsAt: nil,
                isIdlePending: true,
                pendingIdleStartedAt: promptIdleMarkAt,
                pendingIdleEndedAt: nil,
                pendingIdleReason: "unanswered-prompt"
            )

            return CheckInTriggerDecision(
                runtimeState: runtimeState,
                prompt: .unansweredPrompt(startedAt: promptIdleMarkAt),
                effects: [
                    .persistIdleCheckIn(
                        at: promptIdleMarkAt,
                        idleKind: .unansweredPrompt,
                        source: "unanswered-prompt"
                    )
                ]
            )
        }

        let runtimeState = recoverRuntimeState(
            context: context,
            eventDate: eventDate,
            activityDate: nil,
            allowScreenLockReturnFallback: false
        )
        return CheckInTriggerDecision(
            runtimeState: runtimeState,
            prompt: prompt(for: runtimeState)
        )
    }

    private func recoverRuntimeState(
        context: CheckInTriggerContext,
        eventDate: Date,
        activityDate: Date?,
        allowScreenLockReturnFallback: Bool
    ) -> DerivedRuntimeState {
        let pollingInterval = TimeInterval(context.settings.pollingIntervalMinutes * 60)

        guard let latestCheckIn = context.latestCheckIn else {
            if let scheduledCheckInAt = context.knownNextCheckInAt {
                let isPromptOverdue = eventDate >= scheduledCheckInAt
                let referenceStart = scheduledCheckInAt.addingTimeInterval(-pollingInterval)
                let accountableElapsedInterval = isPromptOverdue
                    ? max(eventDate.timeIntervalSince(referenceStart), pollingInterval)
                    : pollingInterval

                return DerivedRuntimeState(
                    nextCheckInAt: scheduledCheckInAt,
                    isPromptOverdue: isPromptOverdue,
                    accountableElapsedInterval: accountableElapsedInterval,
                    isSilenced: false,
                    silenceEndsAt: nil,
                    isIdlePending: false,
                    pendingIdleStartedAt: nil,
                    pendingIdleEndedAt: nil,
                    pendingIdleReason: nil
                )
            }

            return DerivedRuntimeState(
                nextCheckInAt: eventDate.addingTimeInterval(pollingInterval),
                isPromptOverdue: false,
                accountableElapsedInterval: pollingInterval,
                isSilenced: false,
                silenceEndsAt: nil,
                isIdlePending: false,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil
            )
        }

        switch latestCheckIn.kind {
        case .project, .resume:
            let nextCheckInAt = latestCheckIn.timestamp.addingTimeInterval(pollingInterval)
            let isPromptOverdue = eventDate >= nextCheckInAt
            let accountableElapsedInterval = isPromptOverdue
                ? max(eventDate.timeIntervalSince(latestCheckIn.timestamp), pollingInterval)
                : pollingInterval

            return DerivedRuntimeState(
                nextCheckInAt: nextCheckInAt,
                isPromptOverdue: isPromptOverdue,
                accountableElapsedInterval: accountableElapsedInterval,
                isSilenced: false,
                silenceEndsAt: nil,
                isIdlePending: false,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil
            )

        case let .idle(idleKind):
            if idleKind == .doneForDay {
                let silenceEndsAt = nextDayCutoff(
                    after: latestCheckIn.timestamp,
                    dayCutoffHour: context.settings.analyticsDayCutoffHour
                )
                if eventDate < silenceEndsAt {
                    return DerivedRuntimeState(
                        nextCheckInAt: nil,
                        isPromptOverdue: false,
                        accountableElapsedInterval: 0,
                        isSilenced: true,
                        silenceEndsAt: silenceEndsAt,
                        isIdlePending: false,
                        pendingIdleStartedAt: nil,
                        pendingIdleEndedAt: nil,
                        pendingIdleReason: nil
                    )
                }

                let nextCheckInAt = silenceEndsAt.addingTimeInterval(pollingInterval)
                let isPromptOverdue = eventDate >= nextCheckInAt
                let accountableElapsedInterval = isPromptOverdue
                    ? max(eventDate.timeIntervalSince(silenceEndsAt), pollingInterval)
                    : pollingInterval

                return DerivedRuntimeState(
                    nextCheckInAt: nextCheckInAt,
                    isPromptOverdue: isPromptOverdue,
                    accountableElapsedInterval: accountableElapsedInterval,
                    isSilenced: false,
                    silenceEndsAt: nil,
                    isIdlePending: false,
                    pendingIdleStartedAt: nil,
                    pendingIdleEndedAt: nil,
                    pendingIdleReason: nil
                )
            }

            let sampledActivityDate = activityDate ?? eventDate
            let resolvedActivityDate: Date
            if
                allowScreenLockReturnFallback,
                latestCheckIn.source == "screen-locked",
                sampledActivityDate <= latestCheckIn.timestamp
            {
                resolvedActivityDate = eventDate
            } else {
                resolvedActivityDate = sampledActivityDate
            }

            let pendingIdleEndedAt = resolvedActivityDate > latestCheckIn.timestamp
                ? resolvedActivityDate
                : nil

            return DerivedRuntimeState(
                nextCheckInAt: nil,
                isPromptOverdue: false,
                accountableElapsedInterval: 0,
                isSilenced: false,
                silenceEndsAt: nil,
                isIdlePending: true,
                pendingIdleStartedAt: latestCheckIn.timestamp,
                pendingIdleEndedAt: pendingIdleEndedAt,
                pendingIdleReason: latestCheckIn.source
            )
        }
    }

    private func prompt(for runtimeState: DerivedRuntimeState) -> CheckInTriggerPrompt {
        if
            runtimeState.isIdlePending,
            let startedAt = runtimeState.pendingIdleStartedAt,
            let endedAt = runtimeState.pendingIdleEndedAt,
            let reason = runtimeState.pendingIdleReason
        {
            return .returnedIdle(reason: reason, startedAt: startedAt, endedAt: endedAt)
        }

        if runtimeState.isIdlePending, let startedAt = runtimeState.pendingIdleStartedAt {
            if runtimeState.pendingIdleReason == "unanswered-prompt" {
                return .unansweredPrompt(startedAt: startedAt)
            }

            return .hidden
        }

        if runtimeState.isPromptOverdue {
            return .freshCheckIn
        }

        return .hidden
    }

    private func promptIdleMarkAt(for context: CheckInTriggerContext) -> Date? {
        guard
            context.runtimeState.isPromptOverdue,
            !context.runtimeState.isIdlePending,
            let promptPresentedAt = context.promptPresentedAt
        else {
            return nil
        }

        return promptPresentedAt.addingTimeInterval(
            TimeInterval(context.settings.idleThresholdMinutes * 60)
        )
    }

    private func nextDayCutoff(after date: Date, dayCutoffHour: Int) -> Date {
        let shiftedDate = calendar.date(byAdding: .hour, value: -dayCutoffHour, to: date) ?? date
        let shiftedStartOfDay = calendar.startOfDay(for: shiftedDate)
        let nextShiftedDay = calendar.date(byAdding: .day, value: 1, to: shiftedStartOfDay) ?? shiftedStartOfDay
        return calendar.date(byAdding: .hour, value: dayCutoffHour, to: nextShiftedDay) ?? nextShiftedDay
    }
}

private extension CheckInTriggerLatestCheckIn {
    var isIdle: Bool {
        if case .idle = kind {
            return true
        }

        return false
    }
}
