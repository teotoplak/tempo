import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CheckInProjectSelectionTests: XCTestCase {
    @MainActor
    func testRecentProjectsSortFirst() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        let alpha = ProjectRecord(name: "Alpha", sortOrder: 0)
        let beta = ProjectRecord(name: "Beta", sortOrder: 1)
        let gamma = ProjectRecord(name: "Gamma", sortOrder: 2)
        appModel.modelContext.insert(alpha)
        appModel.modelContext.insert(beta)
        appModel.modelContext.insert(gamma)
        appModel.modelContext.insert(TimeEntryRecord(
            project: beta,
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            source: "manual"
        ))
        appModel.modelContext.insert(TimeEntryRecord(
            project: alpha,
            startAt: Date(timeIntervalSince1970: 300),
            endAt: Date(timeIntervalSince1970: 400),
            source: "manual"
        ))
        try appModel.modelContext.save()

        XCTAssertEqual(appModel.recentPromptProjects.map(\.name), ["Alpha", "Beta", "Gamma"])
    }

    @MainActor
    func testPromptFilteringIsCaseInsensitive() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        appModel.modelContext.insert(ProjectRecord(name: "Client Work", sortOrder: 0))
        appModel.modelContext.insert(ProjectRecord(name: "Deep Focus", sortOrder: 1))
        try appModel.modelContext.save()

        appModel.promptSearchText = "client"

        XCTAssertEqual(appModel.filteredPromptProjects.map(\.name), ["Client Work"])
    }

    @MainActor
    func testCanCreatePromptProjectOnlyForUnmatchedTrimmedName() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        appModel.modelContext.insert(ProjectRecord(name: "Tempo", sortOrder: 0))
        try appModel.modelContext.save()

        XCTAssertTrue(appModel.canCreatePromptProject(named: "  Deep Work  "))
        XCTAssertFalse(appModel.canCreatePromptProject(named: "Tempo"))
        XCTAssertFalse(appModel.canCreatePromptProject(named: "   "))
    }
}
