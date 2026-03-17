import SwiftUI

struct CheckInPromptContent: View {
    let appModel: TempoAppModel?
    let state: CheckInPromptState
    @FocusState private var isSearchFieldFocused: Bool

    private var isIdleResolution: Bool {
        appModel?.isIdlePending ?? false
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
                TextField(isIdleResolution ? "Find or create a project" : "Type a project", text: promptSearchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFieldFocused)
                    .help("Select an existing project or create one from what you type.")
                    .onSubmit {
                        submitPromptSearch()
                    }

                compactProjectListSection

                if let appModel, appModel.canCreatePromptProject(named: appModel.promptSearchText) {
                    InlineProjectCreationView(name: appModel.promptSearchText) {
                        createProjectFromPrompt()
                    }
                    .padding(.horizontal, 4)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(promptSupportingSubtitle(at: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

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
                .fill(controlBackground)
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
            .background(controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .background(controlBackground, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                try? appModel.silenceForRestOfDay()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 11, weight: .semibold))

                    Text("Done for day")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(controlBackground, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
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

    private func promptSupportingSubtitle(at date: Date) -> String {
        guard let appModel else {
            return state.supportingSubtitle
        }

        return appModel.promptSupportingSubtitle(at: date)
    }
}
