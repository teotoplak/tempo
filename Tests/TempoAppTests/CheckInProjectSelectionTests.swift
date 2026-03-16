import Foundation
import SwiftData
import XCTest
@testable import TempoApp

final class CheckInProjectSelectionTests: XCTestCase {
    @MainActor
    func testRecentProjectsSortUsingLatestProjectCheckIn() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        let alpha = ProjectRecord(name: "Alpha", sortOrder: 0)
        let beta = ProjectRecord(name: "Beta", sortOrder: 1)
        let gamma = ProjectRecord(name: "Gamma", sortOrder: 2)
        appModel.modelContext.insert(alpha)
        appModel.modelContext.insert(beta)
        appModel.modelContext.insert(gamma)
        appModel.modelContext.insert(projectCheckIn(project: beta, at: Date(timeIntervalSince1970: 200)))
        appModel.modelContext.insert(projectCheckIn(project: alpha, at: Date(timeIntervalSince1970: 400)))
        appModel.modelContext.insert(
            CheckInRecord(
                timestamp: Date(timeIntervalSince1970: 500),
                kind: "idle",
                source: "test",
                idleKind: TimeAllocationIdleKind.automaticThreshold.rawValue
            )
        )
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

    private func projectCheckIn(project: ProjectRecord, at date: Date) -> CheckInRecord {
        CheckInRecord(
            timestamp: date,
            kind: "project",
            source: "test",
            project: project
        )
    }
}
