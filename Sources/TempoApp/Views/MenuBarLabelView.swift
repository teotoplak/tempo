import SwiftUI

struct MenuBarLabelView: View {
    @Bindable var appModel: TempoAppModel
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "metronome.fill")

            if let countdown = appModel.menuBarCountdownMinutesText(at: now) {
                Text(countdown)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 13, weight: .medium))
        .onAppear {
            now = Date()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { currentDate in
            now = currentDate
        }
        .onChange(of: appModel.nextCheckInAt) { _, _ in
            now = Date()
        }
        .onChange(of: appModel.isSilenced) { _, _ in
            now = Date()
        }
    }
}
