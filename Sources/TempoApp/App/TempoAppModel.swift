import AppKit
import Foundation
import Observation
import SwiftData

protocol ProjectStore: AnyObject {}
protocol SettingsStore: AnyObject {}
protocol SchedulerStore: AnyObject {}

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

    private let clock: any SchedulerClock
    private let scheduler: PollingScheduler
    private var hasHandledInitialLaunch = false
    private var wakeObserver: NSObjectProtocol?

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
        self.settingsStore = LocalSettingsStore(record: self.settings)
        self.schedulerStore = schedulerStateStore
        self.projectStore = LocalProjectStore(modelContext: self.modelContext)

        apply(snapshot: scheduler.snapshot(for: self.schedulerStateRecord, settings: self.settings, eventDate: clock.now))
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

    func createProject(named name: String) throws {
        let nextSortOrder = nextProjectSortOrder()
        let project = ProjectRecord(name: name, sortOrder: nextSortOrder)
        modelContext.insert(project)
        try modelContext.save()
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

        schedulerStateRecord.lastAppLaunchAt = result.lastAppLaunchAt
        schedulerStateRecord.lastCheckInAt = result.lastCheckInAt
        schedulerStateRecord.nextCheckInAt = result.nextCheckInAt

        try? modelContext.save()
        apply(snapshot: result.snapshot)
        launchState = .ready
    }

    private func apply(snapshot: PollingSchedulerSnapshot) {
        nextCheckInAt = snapshot.nextCheckInAt
        isPromptOverdue = snapshot.isPromptOverdue
        accountableElapsedInterval = snapshot.accountableElapsedInterval
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
