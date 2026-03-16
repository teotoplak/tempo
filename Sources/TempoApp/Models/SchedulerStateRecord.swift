import Foundation
import SwiftData

@Model
final class SchedulerStateRecord {
    @Attribute(.unique) var singletonKey: String
    var lastCheckInAt: Date?
    var nextCheckInAt: Date?
    var idleBeganAt: Date?
    var idleDetectedAt: Date?
    var idleResolvedAt: Date?
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
    var silenceEndsAt: Date?

    init(
        singletonKey: String = "default",
        lastCheckInAt: Date? = nil,
        nextCheckInAt: Date? = nil,
        idleBeganAt: Date? = nil,
        idleDetectedAt: Date? = nil,
        idleResolvedAt: Date? = nil,
        pendingIdleStartedAt: Date? = nil,
        pendingIdleEndedAt: Date? = nil,
        pendingIdleReason: String? = nil,
        silenceEndsAt: Date? = nil
    ) {
        self.singletonKey = singletonKey
        self.lastCheckInAt = lastCheckInAt
        self.nextCheckInAt = nextCheckInAt
        self.idleBeganAt = idleBeganAt
        self.idleDetectedAt = idleDetectedAt
        self.idleResolvedAt = idleResolvedAt
        self.pendingIdleStartedAt = pendingIdleStartedAt
        self.pendingIdleEndedAt = pendingIdleEndedAt
        self.pendingIdleReason = pendingIdleReason
        self.silenceEndsAt = silenceEndsAt
    }
}
