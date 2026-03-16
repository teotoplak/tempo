import Foundation

struct PollingSchedulerSnapshot: Equatable {
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
    var accountableWorkEndAt: Date?
    var isSilenced: Bool
    var silenceEndsAt: Date?
    var isIdlePending: Bool
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
}

struct PollingSchedulerResult {
    var snapshot: PollingSchedulerSnapshot
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
    var accountableWorkEndAt: Date?
    var lastCheckInAt: Date?
    var idleBeganAt: Date?
    var idleDetectedAt: Date?
    var idleResolvedAt: Date?
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
    var silenceEndsAt: Date?
}

final class PollingScheduler {
    private let clock: any SchedulerClock
    private let calendar: Calendar

    init(clock: any SchedulerClock, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    func snapshot(
        for state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date? = nil
    ) -> PollingSchedulerSnapshot {
        let result = updateState(state, settings: settings, eventDate: eventDate ?? clock.now)
        return result.snapshot
    }

    func updateState(
        _ state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date
    ) -> PollingSchedulerResult {
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)

        if let pendingIdleStartedAt = state.pendingIdleStartedAt {
            return makeResult(
                nextCheckInAt: nil,
                isPromptOverdue: false,
                accountableElapsedInterval: 0,
                accountableWorkEndAt: pendingIdleStartedAt,
                lastCheckInAt: state.lastCheckInAt,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: pendingIdleStartedAt,
                pendingIdleEndedAt: state.pendingIdleEndedAt,
                pendingIdleReason: state.pendingIdleReason,
                silenceEndsAt: nil
            )
        }

        if let silenceEndsAt = state.silenceEndsAt {
            if eventDate < silenceEndsAt {
                return makeResult(
                    nextCheckInAt: silenceEndsAt,
                    isPromptOverdue: false,
                    accountableElapsedInterval: 0,
                    accountableWorkEndAt: eventDate,
                    lastCheckInAt: state.lastCheckInAt,
                    idleBeganAt: state.idleBeganAt,
                    idleDetectedAt: state.idleDetectedAt,
                    idleResolvedAt: state.idleResolvedAt,
                    pendingIdleStartedAt: nil,
                    pendingIdleEndedAt: nil,
                    pendingIdleReason: nil,
                    silenceEndsAt: silenceEndsAt
                )
            }

            let resumedAt = max(eventDate, silenceEndsAt)
            let nextCheckInAt = resumedAt.addingTimeInterval(pollingInterval)
            return makeResult(
                nextCheckInAt: nextCheckInAt,
                isPromptOverdue: false,
                accountableElapsedInterval: pollingInterval,
                accountableWorkEndAt: nextCheckInAt,
                lastCheckInAt: state.lastCheckInAt,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil,
                silenceEndsAt: nil
            )
        }

        guard let existingNextCheckInAt = state.nextCheckInAt else {
            let nextCheckInAt = eventDate.addingTimeInterval(pollingInterval)
            return makeResult(
                nextCheckInAt: nextCheckInAt,
                isPromptOverdue: false,
                accountableElapsedInterval: pollingInterval,
                accountableWorkEndAt: nextCheckInAt,
                lastCheckInAt: state.lastCheckInAt,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil,
                silenceEndsAt: nil
            )
        }

        if existingNextCheckInAt <= eventDate {
            let referenceStart = effectiveElapsedStart(
                for: state,
                scheduledCheckInAt: existingNextCheckInAt,
                pollingInterval: pollingInterval
            )
            let elapsedInterval = max(eventDate.timeIntervalSince(referenceStart), pollingInterval)
            return makeResult(
                nextCheckInAt: existingNextCheckInAt,
                isPromptOverdue: true,
                accountableElapsedInterval: elapsedInterval,
                accountableWorkEndAt: eventDate,
                lastCheckInAt: state.lastCheckInAt,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil,
                silenceEndsAt: nil
            )
        }

        let referenceStart = effectiveElapsedStart(
            for: state,
            scheduledCheckInAt: existingNextCheckInAt,
            pollingInterval: pollingInterval
        )
        let elapsedInterval = max(existingNextCheckInAt.timeIntervalSince(referenceStart), pollingInterval)
        return makeResult(
            nextCheckInAt: existingNextCheckInAt,
            isPromptOverdue: false,
            accountableElapsedInterval: elapsedInterval,
            accountableWorkEndAt: existingNextCheckInAt,
            lastCheckInAt: state.lastCheckInAt,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            silenceEndsAt: nil
        )
    }

    func silenceUntilEndOfDay(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date
    ) -> PollingSchedulerResult {
        let silenceEndsAt = nextDayCutoff(after: eventDate, dayCutoffHour: settings.analyticsDayCutoffHour)

        return makeResult(
            nextCheckInAt: silenceEndsAt,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            accountableWorkEndAt: eventDate,
            lastCheckInAt: state.lastCheckInAt,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            silenceEndsAt: silenceEndsAt
        )
    }

    func endSilence(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date
    ) -> PollingSchedulerResult {
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        let nextCheckInAt = eventDate.addingTimeInterval(pollingInterval)

        return makeResult(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: false,
            accountableElapsedInterval: pollingInterval,
            accountableWorkEndAt: nextCheckInAt,
            lastCheckInAt: state.lastCheckInAt,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            silenceEndsAt: nil
        )
    }

    func completeCheckIn(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        completionDate: Date
    ) -> PollingSchedulerResult {
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        let nextCheckInAt = completionDate.addingTimeInterval(pollingInterval)

        return makeResult(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: false,
            accountableElapsedInterval: pollingInterval,
            accountableWorkEndAt: nextCheckInAt,
            lastCheckInAt: completionDate,
            idleBeganAt: nil,
            idleDetectedAt: nil,
            idleResolvedAt: nil,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            silenceEndsAt: nil
        )
    }

    func rescheduleFromSettingsChange(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date
    ) -> PollingSchedulerResult {
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        let nextCheckInAt = eventDate.addingTimeInterval(pollingInterval)

        return makeResult(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: false,
            accountableElapsedInterval: pollingInterval,
            accountableWorkEndAt: nextCheckInAt,
            lastCheckInAt: state.lastCheckInAt,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            silenceEndsAt: nil
        )
    }

    func beginIdleInterval(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date,
        reason: String
    ) -> PollingSchedulerResult {
        let idleStart = state.pendingIdleStartedAt ?? eventDate
        let idleEnd = max(state.pendingIdleEndedAt ?? eventDate, eventDate)

        return makeResult(
            nextCheckInAt: nil,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            accountableWorkEndAt: idleStart,
            lastCheckInAt: state.lastCheckInAt,
            idleBeganAt: state.idleBeganAt ?? idleStart,
            idleDetectedAt: eventDate,
            idleResolvedAt: nil,
            pendingIdleStartedAt: idleStart,
            pendingIdleEndedAt: idleEnd,
            pendingIdleReason: reason,
            silenceEndsAt: nil
        )
    }

    func resolveReturnedIdleState(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date
    ) -> PollingSchedulerResult {
        guard let pendingIdleStartedAt = state.pendingIdleStartedAt else {
            return updateState(state, settings: settings, eventDate: eventDate)
        }

        let pendingIdleEndedAt = max(state.pendingIdleEndedAt ?? pendingIdleStartedAt, eventDate)

        return makeResult(
            nextCheckInAt: nil,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            accountableWorkEndAt: pendingIdleStartedAt,
            lastCheckInAt: state.lastCheckInAt,
            idleBeganAt: state.idleBeganAt ?? pendingIdleStartedAt,
            idleDetectedAt: state.idleDetectedAt ?? pendingIdleStartedAt,
            idleResolvedAt: eventDate,
            pendingIdleStartedAt: pendingIdleStartedAt,
            pendingIdleEndedAt: pendingIdleEndedAt,
            pendingIdleReason: state.pendingIdleReason,
            silenceEndsAt: nil
        )
    }

    private func effectiveElapsedStart(
        for state: SchedulerStateRecord,
        scheduledCheckInAt: Date,
        pollingInterval: TimeInterval
    ) -> Date {
        var candidateStarts = [scheduledCheckInAt.addingTimeInterval(-pollingInterval)]

        if let lastCheckInAt = state.lastCheckInAt {
            candidateStarts.append(lastCheckInAt)
        }

        return candidateStarts.max() ?? scheduledCheckInAt.addingTimeInterval(-pollingInterval)
    }

    private func nextDayCutoff(after date: Date, dayCutoffHour: Int) -> Date {
        let shiftedDate = calendar.date(byAdding: .hour, value: -dayCutoffHour, to: date) ?? date
        let shiftedStartOfDay = calendar.startOfDay(for: shiftedDate)
        let nextShiftedDay = calendar.date(byAdding: .day, value: 1, to: shiftedStartOfDay) ?? shiftedStartOfDay
        return calendar.date(byAdding: .hour, value: dayCutoffHour, to: nextShiftedDay) ?? nextShiftedDay
    }

    private func makeResult(
        nextCheckInAt: Date?,
        isPromptOverdue: Bool,
        accountableElapsedInterval: TimeInterval,
        accountableWorkEndAt: Date?,
        lastCheckInAt: Date?,
        idleBeganAt: Date?,
        idleDetectedAt: Date?,
        idleResolvedAt: Date?,
        pendingIdleStartedAt: Date?,
        pendingIdleEndedAt: Date?,
        pendingIdleReason: String?,
        silenceEndsAt: Date?
    ) -> PollingSchedulerResult {
        let snapshot = PollingSchedulerSnapshot(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval,
            accountableWorkEndAt: accountableWorkEndAt,
            isSilenced: silenceEndsAt != nil,
            silenceEndsAt: silenceEndsAt,
            isIdlePending: pendingIdleStartedAt != nil,
            pendingIdleStartedAt: pendingIdleStartedAt,
            pendingIdleEndedAt: pendingIdleEndedAt,
            pendingIdleReason: pendingIdleReason
        )

        return PollingSchedulerResult(
            snapshot: snapshot,
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval,
            accountableWorkEndAt: accountableWorkEndAt,
            lastCheckInAt: lastCheckInAt,
            idleBeganAt: idleBeganAt,
            idleDetectedAt: idleDetectedAt,
            idleResolvedAt: idleResolvedAt,
            pendingIdleStartedAt: pendingIdleStartedAt,
            pendingIdleEndedAt: pendingIdleEndedAt,
            pendingIdleReason: pendingIdleReason,
            silenceEndsAt: silenceEndsAt
        )
    }
}
