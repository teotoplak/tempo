import SwiftUI

struct MenuBarRootView: View {
    @Bindable var appModel: TempoAppModel
    @State private var isShowingSettings = false
    @State private var isShowingTroubleshootingCheckIns = false
    @Environment(\.calendar) private var calendar
    @Environment(\.openWindow) private var openWindow

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
                            title: "Current check-in",
                            primary: appModel.menuBarCurrentActivityPrimaryStatus(),
                            secondary: appModel.menuBarCurrentActivitySecondaryStatus(at: context.date),
                            accent: Color(red: 0.10, green: 0.47, blue: 0.67),
                            icon: "checkmark.circle.fill"
                        )
                    }
                }

                dailySummarySection

                primaryActionButton

                if !appModel.isSilenced {
                    doneForDayActionButton
                }

                LazyVGrid(columns: actionColumns, spacing: 10) {
                    secondaryActionButton(title: "Analytics", icon: "chart.xyaxis.line") {
                        appModel.recordAnalyticsWindowEvent(
                            "menu-bar-button-clicked",
                            metadata: ["source": "menu-bar"]
                        )
                        appModel.prepareWeeklyAnalyticsPresentation()
                        presentDetachedPrompt {
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            openWindow(id: AppSceneID.analyticsWindow.rawValue)
                            DispatchQueue.main.async {
                                appModel.bringAnalyticsWindowToFront(reason: "menu-bar-open-request-immediate")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                appModel.bringAnalyticsWindowToFront(reason: "menu-bar-open-request-deferred")
                            }
                        }
                    }

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
                            try? appModel.endSilenceMode(trigger: "menu-bar")
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

                troubleshootingCheckInsSection
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
        // MenuBarExtra(.window) on macOS 26 (Tahoe) does not honor a ScrollView's
        // idealHeight when sizing the popover window, so the window collapses to a
        // near-zero-height blank pill. Pin a concrete height so the window always
        // opens at full size; the ScrollView handles any overflow.
        .frame(width: 320, height: 480)
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
                appModel.checkInNow(trigger: "menu-bar")
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
            try? appModel.silenceForRestOfDay(trigger: "menu-bar")
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
                Button("Previous day", systemImage: "chevron.left") {
                    appModel.showPreviousMenuBarDay()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .buttonStyle(.plain)

                Text(summaryDateTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)

                Button("Next day", systemImage: "chevron.right") {
                    appModel.showNextMenuBarDay()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
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
                noTrackedTimeEmptyState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appModel.menuBarDayProjectSummaries, id: \.id) { summary in
                        projectSummaryRow(summary)
                    }
                }
                .padding(.top, 4)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
    }

    private var noTrackedTimeEmptyState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(noTrackedTimeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(noTrackedTimeDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var troubleshootingCheckInsSection: some View {
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
        case .untracked:
            return "untracked"
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
