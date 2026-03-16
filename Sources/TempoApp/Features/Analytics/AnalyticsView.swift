import SwiftUI

struct AnalyticsView: View {
    @Bindable var appModel: TempoAppModel
    // PercentFormatStyle coverage is locked by source-level tests for this view.
    private let percentStyle = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                summaryCards
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
                AnalyticsChartSection(summaries: appModel.analyticsProjectSummaries)

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
