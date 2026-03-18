import SwiftUI

struct CheckInPromptContent: View {
    let appModel: TempoAppModel?
    let state: CheckInPromptState
    @State private var searchFieldFocusRequestID = 0

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
                PromptSearchField(
                    placeholder: isIdleResolution ? "Find or create a project" : "Type a project",
                    text: promptSearchText,
                    focusRequestID: searchFieldFocusRequestID,
                    onSubmit: submitPromptSearch,
                    onMoveUp: { appModel?.movePromptSelection(by: -1) },
                    onMoveDown: { appModel?.movePromptSelection(by: 1) }
                )
                    .help("Select an existing project or create one from what you type.")

                compactProjectListSection

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
        let hasProjects = !(appModel?.visiblePromptProjects.isEmpty ?? true)
        let hasCreateAction = appModel?.hasVisiblePromptCreateAction ?? false

        if !hasProjects && !hasCreateAction {
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
                projects: appModel?.visiblePromptProjects ?? [],
                selectedProjectID: appModel?.selectedPromptProjectID,
                createProjectName: hasCreateAction ? appModel?.promptSearchText : nil,
                isCreateProjectSelected: appModel?.isCreatePromptProjectSelected ?? false,
                onProjectTap: onProjectTap,
                onCreateProjectTap: createProjectFromPrompt,
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
        searchFieldFocusRequestID += 1
    }

    private func promptSupportingSubtitle(at date: Date) -> String {
        guard let appModel else {
            return state.supportingSubtitle
        }

        return appModel.promptSupportingSubtitle(at: date)
    }
}
