import Foundation
import SwiftData

@Model
final class SchedulerStateRecord {
    @Attribute(.unique) var singletonKey: String
    var lastCheckInAt: Date?
    var nextCheckInAt: Date?
    var lastAppLaunchAt: Date?
    var delayedUntilAt: Date?
    var delayedFromPromptAt: Date?
    var silencedAt: Date?
    var silenceEndsAt: Date?

    init(
        singletonKey: String = "default",
        lastCheckInAt: Date? = nil,
        nextCheckInAt: Date? = nil,
        lastAppLaunchAt: Date? = nil,
        delayedUntilAt: Date? = nil,
        delayedFromPromptAt: Date? = nil,
        silencedAt: Date? = nil,
        silenceEndsAt: Date? = nil
    ) {
        self.singletonKey = singletonKey
        self.lastCheckInAt = lastCheckInAt
        self.nextCheckInAt = nextCheckInAt
        self.lastAppLaunchAt = lastAppLaunchAt
        self.delayedUntilAt = delayedUntilAt
        self.delayedFromPromptAt = delayedFromPromptAt
        self.silencedAt = silencedAt
        self.silenceEndsAt = silenceEndsAt
    }
}
