import SwiftUI

struct CheckInPromptContent: View {
    let appModel: TempoAppModel?
    let state: CheckInPromptState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tempo")
                    .font(.headline.smallCaps())
                    .foregroundStyle(.secondary)

                Text("What are you currently doing")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text(TempoAppModel.formattedElapsedText(for: state.elapsedDuration))
                    .font(.title3.weight(.medium))

                if state.isOverdue {
                    Text("This check-in is overdue, so Tempo is holding the full elapsed block until you classify it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                TextField("Find or create a project", text: promptSearchText)
                    .textFieldStyle(.roundedBorder)

                if let appModel, appModel.canCreatePromptProject(named: appModel.promptSearchText) {
                    InlineProjectCreationView(name: appModel.promptSearchText) {
                        createProjectFromPrompt()
                    }
                }

                CheckInProjectListView(
                    projects: appModel?.filteredPromptProjects ?? [],
                    selectProjectForPrompt: selectProjectForPrompt
                )
            }

            if appModel?.filteredPromptProjects.isEmpty ?? true {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .overlay {
                        Text("No matching projects yet.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(20)
                    }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var promptSearchText: Binding<String> {
        Binding(
            get: { appModel?.promptSearchText ?? "" },
            set: { newValue in
                appModel?.promptSearchText = newValue
            }
        )
    }

    private func selectProjectForPrompt(_ project: ProjectRecord) {
        guard let appModel else {
            return
        }

        try? appModel.selectProjectForPrompt(project)
    }

    private func createProjectFromPrompt() {
        guard let appModel else {
            return
        }

        try? appModel.createAndSelectProjectForPrompt(named: appModel.promptSearchText)
    }
}
