import SwiftUI

struct CheckInPromptView: View {
    let appModel: TempoAppModel?
    let state: CheckInPromptState

    private var isIdleResolution: Bool {
        state.promptTitle == "Resolve idle time"
    }

    var body: some View {
        CheckInPromptContent(appModel: appModel, state: state)
            .frame(
                minWidth: isIdleResolution ? 368 : 336,
                minHeight: isIdleResolution ? 380 : 284
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(cardBackground)
    }

    private var cardBackground: some View {
        ZStack(alignment: .topTrailing) {
            if !isIdleResolution {
                PopoverArrow()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 22, height: 12)
                    .offset(x: -72, y: -6)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }

            RoundedRectangle(cornerRadius: isIdleResolution ? 28 : 14, style: .continuous)
                .fill(AnyShapeStyle(Color.white.opacity(0.96)))
                .overlay(
                    RoundedRectangle(cornerRadius: isIdleResolution ? 28 : 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(isIdleResolution ? 0.08 : 0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isIdleResolution ? 0.22 : 0.18), radius: isIdleResolution ? 28 : 18, y: isIdleResolution ? 14 : 8)
        }
    }
}

private struct PopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
