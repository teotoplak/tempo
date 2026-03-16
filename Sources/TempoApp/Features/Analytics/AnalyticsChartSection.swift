import Charts
import SwiftUI

struct AnalyticsChartSection: View {
    let summaries: [AnalyticsProjectSummary]

    var body: some View {
        Chart(summaries) { summary in
            SectorMark(
                angle: .value("Duration", summary.totalDuration),
                innerRadius: .ratio(0.58),
                angularInset: 2
            )
            .foregroundStyle(by: .value("Project", summary.projectName))
        }
        .chartLegend(.visible)
        .frame(height: 260)
    }
}
