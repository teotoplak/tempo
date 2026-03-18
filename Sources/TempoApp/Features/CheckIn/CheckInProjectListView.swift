import SwiftUI

struct CheckInProjectListView: View {
    let projects: [ProjectRecord]
    let selectedProjectID: UUID?
    let createProjectName: String?
    let isCreateProjectSelected: Bool
    let onProjectTap: (ProjectRecord) -> Void
    let onCreateProjectTap: () -> Void
    var compact = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(projects) { project in
                    Button {
                        onProjectTap(project)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Text(project.name)
                                .lineLimit(compact ? 1 : 2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: selectedProjectID == project.id ? "checkmark.circle.fill" : "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .frame(width: 14)
                                .foregroundStyle(selectedProjectID == project.id ? Color.accentColor : .secondary)
                        }
                        .padding(.horizontal, compact ? 14 : 16)
                        .padding(.vertical, compact ? 9 : 14)
                        .background(backgroundColor(for: project), in: RoundedRectangle(cornerRadius: compact ? 10 : 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let createProjectName {
                    Button(action: onCreateProjectTap) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                                .frame(width: 14)
                                .foregroundStyle(Color.accentColor)

                            Text("Create \"\(trimmedCreateProjectName(createProjectName))\"")
                                .lineLimit(compact ? 1 : 2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, compact ? 14 : 16)
                        .padding(.vertical, compact ? 9 : 14)
                        .background(createActionBackground, in: RoundedRectangle(cornerRadius: compact ? 10 : 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 96 : 150, maxHeight: compact ? 150 : 220)
    }

    private func backgroundColor(for project: ProjectRecord) -> Color {
        if selectedProjectID == project.id {
            return Color.accentColor.opacity(compact ? 0.14 : 0.16)
        }

        return Color.primary.opacity(compact ? 0.04 : 0.06)
    }

    private var createActionBackground: Color {
        if isCreateProjectSelected {
            return Color.accentColor.opacity(compact ? 0.14 : 0.16)
        }

        return Color.primary.opacity(compact ? 0.04 : 0.06)
    }

    private func trimmedCreateProjectName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
