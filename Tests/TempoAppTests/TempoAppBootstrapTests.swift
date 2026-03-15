import Foundation
import XCTest
@testable import TempoApp

final class TempoAppBootstrapTests: XCTestCase {
    @MainActor
    func testTempoAppModelBootstraps() throws {
        let model = TempoAppModel(modelContainer: TempoModelContainer.inMemory())

        XCTAssertEqual(model.launchState, .launching)
        XCTAssertEqual(model.settings.pollingIntervalMinutes, 25)
        XCTAssertEqual(model.settings.idleThresholdMinutes, 5)
    }

    @MainActor
    func testSilenceForRestOfDayHidesPrompt() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.schedulerStateRecord.nextCheckInAt = now
        model.isPromptOverdue = true
        model.accountableElapsedInterval = 30 * 60
        model.promptSearchText = "client"
        model.refreshCheckInPromptState()

        try model.silenceForRestOfDay()

        XCTAssertTrue(model.isSilenced)
        XCTAssertFalse(model.checkInPromptState.isPresented)
        XCTAssertEqual(model.accountableElapsedInterval, 0)
        XCTAssertEqual(model.promptSearchText, "")
    }

    @MainActor
    func testCheckInNowShowsPrompt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = TempoAppModel(
            modelContainer: TempoModelContainer.inMemory(),
            clock: FixedBootstrapClock(now: now)
        )
        model.schedulerStateRecord.lastCheckInAt = now.addingTimeInterval(-20 * 60)
        model.schedulerStateRecord.nextCheckInAt = now.addingTimeInterval(5 * 60)

        model.checkInNow()

        XCTAssertTrue(model.checkInPromptState.isPresented)
        XCTAssertTrue(model.isPromptOverdue)
        XCTAssertGreaterThanOrEqual(model.accountableElapsedInterval, 25 * 60)
    }

    func testPackageManifestStaysLocalOnly() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = rootURL.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

        XCTAssertTrue(manifest.contains("platforms: ["))
        XCTAssertTrue(manifest.contains(".executableTarget("))
        XCTAssertFalse(manifest.contains(".package(url:"))
    }

    func testMenuBarQuickActionsRemainAvailable() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuSource = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/TempoApp/Views/MenuBarRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(menuSource.contains("Open Analytics"))
        XCTAssertTrue(menuSource.contains("Settings"))
        XCTAssertTrue(menuSource.contains("Quit Tempo"))
    }
}

private struct FixedBootstrapClock: SchedulerClock {
    let now: Date
}
