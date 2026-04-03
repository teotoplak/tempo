import AppKit
import Charts
import SwiftUI

struct AnalyticsView: View {
    @Bindable var appModel: TempoAppModel
    @Environment(\.calendar) private var calendar
    @State private var resolvedWindowNumber: Int?

    private let percentStyle = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0))
    private let projectPalette: [Color] = [
        Color(red: 0.12, green: 0.46, blue: 0.78),
        Color(red: 0.90, green: 0.41, blue: 0.24),
        Color(red: 0.12, green: 0.62, blue: 0.50),
        Color(red: 0.78, green: 0.26, blue: 0.43),
        Color(red: 0.69, green: 0.52, blue: 0.14),
        Color(red: 0.38, green: 0.35, blue: 0.78),
        Color(red: 0.16, green: 0.57, blue: 0.67),
        Color(red: 0.57, green: 0.41, blue: 0.24),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                weekNavigator
                summaryCards
                weeklyVisualsSection
                allocationSection
            }
            .padding(28)
        }
        .background(backgroundGradient)
        .background(
            AnalyticsWindowResolver { window in
                handleResolvedWindow(window)
            }
        )
        .onAppear {
            appModel.recordAnalyticsWindowEvent(
                "window-appeared",
                metadata: ["dayCount": "\(weekDaySummaries.count)"]
            )
            if appModel.selectedAnalyticsRange != .week {
                appModel.prepareWeeklyAnalyticsPresentation(resetReferenceDate: false)
            }
        }
        .onDisappear {
            appModel.analyticsWindowDidDisappear()
        }
    }

    private func handleResolvedWindow(_ window: NSWindow?) {
        guard let window else {
            return
        }

        guard resolvedWindowNumber != window.windowNumber else {
            return
        }

        resolvedWindowNumber = window.windowNumber
        appModel.registerAnalyticsWindow(window)
        appModel.recordAnalyticsWindowEvent(
            "window-resolved",
            metadata: [
                "windowNumber": "\(window.windowNumber)",
                "frame": traceRect(window.frame),
                "isVisible": "\(window.isVisible)",
                "isKeyWindow": "\(window.isKeyWindow)",
                "isMainWindow": "\(window.isMainWindow)",
                "isMiniaturized": "\(window.isMiniaturized)"
            ]
        )

        DispatchQueue.main.async {
            appModel.bringAnalyticsWindowToFront(reason: "window-resolved")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Time Statistics")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))

                Text("Weekly allocation generated from your check-ins. Bars show each day, while the pie summarizes the whole week.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                Button("Export CSV") {
                    appModel.exportAnalyticsCSV()
                }
                .buttonStyle(.borderedProminent)

                if let statusMessage = appModel.analyticsExportStatusMessage {
                    Text(statusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.12, green: 0.50, blue: 0.28))
                }

                if let errorMessage = appModel.analyticsExportErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.74, green: 0.22, blue: 0.18))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: 18) {
            navigationButton(systemImage: "chevron.left") {
                appModel.showPreviousAnalyticsPeriod()
            }

            VStack(spacing: 4) {
                Text("Weekly Overview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(appModel.analyticsPeriod.label)
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)

            navigationButton(systemImage: "chevron.right", isEnabled: appModel.canShowNextAnalyticsPeriod) {
                appModel.showNextAnalyticsPeriod()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        }
    }

    private var summaryCards: some View {
        HStack(alignment: .top, spacing: 16) {
            analyticsCard(title: "Worked", value: TempoAppModel.formattedTrackedDuration(workedDuration), detail: "Project time for the selected week")
            analyticsCard(title: "Top project", value: topProjectCardText, detail: workedProjectSummaries.first.map { $0.percentageOfTotal.formatted(percentStyle) } ?? "No tracked time")
            analyticsCard(title: "Active days", value: "\(activeDayCount)/\(weekDaySummaries.count)", detail: idleDuration > 0 ? "Idle recorded: \(TempoAppModel.formattedTrackedDuration(idleDuration))" : "No idle time recorded")
        }
    }

    private var weeklyVisualsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                dailyStackedBarsCard
                weeklyPieChartCard
            }

            VStack(spacing: 20) {
                dailyStackedBarsCard
                weeklyPieChartCard
            }
        }
    }

    private var dailyStackedBarsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(
                title: "Daily breakdown",
                subtitle: "Stacked hours per project for each day in the week"
            )

            if workedProjectSummaries.isEmpty {
                ContentUnavailableView(
                    "No project time this week",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Check-ins that resolve into project time will appear here automatically.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                dailyBreakdownChart
                weekTotalsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(cardBackground)
    }

    private var dailyBreakdownChart: some View {
        Chart {
            ForEach(weekDaySummaries) { day in
                ForEach(day.projectSegments) { segment in
                    dailyBreakdownMark(day: day, segment: segment)
                }
            }
        }
        .chartYAxis { dailyBreakdownYAxis }
        .chartXAxis { dailyBreakdownXAxis }
        .chartYScale(domain: 0...maxWorkedDayHours)
        .chartPlotStyle { plot in
            plot
                .frame(maxWidth: .infinity, minHeight: 320)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var weeklyPieChartCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(
                title: "Weekly share",
                subtitle: "Project mix for the full week"
            )

            if workedProjectSummaries.isEmpty {
                ContentUnavailableView(
                    "No weekly allocation yet",
                    systemImage: "chart.pie",
                    description: Text("Once a week contains project time, the share chart appears here.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                weeklyShareChart

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workedProjectSummaries.prefix(5), id: \.id) { summary in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(color(for: summary.projectID, name: summary.projectName))
                                .frame(width: 10, height: 10)

                            Text(summary.projectName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)

                            Spacer()

                            Text(summary.percentageOfTotal.formatted(percentStyle))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(cardBackground)
    }

    private var weeklyShareChart: some View {
        Chart(workedProjectSummaries, id: \.id) { summary in
            SectorMark(
                angle: .value("Worked", summary.totalDuration),
                innerRadius: .ratio(0.56),
                angularInset: 2
            )
            .foregroundStyle(color(for: summary.projectID, name: summary.projectName))
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                    let plotFrame = geometry[frame]

                    VStack(spacing: 4) {
                        Text("Worked")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(TempoAppModel.formattedTrackedDuration(workedDuration))
                            .font(.title3.weight(.semibold))
                    }
                    .position(x: plotFrame.midX, y: plotFrame.midY)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(
                title: "Project allocation",
                subtitle: "Detailed totals for the selected week"
            )

            if workedProjectSummaries.isEmpty {
                ContentUnavailableView(
                    "No tracked time in this period",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Change weeks or log time to populate the report.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 12) {
                    ForEach(workedProjectSummaries, id: \.id) { summary in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(color(for: summary.projectID, name: summary.projectName))
                                        .frame(width: 10, height: 10)

                                    Text(summary.projectName)
                                        .font(.headline)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(TempoAppModel.formattedTrackedDuration(summary.totalDuration))
                                        .font(.headline.monospacedDigit())
                                    Text(summary.percentageOfTotal.formatted(percentStyle))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            GeometryReader { geometry in
                                let progress = min(max(summary.percentageOfTotal, 0), 1)

                                ZStack(alignment: .leading) {
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.08))

                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    color(for: summary.projectID, name: summary.projectName).opacity(0.85),
                                                    color(for: summary.projectID, name: summary.projectName)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(geometry.size.width * progress, progress > 0 ? 10 : 0))
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                        )
                    }
                }
            }
        }
        .padding(22)
        .background(cardBackground)
    }

    private var workedProjectSummaries: [AnalyticsProjectSummary] {
        let workedSummaries = appModel.analyticsProjectSummaries.filter { $0.projectID != nil }
        let totalWorkedDuration = workedSummaries.reduce(into: 0.0) { total, summary in
            total += summary.totalDuration
        }

        return workedSummaries.map { summary in
            AnalyticsProjectSummary(
                projectID: summary.projectID,
                projectName: summary.projectName,
                totalDuration: summary.totalDuration,
                percentageOfTotal: totalWorkedDuration > 0 ? summary.totalDuration / totalWorkedDuration : 0,
                entryCount: summary.entryCount
            )
        }
    }

    private var workedDuration: TimeInterval {
        workedProjectSummaries.reduce(into: 0.0) { total, summary in
            total += summary.totalDuration
        }
    }

    private var idleDuration: TimeInterval {
        appModel.analyticsProjectSummaries
            .filter { $0.projectID == nil }
            .reduce(into: 0.0) { total, summary in
                total += summary.totalDuration
            }
    }

    private var activeDayCount: Int {
        weekDaySummaries.filter { $0.workedDuration > 0 }.count
    }

    private var topProjectCardText: String {
        guard let topProject = workedProjectSummaries.first else {
            return "No tracked time"
        }

        return topProject.projectName
    }

    private var weekDaySummaries: [AnalyticsWeekDaySummary] {
        let orderedProjectIDs = workedProjectSummaries.enumerated().reduce(into: [UUID: Int]()) { result, entry in
            if let projectID = entry.element.projectID {
                result[projectID] = entry.offset
            }
        }

        var groupedDurations: [Date: [UUID: AnalyticsWeekProjectDuration]] = [:]

        for interval in appModel.analyticsAllocatedIntervals {
            guard case let .project(projectID, projectName) = interval.bucket else {
                continue
            }

            let dayStart = dayStartDate(containing: interval.startDate)
            let segment = groupedDurations[dayStart]?[projectID] ?? AnalyticsWeekProjectDuration(
                dayStartDate: dayStart,
                projectID: projectID,
                projectName: projectName,
                duration: 0
            )

            groupedDurations[dayStart, default: [:]][projectID] = AnalyticsWeekProjectDuration(
                dayStartDate: dayStart,
                projectID: projectID,
                projectName: projectName,
                duration: segment.duration + interval.duration
            )
        }

        return weekStartDates.map { dayStart in
            let displayDate = calendar.date(byAdding: .hour, value: -appModel.settings.analyticsDayCutoffHour, to: dayStart) ?? dayStart
            let segments = groupedDurations[dayStart, default: [:]]
                .values
                .sorted { lhs, rhs in
                    let lhsOrder = orderedProjectIDs[lhs.projectID] ?? .max
                    let rhsOrder = orderedProjectIDs[rhs.projectID] ?? .max
                    if lhsOrder != rhsOrder {
                        return lhsOrder < rhsOrder
                    }

                    return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
                }
            let workedDuration = segments.reduce(into: 0.0) { total, segment in
                total += segment.duration
            }

            return AnalyticsWeekDaySummary(
                dayStartDate: dayStart,
                displayDate: displayDate,
                weekdayLabel: displayDate.formatted(.dateTime.weekday(.abbreviated)),
                dateLabel: displayDate.formatted(.dateTime.day()),
                workedDuration: workedDuration,
                projectSegments: segments
            )
        }
    }

    private var weekStartDates: [Date] {
        var dates: [Date] = []
        var currentDate = appModel.analyticsPeriod.startDate

        while currentDate < appModel.analyticsPeriod.endDate {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? appModel.analyticsPeriod.endDate
        }

        return dates
    }

    private var maxWorkedDayHours: Double {
        let rawHours = weekDaySummaries
            .map { $0.workedDuration / 3_600 }
            .max() ?? 0
        let roundedHours = ceil(max(rawHours, 1) / 2) * 2
        return max(roundedHours, 2)
    }

    private var weekTotalsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(weekDaySummaries) { day in
                VStack(spacing: 4) {
                    Text(day.weekdayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(TempoAppModel.formattedTrackedDuration(day.workedDuration))
                        .font(.caption.monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                )
            }
        }
    }

    @ChartContentBuilder
    private func dailyBreakdownMark(day: AnalyticsWeekDaySummary, segment: AnalyticsWeekProjectDuration) -> some ChartContent {
        BarMark(
            x: .value("Day", day.displayDate, unit: .day),
            y: .value("Hours", segment.duration / 3_600),
            stacking: .standard
        )
        .foregroundStyle(color(for: segment.projectID, name: segment.projectName))
        .cornerRadius(8)
    }

    private var dailyBreakdownYAxis: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.black.opacity(0.12))
            AxisValueLabel {
                if let hourValue = value.as(Double.self) {
                    Text("\(Int(hourValue.rounded()))h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dailyBreakdownXAxis: some AxisContent {
        AxisMarks(values: weekDaySummaries.map(\.displayDate)) { value in
            AxisGridLine()
                .foregroundStyle(.clear)
            AxisTick()
                .foregroundStyle(Color.black.opacity(0.08))
            AxisValueLabel {
                if let date = value.as(Date.self),
                   let day = weekDaySummaries.first(where: { calendar.isDate($0.displayDate, inSameDayAs: date) }) {
                    VStack(spacing: 2) {
                        Text(day.weekdayLabel)
                        Text(day.dateLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dayStartDate(containing date: Date) -> Date {
        let dayOffset = calendar.dateComponents([.day], from: appModel.analyticsPeriod.startDate, to: date).day ?? 0
        let clampedOffset = max(dayOffset, 0)
        return calendar.date(byAdding: .day, value: clampedOffset, to: appModel.analyticsPeriod.startDate) ?? appModel.analyticsPeriod.startDate
    }

    private func navigationButton(systemImage: String, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isEnabled ? 0.86 : 0.52))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func analyticsCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func cardHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    nonisolated static func paletteIndex(for projectID: UUID?, name: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else {
            return 0
        }

        let seed = (projectID?.uuidString ?? name).unicodeScalars.reduce(into: UInt(0)) { value, scalar in
            value = (value &* 33) &+ UInt(scalar.value)
        }
        return Int(seed % UInt(paletteCount))
    }

    private func color(for projectID: UUID?, name: String) -> Color {
        projectPalette[Self.paletteIndex(for: projectID, name: name, paletteCount: projectPalette.count)]
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.95, blue: 0.90),
                Color(red: 0.93, green: 0.96, blue: 0.98),
                Color(red: 0.95, green: 0.93, blue: 0.97),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 10)
    }

    private func traceRect(_ rect: CGRect) -> String {
        "{{\(Int(rect.origin.x)), \(Int(rect.origin.y))}, {\(Int(rect.size.width)), \(Int(rect.size.height))}}"
    }
}

private struct AnalyticsWeekDaySummary: Identifiable {
    let dayStartDate: Date
    let displayDate: Date
    let weekdayLabel: String
    let dateLabel: String
    let workedDuration: TimeInterval
    let projectSegments: [AnalyticsWeekProjectDuration]

    var id: Date { dayStartDate }
}

private struct AnalyticsWeekProjectDuration: Identifiable {
    let dayStartDate: Date
    let projectID: UUID
    let projectName: String
    let duration: TimeInterval

    var id: String {
        "\(dayStartDate.timeIntervalSinceReferenceDate)-\(projectID.uuidString)"
    }
}

private struct AnalyticsWindowResolver: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}
