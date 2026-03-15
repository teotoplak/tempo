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
                analyticsPlaceholder
            }
        }
    }

    private var analyticsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analytics")
                .font(.largeTitle.weight(.semibold))
            Text("Phase 1 reserves the main window shell so later analytics work has a real app surface instead of being squeezed into the menu bar.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
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
