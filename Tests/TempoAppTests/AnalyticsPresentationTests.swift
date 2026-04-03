import Foundation
import XCTest
@testable import TempoApp

final class AnalyticsPresentationTests: XCTestCase {
    func testAppWindowShellUsesAnalyticsView() throws {
        let source = try sourceFile("Sources/TempoApp/Views/AppWindowShellView.swift")

        XCTAssertTrue(source.contains("AnalyticsView(appModel: appModel)"))
    }

    func testTempoAppDefinesDedicatedAnalyticsWindow() throws {
        let source = try sourceFile("Sources/TempoApp/App/TempoApp.swift")

        XCTAssertTrue(source.contains("Window(\"Time Statistics\", id: AppSceneID.analyticsWindow.rawValue)"))
    }

    func testAnalyticsViewContainsWeeklyOverviewCopy() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("Time Statistics"))
        XCTAssertTrue(source.contains("Weekly Overview"))
        XCTAssertTrue(source.contains("Daily breakdown"))
        XCTAssertTrue(source.contains("Weekly share"))
    }

    func testAnalyticsViewContainsProjectAllocationSection() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("Project allocation"))
        XCTAssertTrue(source.contains("FloatingPointFormatStyle<Double>.Percent.percent"))
        XCTAssertTrue(source.contains("Detailed totals for the selected week"))
    }

    func testAnalyticsViewContainsWeeklyChartEmptyStates() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("No project time this week"))
        XCTAssertTrue(source.contains("No weekly allocation yet"))
    }

    func testAnalyticsViewDefinesEmptyStateCopy() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("No tracked time in this period"))
    }

    func testAnalyticsViewContainsExportCSVAction() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("Export CSV"))
        XCTAssertTrue(source.contains("analyticsExportStatusMessage"))
        XCTAssertTrue(source.contains("analyticsExportErrorMessage"))
    }

    func testAnalyticsPaletteIndexHandlesLongProjectNames() {
        let longName = String(repeating: "very-long-project-name-", count: 512)

        let firstIndex = AnalyticsView.paletteIndex(for: nil, name: longName, paletteCount: 8)
        let secondIndex = AnalyticsView.paletteIndex(for: nil, name: longName, paletteCount: 8)

        XCTAssertEqual(firstIndex, secondIndex)
        XCTAssertGreaterThanOrEqual(firstIndex, 0)
        XCTAssertLessThan(firstIndex, 8)
    }

    private func sourceFile(_ path: String) throws -> String {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: rootURL.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
