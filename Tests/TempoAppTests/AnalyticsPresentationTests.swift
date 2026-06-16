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

    func testAnalyticsViewContainsRangeAwareOverviewCopy() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("Time Statistics"))
        XCTAssertTrue(source.contains("selectedRangeTitle"))
        XCTAssertTrue(source.contains("availablePresentationRanges: [AnalyticsRange] = [.week, .month]"))
        XCTAssertTrue(source.contains("Picker(\"Range\", selection: selectedRangeBinding)"))
        XCTAssertTrue(source.contains("Daily breakdown"))
        XCTAssertTrue(source.contains("Daily timeline"))
        XCTAssertTrue(source.contains("Chronological check-in intervals"))
        XCTAssertTrue(source.contains("share"))
    }

    func testAnalyticsViewAddsArrowKeyPeriodNavigation() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("keyboardShortcut: .leftArrow"))
        XCTAssertTrue(source.contains("keyboardShortcut: .rightArrow"))
        XCTAssertTrue(source.contains("button.keyboardShortcut(keyboardShortcut, modifiers: [])"))
    }

    func testAnalyticsViewKeepsShareCompactWithTimeColumn() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("FloatingPointFormatStyle<Double>.Percent.percent"))
        XCTAssertTrue(source.contains("weeklyShareAllocationList(limit: 5)"))
        XCTAssertTrue(source.contains("Text(\"Time\")"))
    }

    func testAnalyticsViewContainsRangeAwareChartEmptyStates() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("No project time this \\(periodNoun)"))
        XCTAssertTrue(source.contains("No \\(periodAdjective) allocation yet"))
    }

    func testAnalyticsViewPlacesProjectAllocationAtBottom() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("Project allocation"))
        XCTAssertTrue(source.contains("Detailed totals for the selected \\(periodNoun)"))
        XCTAssertTrue(source.contains("No tracked time in this period"))

        let timelineRange = try XCTUnwrap(source.range(of: "chronologicalDailyBreakdownCard"))
        let allocationRange = try XCTUnwrap(source.range(of: "allocationSection"))
        XCTAssertLessThan(timelineRange.lowerBound, allocationRange.lowerBound)
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
