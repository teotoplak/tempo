import Foundation

struct PollingSchedulerSnapshot: Equatable {
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
}

struct PollingSchedulerResult {
    var snapshot: PollingSchedulerSnapshot
    var nextCheckInAt: Date?
    var isPromptOverdue: Bool
    var accountableElapsedInterval: TimeInterval
    var lastCheckInAt: Date?
    var lastAppLaunchAt: Date
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

        guard let existingNextCheckInAt = state.nextCheckInAt else {
            let nextCheckInAt = eventDate.addingTimeInterval(pollingInterval)
            return makeResult(
                nextCheckInAt: nextCheckInAt,
                isPromptOverdue: false,
                accountableElapsedInterval: pollingInterval,
                lastCheckInAt: state.lastCheckInAt,
                lastAppLaunchAt: eventDate
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
                lastAppLaunchAt: eventDate
            )
        }

        let referenceStart = state.lastCheckInAt ?? existingNextCheckInAt.addingTimeInterval(-pollingInterval)
        let elapsedInterval = max(existingNextCheckInAt.timeIntervalSince(referenceStart), pollingInterval)
        return makeResult(
            nextCheckInAt: existingNextCheckInAt,
            isPromptOverdue: false,
            accountableElapsedInterval: elapsedInterval,
            lastCheckInAt: state.lastCheckInAt,
            lastAppLaunchAt: eventDate
        )
    }

    private func makeResult(
        nextCheckInAt: Date,
        isPromptOverdue: Bool,
        accountableElapsedInterval: TimeInterval,
        lastCheckInAt: Date?,
        lastAppLaunchAt: Date
    ) -> PollingSchedulerResult {
        let snapshot = PollingSchedulerSnapshot(
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval
        )

        return PollingSchedulerResult(
            snapshot: snapshot,
            nextCheckInAt: nextCheckInAt,
            isPromptOverdue: isPromptOverdue,
            accountableElapsedInterval: accountableElapsedInterval,
            lastCheckInAt: lastCheckInAt,
            lastAppLaunchAt: lastAppLaunchAt
        )
    }
}
