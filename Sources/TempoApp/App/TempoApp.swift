import AppKit
import SwiftUI

@main
struct TempoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = TempoAppModel()
    private let checkInPromptWindowController = CheckInPromptWindowController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(appModel: appModel)
                .modelContainer(appModel.modelContainer)
                .task {
                    bootstrapAppIfNeeded()
                }
        } label: {
            MenuBarLabelView(appModel: appModel)
                .task {
                    bootstrapAppIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Tempo", id: AppSceneID.mainWindow.rawValue) {
            AppWindowShellView(appModel: appModel)
                .modelContainer(appModel.modelContainer)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    bootstrapAppIfNeeded()
                }
        }
        .defaultSize(width: 1080, height: 680)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            bootstrapAppIfNeeded()
            appModel.handleSceneActivation()
            appModel.presentCheckInPromptIfNeeded()
        }
    }

    @MainActor
    private func bootstrapAppIfNeeded() {
        appModel.attachCheckInPromptWindowController(checkInPromptWindowController)
        appModel.performInitialLaunchIfNeeded()
        appModel.presentCheckInPromptIfNeeded()
    }
}
