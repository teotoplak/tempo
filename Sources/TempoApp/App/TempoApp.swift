import AppKit
import SwiftUI

@main
struct TempoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = TempoAppModel()

    private let workspaceWakeNotification = NSWorkspace.didWakeNotification

    var body: some Scene {
        MenuBarExtra("Tempo", systemImage: "clock") {
            MenuBarRootView(appModel: appModel)
                .modelContainer(appModel.modelContainer)
                .task {
                    appModel.performInitialLaunchIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Tempo", id: AppSceneID.mainWindow.rawValue) {
            AppWindowShellView(appModel: appModel)
                .modelContainer(appModel.modelContainer)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    appModel.performInitialLaunchIfNeeded()
                }
        }
        .defaultSize(width: 1080, height: 680)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            appModel.handleSceneActivation()
        }
    }
}
