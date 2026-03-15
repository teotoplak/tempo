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
    var isPromptDelayed = false
    var delayedUntilAt: Date?
    var isSilenced = false
    var silenceEndsAt: Date?
    var isIdlePending = false
    var pendingIdleStartedAt: Date?
    var pendingIdleEndedAt: Date?
    var pendingIdleReason: String?
    var pendingIdleDuration: TimeInterval = 0
    var checkInPromptState = CheckInPromptState.hidden
    var promptSearchText = ""

    private let clock: any SchedulerClock
    private let scheduler: PollingScheduler
    private let schedulerStateStore: SchedulerStateStore
    private var hasHandledInitialLaunch = false
    private var workspaceObservers: [NSObjectProtocol] = []
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
        let now = clock.now
        detectInactivityIfNeeded(activityDate: currentUserActivityDate(referenceDate: now))

        guard !isIdlePending else {
            return
        }

        handleSchedulerTransition(eventDate: now)
    }

    func handleAppWake() {
        if isIdlePending {
            handleIdleReturn()
            return
        }

        let now = clock.now
        detectInactivityIfNeeded(activityDate: currentUserActivityDate(referenceDate: now))

        guard !isIdlePending else {
            return
        }

        handleSchedulerTransition(eventDate: now)
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
        let shouldPresent = isPromptOverdue || shouldPresentPendingIdlePrompt
        let promptTitle = shouldPresentPendingIdlePrompt ? "Resolve idle time" : "What are you currently doing"
        let supportingSubtitle = shouldPresentPendingIdlePrompt
            ? Self.idleSupportingSubtitle(duration: pendingIdleDuration, reason: pendingIdleReasonLabel)
            : Self.supportingSubtitle(
                elapsedDuration: accountableElapsedInterval,
                isOverdue: isPromptOverdue
            )
        checkInPromptState = CheckInPromptState(
            isPresented: shouldPresent,
            elapsedDuration: accountableElapsedInterval,
            isOverdue: isPromptOverdue,
            promptTitle: promptTitle,
            supportingSubtitle: supportingSubtitle
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

    var delayPresetMinutes: [Int] {
        settings.delayPresetMinutes
    }

    var currentProjectContextLabel: String {
        latestCompletedTimeEntry()?.project?.name ?? "No recent project"
    }

    var todaysTrackedDuration: TimeInterval {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: clock.now)
        let descriptor = FetchDescriptor<TimeEntryRecord>(sortBy: [SortDescriptor(\.endAt, order: .reverse)])
        let entries = (try? modelContext.fetch(descriptor)) ?? []

        return entries.reduce(into: 0) { total, entry in
            guard calendar.startOfDay(for: entry.endAt) == targetDay else {
                return
            }

            total += entry.endAt.timeIntervalSince(entry.startAt)
        }
    }

    func menuBarPrimaryStatus(at date: Date) -> String {
        if isSilenced, let silenceEndsAt {
            return "Silenced until \(Self.formattedClockTime(silenceEndsAt))"
        }

        if isPromptDelayed, let delayedUntilAt {
            return "Delayed until \(Self.formattedClockTime(delayedUntilAt))"
        }

        if isPromptOverdue {
            return "Check-in overdue"
        }

        guard let nextCheckInAt else {
            return "Not scheduled"
        }

        let remaining = max(nextCheckInAt.timeIntervalSince(date), 0)
        return "Next check-in in \(Self.formattedCompactDuration(remaining))"
    }

    func menuBarSecondaryStatus(at date: Date) -> String {
        if isSilenced, let silenceEndsAt {
            return "Resumes at local midnight (\(Self.formattedClockTime(silenceEndsAt)))"
        }

        if isPromptDelayed, let delayedUntilAt {
            let remaining = max(delayedUntilAt.timeIntervalSince(date), 0)
            return "Prompt hidden for \(Self.formattedCompactDuration(remaining))"
        }

        if isPromptOverdue {
            return Self.supportingSubtitle(
                elapsedDuration: accountableElapsedInterval,
                isOverdue: true
            )
        }

        guard let nextCheckInAt else {
            return "Open Tempo to reset scheduling."
        }

        return "Scheduled for \(Self.formattedClockTime(nextCheckInAt))"
    }

    var pendingIdleStatusText: String {
        Self.idleSupportingSubtitle(duration: pendingIdleDuration, reason: pendingIdleReasonLabel)
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

    func delayPrompt(byMinutes minutes: Int) throws {
        let result = scheduler.delayCheckIn(
            state: schedulerStateRecord,
            settings: settings,
            delayMinutes: minutes,
            delayDate: clock.now
        )
        schedulerStateStore.apply(result, to: schedulerStateRecord)
        try schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: result.snapshot)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func silenceForRestOfDay() throws {
        let result = scheduler.silenceUntilEndOfDay(
            state: schedulerStateRecord,
            settings: settings,
            eventDate: clock.now
        )
        schedulerStateStore.apply(result, to: schedulerStateRecord)
        try schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: result.snapshot)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func endSilenceMode() throws {
        let result = scheduler.endSilence(
            state: schedulerStateRecord,
            settings: settings,
            eventDate: clock.now
        )
        schedulerStateStore.apply(result, to: schedulerStateRecord)
        try schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: result.snapshot)
        refreshCheckInPromptState()
    }

    func checkInNow() {
        if isIdlePending {
            schedulerStateRecord.idleResolvedAt = clock.now
            refreshCheckInPromptState()
            presentCheckInPromptIfNeeded()
            return
        }

        let pollingInterval = TimeInterval(settings.pollingIntervalMinutes * 60)
        let promptReference = schedulerStateRecord.delayedFromPromptAt ?? schedulerStateRecord.nextCheckInAt ?? clock.now
        let referenceStart = schedulerStateRecord.lastCheckInAt ?? promptReference.addingTimeInterval(-pollingInterval)
        accountableElapsedInterval = max(clock.now.timeIntervalSince(referenceStart), pollingInterval)
        isPromptOverdue = true
        refreshCheckInPromptState()
        presentCheckInPromptIfNeeded()
    }

    func detectInactivityIfNeeded(activityDate: Date) {
        guard !isIdlePending else {
            return
        }

        let threshold = TimeInterval(settings.idleThresholdMinutes * 60)
        let now = clock.now
        guard now.timeIntervalSince(activityDate) >= threshold else {
            return
        }

        let result = scheduler.beginIdleInterval(
            state: schedulerStateRecord,
            settings: settings,
            eventDate: now,
            reason: "inactivity"
        )
        var adjustedResult = result
        adjustedResult.snapshot.accountableWorkEndAt = activityDate
        adjustedResult.snapshot.pendingIdleStartedAt = activityDate
        adjustedResult.accountableWorkEndAt = activityDate
        adjustedResult.idleBeganAt = activityDate
        adjustedResult.pendingIdleStartedAt = activityDate

        schedulerStateStore.apply(adjustedResult, to: schedulerStateRecord)
        try? schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: adjustedResult.snapshot)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func handleScreenLock() {
        let result = scheduler.beginIdleInterval(
            state: schedulerStateRecord,
            settings: settings,
            eventDate: clock.now,
            reason: "screen-locked"
        )
        schedulerStateStore.apply(result, to: schedulerStateRecord)
        try? schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: result.snapshot)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func handleIdleReturn() {
        let result = scheduler.resolveReturnedIdleState(
            state: schedulerStateRecord,
            settings: settings,
            eventDate: clock.now
        )
        schedulerStateStore.apply(result, to: schedulerStateRecord)
        try? schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: result.snapshot)
        refreshCheckInPromptState()
        presentCheckInPromptIfNeeded()
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

    private func latestCompletedTimeEntry() -> TimeEntryRecord? {
        let descriptor = FetchDescriptor<TimeEntryRecord>(sortBy: [SortDescriptor(\.endAt, order: .reverse)])
        return try? modelContext.fetch(descriptor).first
    }

    private func observeWorkspaceWake() {
        guard workspaceObservers.isEmpty else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppWake()
            }
        }
        )
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenLock()
            }
        })
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenLock()
            }
        })
        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleIdleReturn()
            }
        })
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
        isPromptDelayed = snapshot.isPromptDelayed
        delayedUntilAt = snapshot.delayedUntilAt
        isSilenced = snapshot.isSilenced
        silenceEndsAt = snapshot.silenceEndsAt
        isIdlePending = snapshot.isIdlePending
        pendingIdleStartedAt = snapshot.pendingIdleStartedAt
        pendingIdleEndedAt = snapshot.pendingIdleEndedAt
        pendingIdleReason = snapshot.pendingIdleReason
        pendingIdleDuration = max((snapshot.pendingIdleEndedAt ?? snapshot.pendingIdleStartedAt ?? clock.now).timeIntervalSince(snapshot.pendingIdleStartedAt ?? clock.now), 0)
    }

    private var shouldPresentPendingIdlePrompt: Bool {
        isIdlePending && schedulerStateRecord.idleResolvedAt != nil
    }

    private var pendingIdleReasonLabel: String {
        switch pendingIdleReason {
        case "screen-locked":
            return "Screen locked"
        default:
            return "Inactive"
        }
    }

    private func currentUserActivityDate(referenceDate: Date) -> Date {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        guard idleSeconds.isFinite, idleSeconds >= 0 else {
            return referenceDate
        }

        return referenceDate.addingTimeInterval(-idleSeconds)
    }

    nonisolated static func formattedElapsedText(for elapsedDuration: TimeInterval) -> String {
        let elapsedMinutes = max(Int(elapsedDuration / 60), 0)
        return "Elapsed \(elapsedMinutes) min"
    }

    nonisolated static func formattedClockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    nonisolated static func formattedCompactDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int(duration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }

        return "\(minutes)m"
    }

    nonisolated static func formattedTrackedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(Int(duration / 60), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
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

    nonisolated private static func idleSupportingSubtitle(
        duration: TimeInterval,
        reason: String
    ) -> String {
        "\(reason) for \(formattedCompactDuration(duration))"
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
