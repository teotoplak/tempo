import SwiftUI

struct MenuBarRootView: View {
    @Bindable var appModel: TempoAppModel
    @State private var isShowingSettings = false
    @State private var isShowingTroubleshootingCheckIns = false
    @Environment(\.calendar) private var calendar

    private let actionColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        Group {
            defaultMenuContent
        }
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
        .onAppear {
            appModel.setMenuBarWindowVisible(true)
        }
        .onDisappear {
            appModel.setMenuBarWindowVisible(false)
        }
    }

    private var defaultMenuContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 10) {
                        if appModel.isIdlePending {
                            statusCard(
                                title: "Idle detected",
                                primary: "Check in when you return",
                                secondary: appModel.pendingIdleStatusText,
                                accent: Color(red: 0.78, green: 0.39, blue: 0.12),
                                icon: "figure.walk.motion"
                            )
                        }

                        statusCard(
                            title: appModel.isSilenced ? "Silence status" : "Next check-in",
                            primary: appModel.menuBarPrimaryStatus(at: context.date),
                            secondary: appModel.menuBarSecondaryStatus(at: context.date),
                            accent: appModel.isSilenced
                                ? Color(red: 0.32, green: 0.39, blue: 0.64)
                                : Color(red: 0.10, green: 0.47, blue: 0.67),
                            icon: appModel.isSilenced
                                ? "moon.stars.fill"
                                : "clock.arrow.trianglehead.counterclockwise.rotate.90"
                        )
                    }
                }

                dailySummarySection

                primaryActionButton

                if !appModel.isSilenced {
                    doneForDayActionButton
                }

                LazyVGrid(columns: actionColumns, spacing: 10) {
                    secondaryActionButton(title: "Settings", icon: "slider.horizontal.3") {
                        isShowingSettings = true
                    }
                    .popover(isPresented: $isShowingSettings, arrowEdge: .top) {
                        SettingsPopoverView(appModel: appModel)
                            .frame(width: 320)
                            .padding()
                    }

                    if appModel.isSilenced {
                        secondaryActionButton(title: "Unsilence", icon: "speaker.wave.2.fill") {
                            try? appModel.endSilenceMode()
                        }
                    } else {
                        secondaryActionButton(title: "Quit", icon: "power") {
                            appModel.quit()
                        }
                    }
                }

                if appModel.isSilenced {
                    secondaryActionButton(title: "Quit Tempo", icon: "power") {
                        appModel.quit()
                    }
                }
            }
            .padding(14)
        }
        .scrollIndicators(.never)
        .frame(width: 320)
        .frame(idealHeight: 520, maxHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "metronome.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Tempo")
                    .font(.system(size: 16, weight: .semibold))

                Text(appModel.launchState == .ready ? "Local tracking controls" : "Preparing local tracking services...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            statusPill
        }
    }

    private var statusPill: some View {
        Text(appModel.launchState == .ready ? "Ready" : "Launching")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(appModel.launchState == .ready ? Color.green : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill((appModel.launchState == .ready ? Color.green : Color.orange).opacity(0.12))
            )
    }

    private var primaryActionButton: some View {
        Button {
            presentDetachedPrompt {
                appModel.checkInNow()
                appModel.presentCheckInPromptIfNeeded()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))

                Text("Check In Now")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var doneForDayActionButton: some View {
        Button {
            try? appModel.silenceForRestOfDay()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 12, weight: .semibold))

                Text("Done for day")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func presentDetachedPrompt(_ action: @escaping () -> Void) {
        appModel.setMenuBarWindowVisible(false)
        NSApplication.shared.keyWindow?.orderOut(nil)

        DispatchQueue.main.async {
            action()
        }
    }

    private func secondaryActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func statusCard(title: String, primary: String, secondary: String, accent: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(primary)
                    .font(.system(size: 18, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(secondary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.12))
        }
    }

    private var dailySummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    appModel.showPreviousMenuBarDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Text(summaryDateTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)

                Button {
                    appModel.showNextMenuBarDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!appModel.canShowNextMenuBarDay)
                .opacity(appModel.canShowNextMenuBarDay ? 1 : 0.35)
            }
            .padding(.bottom, 2)

            Text("\(TempoAppModel.formattedTrackedDuration(appModel.menuBarDayWorkedDuration)) worked")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            if appModel.menuBarDayProjectSummaries.isEmpty {
                ContentUnavailableView {
                    Label(noTrackedTimeTitle, systemImage: "clock.badge.questionmark")
                } description: {
                    Text(noTrackedTimeDescription)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appModel.menuBarDayProjectSummaries, id: \.id) { summary in
                        projectSummaryRow(summary)
                    }
                }
                .padding(.top, 4)
            }

            Divider()
                .padding(.vertical, 2)

            DisclosureGroup(isExpanded: $isShowingTroubleshootingCheckIns) {
                VStack(alignment: .leading, spacing: 8) {
                    if appModel.menuBarDayCheckIns.isEmpty {
                        Text("No check-ins recorded in this day window.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.menuBarDayCheckIns) { checkIn in
                            troubleshootingCheckInRow(checkIn)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Check-ins (\(appModel.menuBarDayCheckIns.count))")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
    }

    private func projectSummaryRow(_ summary: AnalyticsProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(summary.projectName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(TempoAppModel.formattedTrackedDuration(summary.totalDuration))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            GeometryReader { geometry in
                let progress = min(max(summary.percentageOfTotal, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))

                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: max(geometry.size.width * progress, progress > 0 ? 8 : 0))
                }
            }
            .frame(height: 3)
        }
    }

    private func troubleshootingCheckInRow(_ checkIn: TimeAllocationCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TempoAppModel.formattedClockTime(checkIn.timestamp))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()

                Text(troubleshootingCheckInTitle(for: checkIn))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text("source: \(checkIn.source)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func troubleshootingCheckInTitle(for checkIn: TimeAllocationCheckIn) -> String {
        switch checkIn.kind {
        case let .project(_, name):
            return "project · \(name)"
        case let .idle(kind):
            return "idle · \(kind.rawValue)"
        }
    }

    private var summaryDateTitle: String {
        let summaryDate = appModel.menuBarDayPeriod.startDate
        if calendar.isDateInToday(summaryDate) {
            return "Today \(summaryDate.formatted(.dateTime.month(.wide).day().year()))"
        }

        return summaryDate.formatted(.dateTime.month(.wide).day().year())
    }

    private var noTrackedTimeTitle: String {
        if calendar.isDateInToday(appModel.menuBarDayPeriod.startDate) {
            return "No tracked time today"
        }

        return "No tracked time in this day"
    }

    private var noTrackedTimeDescription: String {
        if calendar.isDateInToday(appModel.menuBarDayPeriod.startDate) {
            return "Today’s breakdown, total, and work hours will appear here once you log time."
        }

        return "This day’s breakdown, total, and work hours will appear here once records exist."
    }

    private var cardBackground: some ShapeStyle {
        AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }
}
