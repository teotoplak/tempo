import Foundation
import SwiftData

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var singletonKey: String
    var pollingIntervalMinutes: Int
    var idleThresholdMinutes: Int
    private var delayPresetMinutesStorage: String
    var launchAtLoginEnabled: Bool

    var delayPresetMinutes: [Int] {
        get {
            let presets = delayPresetMinutesStorage
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { $0 > 0 }

            return presets.isEmpty ? [15, 30] : presets
        }
        set {
            let normalized = newValue.filter { $0 > 0 }
            let resolved = normalized.isEmpty ? [15, 30] : normalized
            delayPresetMinutesStorage = resolved.map(String.init).joined(separator: ",")
        }
    }

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
        self.delayPresetMinutesStorage = delayPresetMinutes.map(String.init).joined(separator: ",")
        self.launchAtLoginEnabled = launchAtLoginEnabled
    }
}
