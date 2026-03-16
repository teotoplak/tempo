import Foundation
import XCTest

final class AnalyticsPresentationTests: XCTestCase {
    func testAppWindowShellUsesAnalyticsView() throws {
        let source = try sourceFile("Sources/TempoApp/Views/AppWindowShellView.swift")

        XCTAssertTrue(source.contains("AnalyticsView(appModel: appModel)"))
    }

    func testAnalyticsViewContainsPeriodPickerLabels() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("\"Daily\""))
        XCTAssertTrue(source.contains("\"Weekly\""))
        XCTAssertTrue(source.contains("\"Monthly\""))
        XCTAssertTrue(source.contains("\"Yearly\""))
    }

    func testAnalyticsViewContainsProjectAllocationSection() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("Project allocation"))
        XCTAssertTrue(source.contains("PercentFormatStyle"))
        XCTAssertTrue(source.contains("entryCount"))
    }

    func testAnalyticsViewDefinesEmptyStateCopy() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("No tracked time in this period"))
    }

    func testAnalyticsViewContainsExportCSVAction() throws {
        let source = try sourceFile("Sources/TempoApp/Features/Analytics/AnalyticsView.swift")

        XCTAssertTrue(source.contains("Export CSV"))
        XCTAssertTrue(source.contains("CSV exported"))
        XCTAssertTrue(source.contains("Export failed"))
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
