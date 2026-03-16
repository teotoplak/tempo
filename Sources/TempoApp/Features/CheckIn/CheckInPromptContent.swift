import SwiftUI

struct CheckInPromptContent: View {
    let appModel: TempoAppModel?
    let state: CheckInPromptState
    @FocusState private var isSearchFieldFocused: Bool

    private var isIdleResolution: Bool {
        appModel?.isIdlePending == true || state.promptTitle == "Resolve idle time"
    }

    var body: some View {
        Group {
            if isIdleResolution {
                expandedPrompt
            } else {
                compactPrompt
            }
        }
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
                    TextField("Type a project", text: promptSearchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFieldFocused)

                    Menu {
                        if let appModel {
                            ForEach(appModel.delayPresetMinutes, id: \.self) { preset in
                                Button("Delay \(preset) min") {
                                    try? appModel.delayPrompt(byMinutes: preset)
                                }
                            }

                            Divider()

                            Button("Silence for today") {
                                try? appModel.silenceForRestOfDay()
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)

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
            }
            .padding(12)
        }
    }

    private var expandedPrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Find or create a project", text: promptSearchText)
                        .textFieldStyle(.roundedBorder)

                    if let appModel, appModel.canCreatePromptProject(named: appModel.promptSearchText) {
                        InlineProjectCreationView(name: appModel.promptSearchText) {
                            createProjectFromPrompt()
                        }
                    }

                    idleResolutionSection

                    projectListSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        assignIdleButton(appModel: appModel)
                        discardIdleButton(appModel: appModel)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        assignIdleButton(appModel: appModel)
                        discardIdleButton(appModel: appModel)
                    }
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
                        HStack {
                            Text("First segment")
                            Spacer(minLength: 12)
                            Text("\(appModel.idleSplitFirstDurationMinutes) min")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Second project")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

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
                        .pickerStyle(.menu)
                    }

                    Button("Split between projects") {
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
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var headerSection: some View {
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
                compact: true
            )
            .padding(.top, 2)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var projectListSection: some View {
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
            CheckInProjectListView(
                projects: appModel?.filteredPromptProjects ?? [],
                selectedProjectID: appModel?.selectedPromptProjectID,
                onProjectTap: onProjectTap,
                compact: false
            )
        }
    }

    private func assignIdleButton(appModel: TempoAppModel) -> some View {
        Button("Assign selected project") {
            guard let project = appModel.selectedPromptProject else {
                return
            }

            try? appModel.assignPendingIdle(to: project)
        }
        .buttonStyle(.borderedProminent)
        .disabled(appModel.selectedPromptProject == nil)
    }

    private func discardIdleButton(appModel: TempoAppModel) -> some View {
        Button("Discard idle block") {
            try? appModel.discardPendingIdle()
        }
        .buttonStyle(.bordered)
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

    private func focusSearchFieldIfNeeded() {
        guard !isIdleResolution else {
            return
        }

        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }
}
