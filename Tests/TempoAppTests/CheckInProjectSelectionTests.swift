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

    @MainActor
    func testVisiblePromptProjectsLimitSelectionToVisibleRows() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        let projects = [
            ProjectRecord(name: "Alpha", sortOrder: 0),
            ProjectRecord(name: "Beta", sortOrder: 1),
            ProjectRecord(name: "Gamma", sortOrder: 2),
            ProjectRecord(name: "Delta", sortOrder: 3),
            ProjectRecord(name: "Epsilon", sortOrder: 4),
        ]

        for project in projects {
            appModel.modelContext.insert(project)
        }
        try appModel.modelContext.save()

        appModel.updatePromptSearchText("")
        XCTAssertEqual(appModel.visiblePromptProjects.map(\.name), ["Alpha", "Beta", "Gamma", "Delta"])
        XCTAssertEqual(appModel.selectedPromptProjectID, projects[0].id)

        appModel.movePromptSelection(by: 1)
        XCTAssertEqual(appModel.selectedPromptProjectID, projects[1].id)

        appModel.movePromptSelection(by: 10)
        XCTAssertEqual(appModel.selectedPromptProjectID, projects[3].id)

        appModel.movePromptSelection(by: -10)
        XCTAssertEqual(appModel.selectedPromptProjectID, projects[0].id)
    }

    @MainActor
    func testMovePromptSelectionIncludesCreateActionAtBottom() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        let linkedin = ProjectRecord(name: "linkedin", sortOrder: 0)
        appModel.modelContext.insert(linkedin)
        try appModel.modelContext.save()

        appModel.updatePromptSearchText("link")

        XCTAssertEqual(appModel.selectedPromptProjectID, linkedin.id)
        XCTAssertFalse(appModel.isCreatePromptProjectSelected)

        appModel.movePromptSelection(by: 1)

        XCTAssertTrue(appModel.isCreatePromptProjectSelected)
        XCTAssertNil(appModel.selectedPromptProjectID)

        appModel.movePromptSelection(by: -1)

        XCTAssertEqual(appModel.selectedPromptProjectID, linkedin.id)
        XCTAssertFalse(appModel.isCreatePromptProjectSelected)
    }

    @MainActor
    func testUpdatePromptSearchTextDefaultsToCreateActionWhenNoProjectsMatch() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        appModel.modelContext.insert(ProjectRecord(name: "Alpha", sortOrder: 0))
        try appModel.modelContext.save()

        appModel.updatePromptSearchText("link")

        XCTAssertTrue(appModel.hasVisiblePromptCreateAction)
        XCTAssertTrue(appModel.isCreatePromptProjectSelected)
        XCTAssertNil(appModel.selectedPromptProjectID)
    }

    @MainActor
    func testUpdatePromptSearchTextKeepsSelectionWithinVisibleMatches() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        let alpha = ProjectRecord(name: "Alpha", sortOrder: 0)
        let alpine = ProjectRecord(name: "Alpine", sortOrder: 1)
        let altitude = ProjectRecord(name: "Altitude", sortOrder: 2)
        let algae = ProjectRecord(name: "Algae", sortOrder: 3)
        let almanac = ProjectRecord(name: "Almanac", sortOrder: 4)

        [alpha, alpine, altitude, algae, almanac].forEach(appModel.modelContext.insert)
        try appModel.modelContext.save()

        appModel.updatePromptSearchText("al")

        XCTAssertEqual(appModel.visiblePromptProjects.map(\.name), ["Alpha", "Alpine", "Altitude", "Algae"])
        XCTAssertEqual(appModel.selectedPromptProjectID, alpha.id)
    }

    @MainActor
    func testUpdatePromptSearchTextDefaultsToExistingProjectBeforeCreateAction() throws {
        let container = TempoModelContainer.inMemory()
        let appModel = TempoAppModel(modelContainer: container)
        let linkedin = ProjectRecord(name: "linkedin", sortOrder: 0)
        appModel.modelContext.insert(linkedin)
        try appModel.modelContext.save()

        appModel.updatePromptSearchText("link")

        XCTAssertEqual(appModel.selectedPromptProjectID, linkedin.id)
        XCTAssertTrue(appModel.hasVisiblePromptCreateAction)
        XCTAssertFalse(appModel.isCreatePromptProjectSelected)
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
