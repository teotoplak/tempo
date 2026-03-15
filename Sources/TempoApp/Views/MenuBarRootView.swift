import SwiftUI

struct MenuBarRootView: View {
    @Bindable var appModel: TempoAppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isShowingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tempo")
                .font(.headline)

            Text(appModel.launchState == .ready ? "Running quietly from the menu bar." : "Preparing local tracking services...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Next check-in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nextCheckInLabel)
                    .font(.body.monospacedDigit())

                Text("Overdue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appModel.isPromptOverdue ? "Yes" : "No")
                    .font(.body)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            Divider()

            Button("Open Tempo") {
                openWindow(id: AppSceneID.mainWindow.rawValue)
            }

            Button("Settings") {
                isShowingSettings = true
            }
            .popover(isPresented: $isShowingSettings, arrowEdge: .top) {
                SettingsPopoverView(appModel: appModel)
                    .frame(width: 320)
                    .padding()
            }

            Button("Quit Tempo") {
                appModel.quit()
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var nextCheckInLabel: String {
        guard let nextCheckInAt = appModel.nextCheckInAt else {
            return "Not scheduled"
        }

        return nextCheckInAt.formatted(date: .omitted, time: .shortened)
    }
}
