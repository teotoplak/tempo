import Foundation
import SwiftData

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var singletonKey: String
    var pollingIntervalMinutes: Int
    var idleThresholdMinutes: Int
    var delayPresetMinutes: [Int]
    var launchAtLoginEnabled: Bool

    init(
        singletonKey: String = "default",
        pollingIntervalMinutes: Int = 25,
        idleThresholdMinutes: Int = 5,
        delayPresetMinutes: [Int] = [15, 30],
        launchAtLoginEnabled: Bool = false
    ) {
        self.singletonKey = singletonKey
        self.pollingIntervalMinutes = pollingIntervalMinutes
        self.idleThresholdMinutes = idleThresholdMinutes
        self.delayPresetMinutes = delayPresetMinutes
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}
