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

            Spacer()

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(maxWidth: .infinity, minHeight: 160)
                .overlay(alignment: .topLeading) {
                    Text("Project selection arrives in the next plan.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(20)
                }
        }
    }
}
