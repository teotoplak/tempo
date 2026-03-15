import SwiftUI

struct CheckInPromptView: View {
    let appModel: TempoAppModel?
    let state: CheckInPromptState

    var body: some View {
        CheckInPromptContent(appModel: appModel, state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThickMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
    }
}
