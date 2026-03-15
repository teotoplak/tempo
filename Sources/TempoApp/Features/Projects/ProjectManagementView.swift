import SwiftData
import SwiftUI

struct ProjectManagementView: View {
    @Bindable var appModel: TempoAppModel
    @Query(sort: \ProjectRecord.sortOrder) private var projects: [ProjectRecord]

    @State private var activeSheet: EditorSheet?
    @State private var deletionCandidate: ProjectRecord?
    @State private var errorMessage: String?

    init(appModel: TempoAppModel) {
        self.appModel = appModel
        _projects = Query(sort: \ProjectRecord.sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projects")
                        .font(.largeTitle.weight(.semibold))
                    Text("Manage your flat local project list.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Add Project") {
                    activeSheet = .create
                }
            }

            List {
                ForEach(projects) { project in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                            Text(project.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Rename") {
                            activeSheet = .rename(project)
                        }
                        .buttonStyle(.borderless)

                        Button("Delete") {
                            deletionCandidate = project
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects Yet",
                        systemImage: "tray",
                        description: Text("Add a project to start building your tracking list.")
                    )
                }
            }
        }
        .padding(24)
        .alert("Project Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete this project?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { newValue in
                    if !newValue {
                        deletionCandidate = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletionCandidate {
                    delete(deletionCandidate)
                }
                deletionCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deletionCandidate = nil
            }
        } message: {
            Text("Tempo will keep local data safe and block deletion if \((deletionCandidate?.name ?? "this project")) already has tracked time.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                ProjectEditorView(title: "Add Project") { name in
                    createProject(named: name)
                }
            case let .rename(project):
                ProjectEditorView(title: "Rename Project", initialName: project.name) { name in
                    rename(project: project, to: name)
                }
            }
        }
    }

    private func createProject(named name: String) {
        do {
            try appModel.createProject(named: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename(project: ProjectRecord, to name: String) {
        do {
            try appModel.renameProject(project, to: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ project: ProjectRecord) {
        do {
            try appModel.deleteProject(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum EditorSheet: Identifiable {
    case create
    case rename(ProjectRecord)

    var id: String {
        switch self {
        case .create:
            return "create"
        case let .rename(project):
            return "rename-\(project.id.uuidString)"
        }
    }
}
