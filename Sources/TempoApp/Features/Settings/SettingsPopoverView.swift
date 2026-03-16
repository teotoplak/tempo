import SwiftUI

struct SettingsPopoverView: View {
    @Bindable var appModel: TempoAppModel

    var body: some View {
        Form {
            Section("Polling Interval") {
                Stepper(value: $appModel.settings.pollingIntervalMinutes, in: 5...120, step: 5) {
                    Text("\(appModel.settings.pollingIntervalMinutes) minutes")
                }
            }

            Section("Idle Threshold") {
                Stepper(value: $appModel.settings.idleThresholdMinutes, in: 1...30) {
                    Text("\(appModel.settings.idleThresholdMinutes) minutes")
                }
            }

            Section("Day Cutoff") {
                Stepper(value: $appModel.settings.analyticsDayCutoffHour, in: 0...23) {
                    Text("\(appModel.settings.analyticsDayCutoffHour):00")
                }

                Text("Analytics days and done-for-day silence reset at this hour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Launch at Login") {
                Toggle("Launch Tempo when I sign in", isOn: Binding(
                    get: { appModel.launchAtLoginEnabled },
                    set: { enabled in
                        appModel.launchAtLoginEnabled = enabled
                        try? appModel.saveLaunchAtLoginPreference(enabled)
                    }
                ))

                Text("Uses the native macOS login item registration for this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage = appModel.launchAtLoginErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appModel.settings.pollingIntervalMinutes) { _, _ in persistSettings() }
        .onChange(of: appModel.settings.idleThresholdMinutes) { _, _ in persistSettings() }
        .onChange(of: appModel.settings.analyticsDayCutoffHour) { _, _ in persistSettings() }
    }

    private func persistSettings() {
        try? appModel.saveSettings()
    }
}
