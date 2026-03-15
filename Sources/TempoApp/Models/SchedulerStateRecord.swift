import Foundation
import SwiftData

@Model
final class SchedulerStateRecord {
    @Attribute(.unique) var singletonKey: String
    var lastCheckInAt: Date?
    var nextCheckInAt: Date?
    var lastAppLaunchAt: Date?
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

    init(
        singletonKey: String = "default",
        lastCheckInAt: Date? = nil,
        nextCheckInAt: Date? = nil,
        lastAppLaunchAt: Date? = nil,
        idleBeganAt: Date? = nil,
        idleDetectedAt: Date? = nil,
        idleResolvedAt: Date? = nil,
        pendingIdleStartedAt: Date? = nil,
        pendingIdleEndedAt: Date? = nil,
        pendingIdleReason: String? = nil,
        delayedUntilAt: Date? = nil,
        delayedFromPromptAt: Date? = nil,
        silencedAt: Date? = nil,
        silenceEndsAt: Date? = nil
    ) {
        self.singletonKey = singletonKey
        self.lastCheckInAt = lastCheckInAt
        self.nextCheckInAt = nextCheckInAt
        self.lastAppLaunchAt = lastAppLaunchAt
        self.idleBeganAt = idleBeganAt
        self.idleDetectedAt = idleDetectedAt
        self.idleResolvedAt = idleResolvedAt
        self.pendingIdleStartedAt = pendingIdleStartedAt
        self.pendingIdleEndedAt = pendingIdleEndedAt
        self.pendingIdleReason = pendingIdleReason
        self.delayedUntilAt = delayedUntilAt
        self.delayedFromPromptAt = delayedFromPromptAt
        self.silencedAt = silencedAt
        self.silenceEndsAt = silenceEndsAt
    }
}
