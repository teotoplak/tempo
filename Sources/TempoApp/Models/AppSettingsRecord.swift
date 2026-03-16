import Foundation
import SwiftData

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var singletonKey: String
    var pollingIntervalMinutes: Int
    var idleThresholdMinutes: Int
    var analyticsDayCutoffHour: Int
    var launchAtLoginEnabled: Bool

    init(
        singletonKey: String = "default",
        pollingIntervalMinutes: Int = 25,
        idleThresholdMinutes: Int = 5,
        analyticsDayCutoffHour: Int = 6,
        launchAtLoginEnabled: Bool = false
    ) {
        self.singletonKey = singletonKey
        self.pollingIntervalMinutes = pollingIntervalMinutes
        self.idleThresholdMinutes = idleThresholdMinutes
        self.analyticsDayCutoffHour = min(max(analyticsDayCutoffHour, 0), 23)
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}
