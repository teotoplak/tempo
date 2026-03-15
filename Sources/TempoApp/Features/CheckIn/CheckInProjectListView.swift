import SwiftUI

struct CheckInProjectListView: View {
    let projects: [ProjectRecord]
    let selectedProjectID: UUID?
    let onProjectTap: (ProjectRecord) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(projects) { project in
                    Button {
                        onProjectTap(project)
                    } label: {
                        HStack {
                            Text(project.name)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: selectedProjectID == project.id ? "checkmark.circle.fill" : "arrow.up.right")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            (selectedProjectID == project.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 220)
    }
}
