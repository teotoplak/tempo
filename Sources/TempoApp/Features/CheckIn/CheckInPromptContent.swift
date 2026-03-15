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

                Text(state.promptTitle)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text(state.supportingSubtitle)
                    .font(.title3.weight(.medium))

                if appModel?.isIdlePending == true {
                    Text("\(appModel?.pendingIdleReasonDisplayText ?? "Inactive") interval ready for reconciliation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if state.isOverdue {
                    Text("This check-in is overdue, so Tempo is holding the full elapsed block until you classify it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                if let appModel, !appModel.isIdlePending {
                    quickActions(appModel: appModel)
                }

                TextField("Find or create a project", text: promptSearchText)
                    .textFieldStyle(.roundedBorder)

                if let appModel, appModel.canCreatePromptProject(named: appModel.promptSearchText) {
                    InlineProjectCreationView(name: appModel.promptSearchText) {
                        createProjectFromPrompt()
                    }
                }

                if appModel?.isIdlePending == true {
                    idleResolutionSection
                }

                CheckInProjectListView(
                    projects: appModel?.filteredPromptProjects ?? [],
                    selectedProjectID: appModel?.selectedPromptProjectID,
                    onProjectTap: onProjectTap
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

    private func quickActions(appModel: TempoAppModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(appModel.delayPresetMinutes, id: \.self) { preset in
                    Button("Delay \(preset) min") {
                        try? appModel.delayPrompt(byMinutes: preset)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Silence for today") {
                    try? appModel.silenceForRestOfDay()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var idleResolutionSection: some View {
        if let appModel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Resolve idle time")
                    .font(.headline)

                Text("\(TempoAppModel.formattedCompactDuration(appModel.pendingIdleDuration)) • \(appModel.pendingIdleReasonDisplayText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Assign all to selected project") {
                        guard let project = appModel.selectedPromptProject else {
                            return
                        }

                        try? appModel.assignPendingIdle(to: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.selectedPromptProject == nil)

                    Button("Discard idle time") {
                        try? appModel.discardPendingIdle()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Split idle time")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Stepper(
                        value: Binding(
                            get: { appModel.idleSplitFirstDurationMinutes },
                            set: { appModel.idleSplitFirstDurationMinutes = $0 }
                        ),
                        in: appModel.firstIdleSegmentMinutesRange
                    ) {
                        Text("First segment (minutes): \(appModel.idleSplitFirstDurationMinutes)")
                    }

                    Picker(
                        "Second project",
                        selection: Binding(
                            get: { appModel.idleSplitSecondProjectID ?? appModel.selectedPromptProjectID ?? UUID() },
                            set: { appModel.idleSplitSecondProjectID = $0 }
                        )
                    ) {
                        ForEach(appModel.recentPromptProjects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }

                    Button("Split idle time") {
                        guard
                            let firstProject = appModel.selectedPromptProject,
                            let secondProject = appModel.idleSplitSecondProject
                        else {
                            return
                        }

                        try? appModel.splitPendingIdle(
                            firstProject: firstProject,
                            firstDurationMinutes: appModel.idleSplitFirstDurationMinutes,
                            secondProject: secondProject
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.selectedPromptProject == nil || appModel.idleSplitSecondProject == nil)
                }
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

    private func onProjectTap(_ project: ProjectRecord) {
        guard let appModel else {
            return
        }

        if appModel.isIdlePending {
            appModel.selectedPromptProjectID = project.id
            if appModel.idleSplitSecondProjectID == nil {
                appModel.idleSplitSecondProjectID = project.id
            }
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
