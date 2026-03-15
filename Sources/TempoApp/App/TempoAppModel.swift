import AppKit
import Foundation
import Observation
import SwiftData

protocol ProjectStore: AnyObject {}
protocol SettingsStore: AnyObject {}
protocol SchedulerStore: AnyObject {}

struct CheckInPromptState: Equatable {
    var isPresented: Bool
    var elapsedDuration: TimeInterval
    var isOverdue: Bool
    var promptTitle: String
    var supportingSubtitle: String

    static let hidden = CheckInPromptState(
        isPresented: false,
        elapsedDuration: 0,
        isOverdue: false,
        promptTitle: "What are you currently doing",
        supportingSubtitle: "Elapsed 0 min"
    )
}

@MainActor
@Observable
final class TempoAppModel {
    enum WindowSection: String, CaseIterable, Identifiable {
        case projects
        case analytics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .projects:
                return "Projects"
            case .analytics:
                return "Analytics"
            }
        }
    }

    enum LaunchState: String {
        case launching
        case ready
    }

    let modelContainer: ModelContainer
    let modelContext: ModelContext

    var selectedWindow: WindowSection = .projects
    var launchState: LaunchState = .launching
    var projectStore: (any ProjectStore)?
    var settingsStore: (any SettingsStore)?
    var schedulerStore: (any SchedulerStore)?

    var settings: AppSettingsRecord
    var schedulerStateRecord: SchedulerStateRecord
    var nextCheckInAt: Date?
    var isPromptOverdue = false
    var accountableElapsedInterval: TimeInterval = 0
    var checkInPromptState = CheckInPromptState.hidden
    var promptSearchText = ""

    private let clock: any SchedulerClock
    private let scheduler: PollingScheduler
    private let schedulerStateStore: SchedulerStateStore
    private var hasHandledInitialLaunch = false
    private var wakeObserver: NSObjectProtocol?
    private var checkInPromptWindowController: CheckInPromptWindowController?

    init(
        modelContainer: ModelContainer? = nil,
        clock: any SchedulerClock = SystemSchedulerClock()
    ) {
        let resolvedContainer = modelContainer ?? TempoModelContainer.live()
        self.modelContainer = resolvedContainer
        self.modelContext = ModelContext(resolvedContainer)
        self.clock = clock
        self.scheduler = PollingScheduler(clock: clock)

        let settingsFetch = FetchDescriptor<AppSettingsRecord>()
        let schedulerFetch = FetchDescriptor<SchedulerStateRecord>()

        if let existingSettings = try? self.modelContext.fetch(settingsFetch).first {
            self.settings = existingSettings
        } else {
            let createdSettings = AppSettingsRecord()
            self.modelContext.insert(createdSettings)
            self.settings = createdSettings
        }

        if let existingState = try? self.modelContext.fetch(schedulerFetch).first {
            self.schedulerStateRecord = existingState
        } else {
            let createdState = SchedulerStateRecord()
            self.modelContext.insert(createdState)
            self.schedulerStateRecord = createdState
        }

        if self.modelContext.hasChanges {
            try? self.modelContext.save()
        }

        let schedulerStateStore = SchedulerStateStore(modelContext: self.modelContext)
        self.schedulerStateStore = schedulerStateStore
        self.settingsStore = LocalSettingsStore(record: self.settings)
        self.schedulerStore = schedulerStateStore
        self.projectStore = LocalProjectStore(modelContext: self.modelContext)

        apply(snapshot: scheduler.snapshot(for: self.schedulerStateRecord, settings: self.settings, eventDate: clock.now))
        refreshCheckInPromptState()
    }

    func performInitialLaunchIfNeeded() {
        guard !hasHandledInitialLaunch else {
            return
        }

        hasHandledInitialLaunch = true
        observeWorkspaceWake()
        handleSchedulerTransition(eventDate: clock.now)
    }

    func handleSceneActivation() {
        handleSchedulerTransition(eventDate: clock.now)
    }

    func handleAppWake() {
        handleSchedulerTransition(eventDate: clock.now)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func attachCheckInPromptWindowController(_ controller: CheckInPromptWindowController) {
        checkInPromptWindowController = controller
        controller.bind(appModel: self)
        controller.update(with: checkInPromptState)
    }

    func refreshCheckInPromptState() {
        let shouldPresent = isPromptOverdue
        checkInPromptState = CheckInPromptState(
            isPresented: shouldPresent,
            elapsedDuration: accountableElapsedInterval,
            isOverdue: isPromptOverdue,
            promptTitle: "What are you currently doing",
            supportingSubtitle: Self.supportingSubtitle(
                elapsedDuration: accountableElapsedInterval,
                isOverdue: isPromptOverdue
            )
        )
        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func presentCheckInPromptIfNeeded() {
        refreshCheckInPromptState()
        checkInPromptWindowController?.update(with: checkInPromptState)
    }

    func dismissCheckInPrompt() {
        checkInPromptState.isPresented = false
        checkInPromptWindowController?.hide()
    }

    var recentPromptProjects: [ProjectRecord] {
        let projects = fetchProjects()
        let recentEndDates = recentPromptProjectEndDates()

        return projects.sorted { lhs, rhs in
            let lhsRecent = recentEndDates[lhs.id]
            let rhsRecent = recentEndDates[rhs.id]

            switch (lhsRecent, rhsRecent) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var filteredPromptProjects: [ProjectRecord] {
        let query = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return recentPromptProjects
        }

        return recentPromptProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
        }
    }

    func canCreatePromptProject(named rawName: String) -> Bool {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return false
        }

        return !fetchProjects().contains { project in
            project.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func createProject(named name: String) throws {
        _ = try createProjectRecord(named: name)
    }

    func selectProjectForPrompt(_ project: ProjectRecord) throws {
        let completionDate = clock.now
        let entryEndAt = completionDate
        let entryStartAt = entryEndAt.addingTimeInterval(-accountableElapsedInterval)
        let timeEntry = TimeEntryRecord(
            project: project,
            startAt: entryStartAt,
            endAt: entryEndAt,
            source: "check-in"
        )
        modelContext.insert(timeEntry)
        try modelContext.save()

        let completionResult = scheduler.completeCheckIn(
            state: schedulerStateRecord,
            settings: settings,
            completionDate: completionDate
        )
        schedulerStateStore.apply(completionResult, to: schedulerStateRecord)
        try schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: completionResult.snapshot)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func createAndSelectProjectForPrompt(named name: String) throws {
        let project = try createProjectRecord(named: name)
        try selectProjectForPrompt(project)
    }

    func renameProject(_ project: ProjectRecord, to newName: String) throws {
        project.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try modelContext.save()
    }

    func deleteProject(_ project: ProjectRecord) throws {
        if !project.timeEntries.isEmpty {
            throw ProjectDeletionError.hasTrackedTime(project.name)
        }

        modelContext.delete(project)
        try modelContext.save()
    }

    func saveSettings() throws {
        try modelContext.save()
        handleSchedulerTransition(eventDate: clock.now)
    }

    private func nextProjectSortOrder() -> Int {
        let descriptor = FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder, order: .reverse)])
        let currentHighest = try? modelContext.fetch(descriptor).first?.sortOrder
        return (currentHighest ?? -1) + 1
    }

    private func createProjectRecord(named name: String) throws -> ProjectRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectValidationError.emptyName
        }

        let nextSortOrder = nextProjectSortOrder()
        let project = ProjectRecord(name: trimmedName, sortOrder: nextSortOrder)
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    private func fetchProjects() -> [ProjectRecord] {
        let descriptor = FetchDescriptor<ProjectRecord>(sortBy: [SortDescriptor(\.sortOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func recentPromptProjectEndDates() -> [UUID: Date] {
        let descriptor = FetchDescriptor<TimeEntryRecord>(sortBy: [SortDescriptor(\.endAt, order: .reverse)])
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        var latestEndDateByProjectID: [UUID: Date] = [:]

        for entry in entries {
            guard let project = entry.project, latestEndDateByProjectID[project.id] == nil else {
                continue
            }

            latestEndDateByProjectID[project.id] = entry.endAt
        }

        return latestEndDateByProjectID
    }

    private func observeWorkspaceWake() {
        guard wakeObserver == nil else {
            return
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWake()
            }
        }
    }

    private func handleSchedulerTransition(eventDate: Date) {
        let result = scheduler.updateState(
            schedulerStateRecord,
            settings: settings,
            eventDate: eventDate
        )

        schedulerStateStore.apply(result, to: schedulerStateRecord)
        try? schedulerStateStore.save(schedulerStateRecord)
        apply(snapshot: result.snapshot)
        refreshCheckInPromptState()
        launchState = .ready
    }

    private func apply(snapshot: PollingSchedulerSnapshot) {
        nextCheckInAt = snapshot.nextCheckInAt
        isPromptOverdue = snapshot.isPromptOverdue
        accountableElapsedInterval = snapshot.accountableElapsedInterval
    }

    nonisolated static func formattedElapsedText(for elapsedDuration: TimeInterval) -> String {
        let elapsedMinutes = max(Int(elapsedDuration / 60), 0)
        return "Elapsed \(elapsedMinutes) min"
    }

    nonisolated private static func supportingSubtitle(
        elapsedDuration: TimeInterval,
        isOverdue: Bool
    ) -> String {
        let elapsed = formattedElapsedText(for: elapsedDuration)
        guard isOverdue else {
            return elapsed
        }

        return "\(elapsed) · overdue"
    }
}

@MainActor
final class LocalProjectStore: ProjectStore {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
}

@MainActor
final class LocalSettingsStore: SettingsStore {
    let record: AppSettingsRecord

    init(record: AppSettingsRecord) {
        self.record = record
    }
}

enum ProjectDeletionError: LocalizedError {
    case hasTrackedTime(String)

    var errorDescription: String? {
        switch self {
        case let .hasTrackedTime(projectName):
            return "Tempo keeps local time entries attached to \(projectName), so it cannot be deleted yet."
        }
    }
}

enum ProjectValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Project names must contain at least one visible character."
        }
    }
}
