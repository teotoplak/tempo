import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class PersistenceModelTests: XCTestCase {
    @MainActor
    func testDefaultSettingsValues() throws {
        let appModel = TempoAppModel(modelContainer: TempoModelContainer.inMemory())

        XCTAssertEqual(appModel.settings.pollingIntervalMinutes, 25)
        XCTAssertEqual(appModel.settings.idleThresholdMinutes, 5)
        XCTAssertEqual(appModel.settings.delayPresetMinutes, [15, 30])
    }

    @MainActor
    func testProjectRenamePersists() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)

        try appModel.createProject(named: "Client Work")

        let fetch = FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        let project = try XCTUnwrap(appModel.modelContext.fetch(fetch).first)

        try appModel.renameProject(project, to: "Deep Work")

        let renamed = try XCTUnwrap(appModel.modelContext.fetch(fetch).first)
        XCTAssertEqual(renamed.name, "Deep Work")
    }
}
