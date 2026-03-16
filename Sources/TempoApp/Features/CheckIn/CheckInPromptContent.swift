import SwiftUI

struct CheckInPromptContent: View {
    let appModel: TempoAppModel?
    let state: CheckInPromptState
    @FocusState private var isSearchFieldFocused: Bool

    private var isIdleResolution: Bool {
        false
    }

    var body: some View {
        compactPrompt
        .onAppear {
            focusSearchFieldIfNeeded()
        }
        .onChange(of: state.isPresented) { _, isPresented in
            guard isPresented else {
                return
            }

            focusSearchFieldIfNeeded()
        }
    }

    private var compactPrompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.promptTitle)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField(isIdleResolution ? "Find or create a project" : "Type a project", text: promptSearchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            submitPromptSearch()
                        }

                    Button {
                    } label: {
                        Image(systemName: "questionmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Select an existing project or create one from what you type.")
                }

                compactProjectListSection

                if let appModel, appModel.canCreatePromptProject(named: appModel.promptSearchText) {
                    InlineProjectCreationView(name: appModel.promptSearchText) {
                        createProjectFromPrompt()
                    }
                    .padding(.horizontal, 4)
                }

                Text(state.supportingSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if let appModel {
                    standardPromptFooter(appModel: appModel)
                        .padding(.top, 2)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var compactProjectListSection: some View {
        if appModel?.filteredPromptProjects.isEmpty ?? true {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(maxWidth: .infinity, minHeight: 72)
                .overlay {
                    Text("No matching projects")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
        } else {
            CheckInProjectListView(
                projects: Array((appModel?.filteredPromptProjects ?? []).prefix(4)),
                selectedProjectID: appModel?.selectedPromptProjectID,
                onProjectTap: onProjectTap,
                onProjectDoubleTap: onProjectDoubleTap,
                compact: true
            )
            .padding(.top, 2)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func standardPromptFooter(appModel: TempoAppModel) -> some View {
        HStack(spacing: 10) {
            Button {
                appModel.dismissCheckInPrompt()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Menu {
                ForEach(appModel.delayPresetMinutes, id: \.self) { preset in
                    Button("Delay \(preset) min") {
                        try? appModel.delayPrompt(byMinutes: preset)
                    }
                }

                Divider()

                Button("Done for day") {
                    try? appModel.silenceForRestOfDay()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.05), in: Circle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 4)
    }

    private var promptSearchText: Binding<String> {
        Binding(
            get: { appModel?.promptSearchText ?? "" },
            set: { newValue in
                appModel?.updatePromptSearchText(newValue)
            }
        )
    }

    private func onProjectTap(_ project: ProjectRecord) {
        try? appModel?.selectProjectForPrompt(project)
    }

    private func onProjectDoubleTap(_ project: ProjectRecord) {
        try? appModel?.selectProjectForPrompt(project)
    }

    private func createProjectFromPrompt() {
        guard let appModel else {
            return
        }

        try? appModel.createAndSelectProjectForPrompt(named: appModel.promptSearchText)
    }

    private func submitPromptSearch() {
        try? appModel?.submitPromptSearch()
    }

    private func focusSearchFieldIfNeeded() {
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }
}
