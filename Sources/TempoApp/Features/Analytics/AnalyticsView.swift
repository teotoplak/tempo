import SwiftUI

struct AnalyticsView: View {
    @Bindable var appModel: TempoAppModel
    // PercentFormatStyle coverage is locked by source-level tests for this view.
    private let percentStyle = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0))
    private let timelineTickHours = [0, 6, 12, 18, 24]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summaryCards
                if appModel.selectedAnalyticsRange == .day {
                    dailyBreakdownSection
                }
                allocationSection
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analytics")
                .font(.largeTitle.weight(.semibold))

            HStack(alignment: .center, spacing: 16) {
                Picker("Analytics range", selection: analyticsRangeBinding) {
                    Text("Daily").tag(AnalyticsRange.day)
                    Text("Weekly").tag(AnalyticsRange.week)
                    Text("Monthly").tag(AnalyticsRange.month)
                    Text("Yearly").tag(AnalyticsRange.year)
                }
                .pickerStyle(.segmented)

                Button("Export CSV") {
                    appModel.exportAnalyticsCSV()
                }
                .disabled(appModel.analyticsProjectSummaries.isEmpty && appModel.analyticsTotalDuration == 0)

                Spacer()
            }

            Text(appModel.analyticsPeriod.label)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let statusMessage = appModel.analyticsExportStatusMessage {
                Text("CSV exported")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                if statusMessage != "CSV exported" {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = appModel.analyticsExportErrorMessage {
                Text("Export failed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryCards: some View {
        HStack(alignment: .top, spacing: 16) {
            analyticsCard(title: "Total tracked", value: appModel.analyticsTotalDurationText)
            analyticsCard(title: "Top project", value: appModel.analyticsTopProjectSummaryText)
            if appModel.selectedAnalyticsRange == .day {
                analyticsCard(title: "Started working", value: appModel.analyticsFirstEntryStartText)
            }
        }
    }

    private var dailyBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily timeline")
                .font(.title2.weight(.semibold))

            if appModel.analyticsTimelineIntervals.isEmpty {
                ContentUnavailableView(
                    "No recorded intervals today",
                    systemImage: "timeline.selection",
                    description: Text("Your first input time and work timeline will appear here once records exist.")
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    timelineTrack

                    VStack(spacing: 8) {
                        ForEach(appModel.analyticsTimelineIntervals) { interval in
                            HStack(spacing: 12) {
                                Text("\(TempoAppModel.formattedClockTime(interval.startDate)) - \(TempoAppModel.formattedClockTime(interval.endDate))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 110, alignment: .leading)

                                Text(interval.projectName)
                                    .font(.subheadline.weight(.medium))

                                Spacer()

                                Text(TempoAppModel.formattedTrackedDuration(interval.endDate.timeIntervalSince(interval.startDate)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project allocation")
                .font(.title2.weight(.semibold))

            if appModel.analyticsProjectSummaries.isEmpty {
                ContentUnavailableView(
                    "No tracked time in this period",
                    systemImage: "chart.pie",
                    description: Text("Change the selected range or log time to populate the report.")
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(appModel.analyticsProjectSummaries, id: \.id) { summary in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.projectName)
                                    .font(.headline)
                                Text("\(summary.entryCount) entries")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private var analyticsRangeBinding: Binding<AnalyticsRange> {
        Binding(
            get: { appModel.selectedAnalyticsRange },
            set: { appModel.selectAnalyticsRange($0) }
        )
    }

    private var timelineTrack: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.tertiary.opacity(0.35))
                        .frame(height: 24)

                    ForEach(appModel.analyticsTimelineIntervals) { interval in
                        let startFraction = timelineFraction(for: interval.startDate)
                        let endFraction = timelineFraction(for: interval.endDate)
                        let intervalWidth = max((endFraction - startFraction) * width, 4)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(.tint)
                            .frame(width: intervalWidth, height: 24)
                            .offset(x: startFraction * width)
                    }
                }
            }
            .frame(height: 24)

            HStack {
                ForEach(timelineTickHours, id: \.self) { hour in
                    Text(timelineLabel(for: hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if hour != timelineTickHours.last {
                        Spacer()
                    }
                }
            }
        }
    }

    private func timelineFraction(for date: Date) -> CGFloat {
        let dayDuration = appModel.analyticsPeriod.endDate.timeIntervalSince(appModel.analyticsPeriod.startDate)
        guard dayDuration > 0 else {
            return 0
        }

        let offset = date.timeIntervalSince(appModel.analyticsPeriod.startDate)
        let fraction = offset / dayDuration
        return CGFloat(min(max(fraction, 0), 1))
    }

    private func timelineLabel(for hour: Int) -> String {
        if hour == 24 {
            return "24:00"
        }

        let date = appModel.analyticsPeriod.startDate.addingTimeInterval(TimeInterval(hour * 3_600))
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func analyticsCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }
}
