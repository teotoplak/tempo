import SwiftUI

struct MenuBarRootView: View {
    @Bindable var appModel: TempoAppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isShowingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tempo")
                .font(.headline)

            Text(appModel.launchState == .ready ? "Daily tracking control surface" : "Preparing local tracking services...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 10) {
                    statusCard(
                        title: appModel.isSilenced ? "Silence status" : "Next check-in",
                        primary: appModel.menuBarPrimaryStatus(at: context.date),
                        secondary: appModel.menuBarSecondaryStatus(at: context.date)
                    )
                    statusCard(
                        title: "Current project",
                        primary: appModel.currentProjectContextLabel,
                        secondary: appModel.isPromptOverdue ? "Prompt is waiting for classification." : "Based on the latest completed check-in."
                    )
                    statusCard(
                        title: "Today's total",
                        primary: TempoAppModel.formattedTrackedDuration(appModel.todaysTrackedDuration),
                        secondary: "Local tracked duration for the current day."
                    )
                }
            }

            Divider()

            Button("Check In Now") {
                appModel.checkInNow()
            }

            Button("Open Analytics") {
                appModel.selectedWindow = .analytics
                openWindow(id: AppSceneID.mainWindow.rawValue)
            }

            Button("Projects") {
                appModel.selectedWindow = .projects
                openWindow(id: AppSceneID.mainWindow.rawValue)
            }

            if appModel.isSilenced {
                Button("Unsilence") {
                    try? appModel.endSilenceMode()
                }
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
        .frame(width: 320)
    }

    private func statusCard(title: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(primary)
                .font(.body.monospacedDigit())
            Text(secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
