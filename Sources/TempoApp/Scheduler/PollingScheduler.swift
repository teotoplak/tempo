import Foundation

struct PollingSchedulerSnapshot: Equatable {
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
    var isPromptDelayed: Bool
    var delayedUntilAt: Date?
    var isSilenced: Bool
    var silenceEndsAt: Date?
}

struct PollingSchedulerResult {
    var snapshot: PollingSchedulerSnapshot
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
    var lastCheckInAt: Date?
    var lastAppLaunchAt: Date
    var delayedUntilAt: Date?
    var delayedFromPromptAt: Date?
    var silencedAt: Date?
    var silenceEndsAt: Date?
}

final class PollingScheduler {
    private let clock: any SchedulerClock

    init(clock: any SchedulerClock) {
        self.clock = clock
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

        if let silenceEndsAt = state.silenceEndsAt {
            if eventDate < silenceEndsAt {
                return makeResult(
                    nextCheckInAt: silenceEndsAt,
                    isPromptOverdue: false,
                    accountableElapsedInterval: 0,
                    lastCheckInAt: state.lastCheckInAt,
                    lastAppLaunchAt: eventDate,
                    delayedUntilAt: nil,
                    delayedFromPromptAt: nil,
                    silencedAt: state.silencedAt,
                    silenceEndsAt: silenceEndsAt
                )
            }

            let nextCheckInAt = eventDate.addingTimeInterval(pollingInterval)
            return makeResult(
                nextCheckInAt: nextCheckInAt,
                isPromptOverdue: false,
                accountableElapsedInterval: pollingInterval,
                lastCheckInAt: state.lastCheckInAt,
                lastAppLaunchAt: eventDate,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
                silenceEndsAt: nil
            )
        }

        if let delayedUntilAt = state.delayedUntilAt {
            let referenceStart = delayReferenceStart(for: state, pollingInterval: pollingInterval)

            if eventDate < delayedUntilAt {
                return makeResult(
                    nextCheckInAt: delayedUntilAt,
                    isPromptOverdue: false,
                    accountableElapsedInterval: max(eventDate.timeIntervalSince(referenceStart), pollingInterval),
                    lastCheckInAt: state.lastCheckInAt,
                    lastAppLaunchAt: eventDate,
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
                lastCheckInAt: state.lastCheckInAt,
                lastAppLaunchAt: eventDate,
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
                lastCheckInAt: state.lastCheckInAt,
                lastAppLaunchAt: eventDate,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
                silenceEndsAt: nil
            )
        }

        if existingNextCheckInAt <= eventDate {
            let referenceStart = state.lastCheckInAt ?? existingNextCheckInAt.addingTimeInterval(-pollingInterval)
            let elapsedInterval = max(eventDate.timeIntervalSince(referenceStart), pollingInterval)
            return makeResult(
                nextCheckInAt: existingNextCheckInAt,
                isPromptOverdue: true,
                accountableElapsedInterval: elapsedInterval,
                lastCheckInAt: state.lastCheckInAt,
                lastAppLaunchAt: eventDate,
                delayedUntilAt: nil,
                delayedFromPromptAt: nil,
                silencedAt: nil,
                silenceEndsAt: nil
            )
        }

        let referenceStart = state.lastCheckInAt ?? existingNextCheckInAt.addingTimeInterval(-pollingInterval)
        let elapsedInterval = max(existingNextCheckInAt.timeIntervalSince(referenceStart), pollingInterval)
        return makeResult(
            nextCheckInAt: existingNextCheckInAt,
            isPromptOverdue: false,
            accountableElapsedInterval: elapsedInterval,
            lastCheckInAt: state.lastCheckInAt,
            lastAppLaunchAt: eventDate,
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
        let referenceStart = state.lastCheckInAt ?? promptReference.addingTimeInterval(-pollingInterval)

        return makeResult(
            nextCheckInAt: delayedUntilAt,
            isPromptOverdue: false,
            accountableElapsedInterval: max(delayDate.timeIntervalSince(referenceStart), pollingInterval),
            lastCheckInAt: state.lastCheckInAt,
            lastAppLaunchAt: delayDate,
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
            lastCheckInAt: state.lastCheckInAt,
            lastAppLaunchAt: eventDate,
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
            lastCheckInAt: state.lastCheckInAt,
            lastAppLaunchAt: eventDate,
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
            lastCheckInAt: completionDate,
            lastAppLaunchAt: completionDate,
            delayedUntilAt: nil,
            delayedFromPromptAt: nil,
            silencedAt: nil,
            silenceEndsAt: nil
        )
    }

    private func delayReferenceStart(
        for state: SchedulerStateRecord,
        pollingInterval: TimeInterval
    ) -> Date {
        if let lastCheckInAt = state.lastCheckInAt {
            return lastCheckInAt
        }

        let promptReference = state.delayedFromPromptAt ?? state.nextCheckInAt ?? clock.now
        return promptReference.addingTimeInterval(-pollingInterval)
    }

    private func nextLocalMidnight(after date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
    }

    private func makeResult(
        nextCheckInAt: Date,
        isPromptOverdue: Bool,
        accountableElapsedInterval: TimeInterval,
        lastCheckInAt: Date?,
        lastAppLaunchAt: Date,
        delayedUntilAt: Date?,
        delayedFromPromptAt: Date?,
        silencedAt: Date?,
        silenceEndsAt: Date?
    ) -> PollingSchedulerResult {
        let snapshot = PollingSchedulerSnapshot(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval,
            isPromptDelayed: delayedUntilAt != nil,
            delayedUntilAt: delayedUntilAt,
            isSilenced: silenceEndsAt != nil,
            silenceEndsAt: silenceEndsAt
        )

        return PollingSchedulerResult(
            snapshot: snapshot,
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval,
            lastCheckInAt: lastCheckInAt,
            lastAppLaunchAt: lastAppLaunchAt,
            delayedUntilAt: delayedUntilAt,
            delayedFromPromptAt: delayedFromPromptAt,
            silencedAt: silencedAt,
            silenceEndsAt: silenceEndsAt
        )
    }
}
