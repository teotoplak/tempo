import Foundation
import SwiftData

@Model
final class SchedulerStateRecord {
    @Attribute(.unique) var singletonKey: String
    var nextCheckInAt: Date?
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
    var silenceEndsAt: Date?

    init(
        singletonKey: String = "default",
        nextCheckInAt: Date? = nil,
        pendingIdleStartedAt: Date? = nil,
        pendingIdleEndedAt: Date? = nil,
        pendingIdleReason: String? = nil,
        silenceEndsAt: Date? = nil
    ) {
        self.singletonKey = singletonKey
        self.nextCheckInAt = nextCheckInAt
        self.pendingIdleStartedAt = pendingIdleStartedAt
        self.pendingIdleEndedAt = pendingIdleEndedAt
        self.pendingIdleReason = pendingIdleReason
        self.silenceEndsAt = silenceEndsAt
    }
}
