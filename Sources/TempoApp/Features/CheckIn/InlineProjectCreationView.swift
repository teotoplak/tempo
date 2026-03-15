import SwiftUI

struct InlineProjectCreationView: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                Text("Create \"\(trimmedName)\"")
            }
            .font(.body.weight(.medium))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
