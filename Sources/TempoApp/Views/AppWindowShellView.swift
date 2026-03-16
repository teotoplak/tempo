import SwiftUI

struct AppWindowShellView: View {
    @Bindable var appModel: TempoAppModel

    var body: some View {
        NavigationSplitView {
            List(TempoAppModel.WindowSection.allCases, selection: $appModel.selectedWindow) { section in
                Label(section.title, systemImage: iconName(for: section))
                    .tag(section)
            }
            .navigationTitle("Tempo")
        } detail: {
            switch appModel.selectedWindow {
            case .projects:
                ProjectManagementView(appModel: appModel)
            case .analytics:
                AnalyticsView(appModel: appModel)
            }
        }
    }

    private func iconName(for section: TempoAppModel.WindowSection) -> String {
        switch section {
        case .projects:
            return "folder"
        case .analytics:
            return "chart.bar"
        }
    }
}
