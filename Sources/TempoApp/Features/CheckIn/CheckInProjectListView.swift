import SwiftUI

struct CheckInProjectListView: View {
    let projects: [ProjectRecord]
    let selectedProjectID: UUID?
    let onProjectTap: (ProjectRecord) -> Void
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
}
