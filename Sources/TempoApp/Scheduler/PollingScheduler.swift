import Foundation

struct PollingSchedulerSnapshot: Equatable {
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
    var accountableWorkEndAt: Date?
    var isPromptDelayed: Bool
    var delayedUntilAt: Date?
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
    var lastAppLaunchAt: Date
    var idleBeganAt: Date?
    var idleDetectedAt: Date?
    var idleResolvedAt: Date?
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
    var delayedUntilAt: Date?
    var delayedFromPromptAt: Date?
    var silencedAt: Date?
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
                lastAppLaunchAt: eventDate,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: pendingIdleStartedAt,
                pendingIdleEndedAt: state.pendingIdleEndedAt,
                pendingIdleReason: state.pendingIdleReason,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
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
                    lastAppLaunchAt: eventDate,
                    idleBeganAt: state.idleBeganAt,
                    idleDetectedAt: state.idleDetectedAt,
                    idleResolvedAt: state.idleResolvedAt,
                    pendingIdleStartedAt: nil,
                    pendingIdleEndedAt: nil,
                    pendingIdleReason: nil,
                    delayedUntilAt: nil,
                    delayedFromPromptAt: nil,
                    silencedAt: state.silencedAt,
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
                lastAppLaunchAt: eventDate,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
                silenceEndsAt: nil
            )
        }

        if let delayedUntilAt = state.delayedUntilAt {
            let referenceStart = effectiveElapsedStart(
                for: state,
                scheduledCheckInAt: delayedUntilAt,
                pollingInterval: pollingInterval
            )

            if eventDate < delayedUntilAt {
                return makeResult(
                    nextCheckInAt: delayedUntilAt,
                    isPromptOverdue: false,
                    accountableElapsedInterval: max(eventDate.timeIntervalSince(referenceStart), pollingInterval),
                    accountableWorkEndAt: eventDate,
                    lastCheckInAt: state.lastCheckInAt,
                    lastAppLaunchAt: eventDate,
                    idleBeganAt: state.idleBeganAt,
                    idleDetectedAt: state.idleDetectedAt,
                    idleResolvedAt: state.idleResolvedAt,
                    pendingIdleStartedAt: nil,
                    pendingIdleEndedAt: nil,
                    pendingIdleReason: nil,
                    delayedUntilAt: delayedUntilAt,
                    delayedFromPromptAt: state.delayedFromPromptAt,
                    silencedAt: nil,
                    silenceEndsAt: nil
                )
            }

            return makeResult(
                nextCheckInAt: delayedUntilAt,
                isPromptOverdue: true,
                accountableElapsedInterval: max(eventDate.timeIntervalSince(referenceStart), pollingInterval),
                accountableWorkEndAt: eventDate,
                lastCheckInAt: state.lastCheckInAt,
                lastAppLaunchAt: eventDate,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
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
                lastAppLaunchAt: eventDate,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
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
                lastAppLaunchAt: eventDate,
                idleBeganAt: state.idleBeganAt,
                idleDetectedAt: state.idleDetectedAt,
                idleResolvedAt: state.idleResolvedAt,
                pendingIdleStartedAt: nil,
                pendingIdleEndedAt: nil,
                pendingIdleReason: nil,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
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
            lastAppLaunchAt: eventDate,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            delayedUntilAt: nil,
            delayedFromPromptAt: nil,
            silencedAt: nil,
            silenceEndsAt: nil
        )
    }

    func delayCheckIn(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        delayMinutes: Int,
        delayDate: Date
    ) -> PollingSchedulerResult {
        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        let delayDuration = TimeInterval(delayMinutes * 60)
        let delayedUntilAt = delayDate.addingTimeInterval(delayDuration)
        let promptReference = state.delayedFromPromptAt ?? state.nextCheckInAt ?? delayDate
        let referenceStart = effectiveElapsedStart(
            for: state,
            scheduledCheckInAt: promptReference,
            pollingInterval: pollingInterval
        )

        return makeResult(
            nextCheckInAt: delayedUntilAt,
            isPromptOverdue: false,
            accountableElapsedInterval: max(delayDate.timeIntervalSince(referenceStart), pollingInterval),
            accountableWorkEndAt: delayDate,
            lastCheckInAt: state.lastCheckInAt,
            lastAppLaunchAt: delayDate,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            delayedUntilAt: delayedUntilAt,
            delayedFromPromptAt: promptReference,
            silencedAt: nil,
            silenceEndsAt: nil
        )
    }

    func silenceUntilEndOfDay(
        state: SchedulerStateRecord,
        settings: AppSettingsRecord,
        eventDate: Date
    ) -> PollingSchedulerResult {
        let silenceEndsAt = nextLocalMidnight(after: eventDate)

        return makeResult(
            nextCheckInAt: silenceEndsAt,
            isPromptOverdue: false,
            accountableElapsedInterval: 0,
            accountableWorkEndAt: eventDate,
            lastCheckInAt: state.lastCheckInAt,
            lastAppLaunchAt: eventDate,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            delayedUntilAt: nil,
            delayedFromPromptAt: nil,
            silencedAt: eventDate,
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
            lastAppLaunchAt: eventDate,
            idleBeganAt: state.idleBeganAt,
            idleDetectedAt: state.idleDetectedAt,
            idleResolvedAt: state.idleResolvedAt,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            delayedUntilAt: nil,
            delayedFromPromptAt: nil,
            silencedAt: nil,
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
            lastAppLaunchAt: completionDate,
            idleBeganAt: nil,
            idleDetectedAt: nil,
            idleResolvedAt: nil,
            pendingIdleStartedAt: nil,
            pendingIdleEndedAt: nil,
            pendingIdleReason: nil,
            delayedUntilAt: nil,
            delayedFromPromptAt: nil,
            silencedAt: nil,
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
            lastAppLaunchAt: eventDate,
            idleBeganAt: state.idleBeganAt ?? idleStart,
            idleDetectedAt: eventDate,
            idleResolvedAt: nil,
            pendingIdleStartedAt: idleStart,
            pendingIdleEndedAt: idleEnd,
            pendingIdleReason: reason,
            delayedUntilAt: nil,
            delayedFromPromptAt: nil,
            silencedAt: nil,
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
            lastAppLaunchAt: eventDate,
            idleBeganAt: state.idleBeganAt ?? pendingIdleStartedAt,
            idleDetectedAt: state.idleDetectedAt ?? pendingIdleStartedAt,
            idleResolvedAt: eventDate,
            pendingIdleStartedAt: pendingIdleStartedAt,
            pendingIdleEndedAt: pendingIdleEndedAt,
            pendingIdleReason: state.pendingIdleReason,
            delayedUntilAt: nil,
            delayedFromPromptAt: nil,
            silencedAt: nil,
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

        if let lastAppLaunchAt = state.lastAppLaunchAt {
            candidateStarts.append(lastAppLaunchAt)
        }

        return candidateStarts.max() ?? scheduledCheckInAt.addingTimeInterval(-pollingInterval)
    }

    private func nextLocalMidnight(after date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
    }

    private func makeResult(
        nextCheckInAt: Date?,
        isPromptOverdue: Bool,
        accountableElapsedInterval: TimeInterval,
        accountableWorkEndAt: Date?,
        lastCheckInAt: Date?,
        lastAppLaunchAt: Date,
        idleBeganAt: Date?,
        idleDetectedAt: Date?,
        idleResolvedAt: Date?,
        pendingIdleStartedAt: Date?,
        pendingIdleEndedAt: Date?,
        pendingIdleReason: String?,
        delayedUntilAt: Date?,
        delayedFromPromptAt: Date?,
        silencedAt: Date?,
        silenceEndsAt: Date?
    ) -> PollingSchedulerResult {
        let snapshot = PollingSchedulerSnapshot(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval,
            accountableWorkEndAt: accountableWorkEndAt,
            isPromptDelayed: delayedUntilAt != nil,
            delayedUntilAt: delayedUntilAt,
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
            lastAppLaunchAt: lastAppLaunchAt,
            idleBeganAt: idleBeganAt,
            idleDetectedAt: idleDetectedAt,
            idleResolvedAt: idleResolvedAt,
            pendingIdleStartedAt: pendingIdleStartedAt,
            pendingIdleEndedAt: pendingIdleEndedAt,
            pendingIdleReason: pendingIdleReason,
            delayedUntilAt: delayedUntilAt,
            delayedFromPromptAt: delayedFromPromptAt,
            silencedAt: silencedAt,
            silenceEndsAt: silenceEndsAt
        )
    }
}
