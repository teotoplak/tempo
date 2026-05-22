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

            Section("Keyboard Shortcut") {
                HStack(spacing: 10) {
                    Text(appModel.checkInHotKeyDisplayText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )

                    if appModel.isRecordingCheckInHotKey {
                        Button("Cancel") {
                            appModel.cancelRecordingCheckInHotKey()
                        }
                    } else {
                        Button("Record") {
                            appModel.beginRecordingCheckInHotKey()
                        }
                    }

                    Button("Clear") {
                        appModel.clearCheckInHotKey()
                    }
                    .disabled(appModel.checkInHotKey == nil && !appModel.isRecordingCheckInHotKey)
                }

                Text(checkInHotKeyHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let hotKeyStatusMessage = appModel.checkInHotKeyStatusMessage {
                    Text(hotKeyStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                Button("Reveal Trace Log in Finder") {
                    appModel.revealDiagnosticsLogInFinder()
                }

                Text(appModel.diagnosticsLogPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Tempo keeps a rolling trace of lock, wake, timer, and prompt-window events for troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let diagnosticsStatusMessage = appModel.diagnosticsStatusMessage {
                    Text(diagnosticsStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var checkInHotKeyHelpText: String {
        if appModel.isRecordingCheckInHotKey {
            return "Press the shortcut you want to use for Check In Now."
        }

        return "This shortcut works globally while Tempo is running."
    }
}
