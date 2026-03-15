import Foundation
import SwiftData

@Model
final class SchedulerStateRecord {
    @Attribute(.unique) var singletonKey: String
    var lastCheckInAt: Date?
    var nextCheckInAt: Date?
    var lastAppLaunchAt: Date?

    init(
        singletonKey: String = "default",
        lastCheckInAt: Date? = nil,
        nextCheckInAt: Date? = nil,
        lastAppLaunchAt: Date? = nil
    ) {
        self.singletonKey = singletonKey
        self.lastCheckInAt = lastCheckInAt
        self.nextCheckInAt = nextCheckInAt
        self.lastAppLaunchAt = lastAppLaunchAt
    }
}
