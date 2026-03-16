import AppKit
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

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

enum IdleResolutionError: LocalizedError {
    case noPendingIdle
    case invalidSplitDuration

    var errorDescription: String? {
        switch self {
        case .noPendingIdle:
            return "No pending idle interval is available."
        case .invalidSplitDuration:
            return "The first segment must be greater than zero and shorter than the full idle interval."
        }
    }
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
    var selectedPromptProjectID: UUID?
    var idleSplitFirstDurationMinutes = 1
    var idleSplitSecondProjectID: UUID?
    var checkInPromptState = CheckInPromptState.hidden
    var promptSearchText = ""
    var selectedAnalyticsRange: AnalyticsRange = .day
    var analyticsPeriod: AnalyticsPeriod
    var analyticsTotalDuration: TimeInterval = 0
    var analyticsProjectSummaries: [AnalyticsProjectSummary] = []
    var analyticsTopProjectName: String?
    var analyticsFirstEntryStartDate: Date?
    var analyticsTimelineIntervals: [AnalyticsTimelineInterval] = []
    var analyticsExportStatusMessage: String?
    var analyticsExportErrorMessage: String?
    var launchAtLoginEnabled = false
    var launchAtLoginErrorMessage: String?
    private var lastSavedPollingIntervalMinutes = 25
    private var isMenuBarWindowVisible = false

    private let clock: any SchedulerClock
    private let calendar: Calendar
    private let scheduler: PollingScheduler
    private let schedulerStateStore: SchedulerStateStore
    private let analyticsStore: AnalyticsStore
    private let csvExportService: CSVExportService
    private let launchAtLoginController: any LaunchAtLoginControlling
    private var hasHandledInitialLaunch = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var checkInPromptWindowController: CheckInPromptWindowController?
    private var scheduledPromptTimer: Timer?

    init(
        modelContainer: ModelContainer? = nil,
        clock: any SchedulerClock = SystemSchedulerClock(),
        calendar: Calendar = .current,
        launchAtLoginController: any LaunchAtLoginControlling = SMAppServiceLaunchAtLoginController()
    ) {
        let resolvedContainer = modelContainer ?? TempoModelContainer.live()
        self.modelContainer = resolvedContainer
        self.modelContext = ModelContext(resolvedContainer)
        self.clock = clock
        self.calendar = calendar
        self.launchAtLoginController = launchAtLoginController
        self.scheduler = PollingScheduler(clock: clock, calendar: calendar)
        self.analyticsPeriod = AnalyticsPeriod(
            startDate: clock.now,
            endDate: clock.now,
            label: clock.now.formatted(date: .abbreviated, time: .omitted)
        )

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
        self.analyticsStore = AnalyticsStore(modelContext: self.modelContext)
        self.csvExportService = CSVExportService(modelContext: self.modelContext, calendar: calendar)
        self.settingsStore = LocalSettingsStore(record: self.settings)
        self.schedulerStore = schedulerStateStore
        self.projectStore = LocalProjectStore(modelContext: self.modelContext)
        self.launchAtLoginEnabled = launchAtLoginController.isEnabled
        self.lastSavedPollingIntervalMinutes = self.settings.pollingIntervalMinutes

        apply(snapshot: scheduler.snapshot(for: self.schedulerStateRecord, settings: self.settings, eventDate: clock.now))
        refreshAnalytics(referenceDate: clock.now)
        refreshCheckInPromptState()
    }

    func performInitialLaunchIfNeeded() {
        guard !hasHandledInitialLaunch else {
            return
        }

        hasHandledInitialLaunch = true
        observeWorkspaceWake()
        syncLaunchAtLoginPreferenceFromSystem()
        recoverSchedulerState(eventDate: clock.now)
        refreshAnalytics(referenceDate: clock.now)
    }

    func syncLaunchAtLoginPreferenceFromSystem() {
        let isEnabled = launchAtLoginController.isEnabled
        launchAtLoginEnabled = isEnabled
        settings.launchAtLoginEnabled = isEnabled
        launchAtLoginErrorMessage = nil
        try? modelContext.save()
    }

    func saveLaunchAtLoginPreference(_ enabled: Bool) throws {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginEnabled = enabled
            settings.launchAtLoginEnabled = enabled
            launchAtLoginErrorMessage = nil
            try modelContext.save()
        } catch {
            let systemState = launchAtLoginController.isEnabled
            launchAtLoginEnabled = systemState
            settings.launchAtLoginEnabled = systemState
            launchAtLoginErrorMessage = error.localizedDescription
            try? modelContext.save()
            throw error
        }
    }

    func handleSceneActivation() {
        let now = clock.now
        detectInactivityIfNeeded(activityDate: currentUserActivityDate(referenceDate: now))

        guard !isIdlePending else {
            return
        }

        recoverSchedulerState(eventDate: now)
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

        recoverSchedulerState(eventDate: now)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func attachCheckInPromptWindowController(_ controller: CheckInPromptWindowController) {
        checkInPromptWindowController = controller
        controller.bind(appModel: self)
        controller.update(with: detachedCheckInPromptState)
    }

    func setMenuBarWindowVisible(_ isVisible: Bool) {
        guard isMenuBarWindowVisible != isVisible else {
            return
        }

        isMenuBarWindowVisible = isVisible
        checkInPromptWindowController?.update(with: detachedCheckInPromptState)
    }

    func refreshCheckInPromptState() {
        ensureIdleSelectionDefaults()
        let shouldPresent = isPromptOverdue || shouldPresentPendingIdlePrompt
        let promptTitle = "What are you currently doing"
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
        checkInPromptWindowController?.update(with: detachedCheckInPromptState)
    }

    func presentCheckInPromptIfNeeded() {
        refreshCheckInPromptState()
        checkInPromptWindowController?.update(with: detachedCheckInPromptState)
    }

    func dismissCheckInPrompt() {
        checkInPromptState.isPresented = false
        checkInPromptWindowController?.hide()
        schedulePromptTimerIfNeeded()
    }

    var delayPresetMinutes: [Int] {
        settings.delayPresetMinutes
    }

    var currentProjectContextLabel: String {
        latestProjectCheckIn()?.project?.name ?? "No recent project"
    }

    var todaysTrackedDuration: TimeInterval {
        analyticsStore.summary(
            range: .day,
            referenceDate: clock.now,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        ).totalDuration
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
            return "Resumes at daily cutoff (\(Self.formattedClockTime(silenceEndsAt)))"
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

    var analyticsTotalDurationText: String {
        Self.formattedTrackedDuration(analyticsTotalDuration)
    }

    var analyticsTopProjectSummaryText: String {
        guard
            let topProject = analyticsProjectSummaries.first
        else {
            return "No tracked time"
        }

        return "\(topProject.projectName) · \(Self.formattedTrackedDuration(topProject.totalDuration))"
    }

    var analyticsFirstEntryStartText: String {
        guard let analyticsFirstEntryStartDate else {
            return "No input yet"
        }

        return Self.formattedClockTime(analyticsFirstEntryStartDate)
    }

    var selectedPromptProject: ProjectRecord? {
        guard let selectedPromptProjectID else {
            return nil
        }

        return fetchProjects().first { $0.id == selectedPromptProjectID }
    }

    var idleSplitSecondProject: ProjectRecord? {
        guard let idleSplitSecondProjectID else {
            return nil
        }

        return fetchProjects().first { $0.id == idleSplitSecondProjectID }
    }

    var pendingIdleReasonDisplayText: String {
        pendingIdleReasonLabel
    }

    var firstIdleSegmentMinutesRange: ClosedRange<Int> {
        let totalMinutes = max(Int(pendingIdleDuration / 60), 0)
        return 1...max(totalMinutes - 1, 1)
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

    func updatePromptSearchText(_ rawText: String) {
        promptSearchText = rawText
        syncPromptSelection()
    }

    func submitPromptSearch() throws {
        let trimmedQuery = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        if canCreatePromptProject(named: trimmedQuery) {
            try createAndSelectProjectForPrompt(named: trimmedQuery)
            return
        }

        if isIdlePending {
            if let selectedPromptProject {
                try assignPendingIdle(to: selectedPromptProject)
            }
            return
        }

        if let selectedPromptProject {
            try selectProjectForPrompt(selectedPromptProject)
        }
    }

    func assignSelectedPromptProjectForPendingIdle() throws {
        guard let selectedPromptProject else {
            return
        }

        try assignPendingIdle(to: selectedPromptProject)
    }

    func createProject(named name: String) throws {
        _ = try createProjectRecord(named: name)
    }

    func selectAnalyticsRange(_ range: AnalyticsRange) {
        selectedAnalyticsRange = range
        refreshAnalytics(referenceDate: clock.now)
    }

    func selectProjectForPrompt(_ project: ProjectRecord) throws {
        if isIdlePending {
            try assignPendingIdle(to: project)
            return
        }

        let completionDate = clock.now
        try persistProjectCheckIn(project, at: completionDate, source: "check-in")

        let completionResult = scheduler.completeCheckIn(
            state: schedulerStateRecord,
            settings: settings,
            completionDate: completionDate
        )
        schedulerStateStore.apply(completionResult, to: schedulerStateRecord)
        try schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: completionResult.snapshot)
        refreshAnalytics(referenceDate: completionDate)
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    func createAndSelectProjectForPrompt(named name: String) throws {
        let project = try createProjectRecord(named: name)
        if isIdlePending {
            selectedPromptProjectID = project.id
            idleSplitSecondProjectID = project.id
            promptSearchText = ""
            refreshCheckInPromptState()
            return
        }

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
        try persistIdleCheckIn(
            at: clock.now,
            idleKind: .doneForDay,
            source: "done-for-day"
        )
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

    func assignPendingIdle(to project: ProjectRecord) throws {
        guard pendingIdleStartedAt != nil, let pendingIdleEndedAt else {
            throw IdleResolutionError.noPendingIdle
        }

        let completionDate = max(clock.now, pendingIdleEndedAt)
        try persistProjectCheckIn(project, at: completionDate, source: "idle-return")
        try completePendingIdleResolution()
        refreshAnalytics(referenceDate: clock.now)
    }

    func discardPendingIdle() throws {
        guard pendingIdleStartedAt != nil, pendingIdleEndedAt != nil else {
            throw IdleResolutionError.noPendingIdle
        }

        try completePendingIdleResolution()
        refreshAnalytics(referenceDate: clock.now)
    }

    func splitPendingIdle(
        firstProject: ProjectRecord,
        firstDurationMinutes: Int,
        secondProject: ProjectRecord
    ) throws {
        guard let pendingIdleStartedAt, let pendingIdleEndedAt else {
            throw IdleResolutionError.noPendingIdle
        }

        let totalSeconds = pendingIdleEndedAt.timeIntervalSince(pendingIdleStartedAt)
        let firstDuration = TimeInterval(firstDurationMinutes * 60)
        guard firstDuration > 0, firstDuration < totalSeconds else {
            throw IdleResolutionError.invalidSplitDuration
        }

        try persistProjectCheckIn(secondProject, at: clock.now, source: "idle-return")

        try completePendingIdleResolution()
        refreshAnalytics(referenceDate: clock.now)
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

        try? persistIdleCheckIn(
            at: activityDate,
            idleKind: .automaticThreshold,
            source: "inactivity"
        )

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
        try? persistIdleCheckIn(
            at: clock.now,
            idleKind: .automaticThreshold,
            source: "screen-locked"
        )
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
        refreshAnalytics(referenceDate: clock.now)
    }

    func deleteProject(_ project: ProjectRecord) throws {
        if !project.checkIns.isEmpty || !project.timeEntries.isEmpty {
            throw ProjectDeletionError.hasTrackedTime(project.name)
        }

        modelContext.delete(project)
        try modelContext.save()
    }

    func saveSettings() throws {
        try modelContext.save()
        defer {
            lastSavedPollingIntervalMinutes = settings.pollingIntervalMinutes
        }

        guard settings.pollingIntervalMinutes != lastSavedPollingIntervalMinutes else {
            recoverSchedulerState(eventDate: clock.now)
            return
        }

        if isIdlePending || isPromptDelayed || isSilenced {
            recoverSchedulerState(eventDate: clock.now)
            return
        }

        let result = scheduler.rescheduleFromSettingsChange(
            state: schedulerStateRecord,
            settings: settings,
            eventDate: clock.now
        )
        schedulerStateStore.apply(result, to: schedulerStateRecord)
        try schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: result.snapshot)
        refreshCheckInPromptState()
    }

    func refreshAnalytics(referenceDate: Date) {
        let snapshot = analyticsStore.summary(
            range: selectedAnalyticsRange,
            referenceDate: referenceDate,
            calendar: calendar,
            dayCutoffHour: settings.analyticsDayCutoffHour
        )
        analyticsPeriod = snapshot.period
        analyticsTotalDuration = snapshot.totalDuration
        analyticsProjectSummaries = snapshot.projectSummaries
        analyticsTopProjectName = snapshot.topProjectName
        analyticsFirstEntryStartDate = snapshot.firstEntryStartDate
        analyticsTimelineIntervals = snapshot.timelineIntervals
    }

    func exportAnalyticsCSV() {
        analyticsExportStatusMessage = nil
        analyticsExportErrorMessage = nil

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "tempo-analytics.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            return
        }

        do {
            let csv = csvExportService.csvString(
                range: selectedAnalyticsRange,
                referenceDate: clock.now,
                dayCutoffHour: settings.analyticsDayCutoffHour
            )
            try csv.write(to: destinationURL, atomically: true, encoding: .utf8)
            analyticsExportStatusMessage = "CSV exported"
        } catch {
            analyticsExportErrorMessage = error.localizedDescription
        }
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
        let descriptor = FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        var latestEndDateByProjectID: [UUID: Date] = [:]

        for entry in entries {
            guard let project = entry.project, latestEndDateByProjectID[project.id] == nil else {
                continue
            }

            latestEndDateByProjectID[project.id] = entry.timestamp
        }

        return latestEndDateByProjectID
    }

    private func latestProjectCheckIn() -> CheckInRecord? {
        let descriptor = FetchDescriptor<CheckInRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try? modelContext.fetch(descriptor).first(where: { $0.project != nil })
    }

    private func persistProjectCheckIn(_ project: ProjectRecord, at timestamp: Date, source: String) throws {
        modelContext.insert(
            CheckInRecord(
                timestamp: timestamp,
                kind: "project",
                source: source,
                project: project
            )
        )
        try modelContext.save()
    }

    private func persistIdleCheckIn(at timestamp: Date, idleKind: TimeAllocationIdleKind, source: String) throws {
        modelContext.insert(
            CheckInRecord(
                timestamp: timestamp,
                kind: "idle",
                source: source,
                idleKind: idleKind.rawValue
            )
        )
        try modelContext.save()
    }

    private func completePendingIdleResolution() throws {
        let completionResult = scheduler.completeCheckIn(
            state: schedulerStateRecord,
            settings: settings,
            completionDate: clock.now
        )
        schedulerStateStore.apply(completionResult, to: schedulerStateRecord)
        try schedulerStateStore.save(schedulerStateRecord)

        apply(snapshot: completionResult.snapshot)
        selectedPromptProjectID = nil
        idleSplitSecondProjectID = nil
        idleSplitFirstDurationMinutes = 1
        promptSearchText = ""
        refreshCheckInPromptState()
        dismissCheckInPrompt()
    }

    private func syncPromptSelection() {
        let filteredProjects = filteredPromptProjects
        let trimmedQuery = promptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if filteredProjects.isEmpty {
            selectedPromptProjectID = preferredPromptProject()?.id
            if isIdlePending {
                idleSplitSecondProjectID = selectedPromptProjectID
            }
            return
        }

        if trimmedQuery.isEmpty {
            let preferredProjectID = preferredPromptProject()?.id ?? filteredProjects.first?.id
            selectedPromptProjectID = preferredProjectID
            if isIdlePending {
                idleSplitSecondProjectID = preferredProjectID
            }
            return
        }

        if let exactMatch = filteredProjects.first(where: { project in
            project.name.compare(trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            selectedPromptProjectID = exactMatch.id
            if isIdlePending {
                idleSplitSecondProjectID = exactMatch.id
            }
            return
        }

        if let selectedPromptProjectID, filteredProjects.contains(where: { $0.id == selectedPromptProjectID }) {
            return
        }

        selectedPromptProjectID = filteredProjects.first?.id
        if isIdlePending {
            idleSplitSecondProjectID = filteredProjects.first?.id
        }
    }

    private func ensureIdleSelectionDefaults() {
        guard isIdlePending else {
            return
        }

        let projects = filteredPromptProjects.isEmpty ? recentPromptProjects : filteredPromptProjects

        if selectedPromptProject == nil {
            selectedPromptProjectID = preferredPromptProject(in: projects)?.id
        }

        if idleSplitSecondProject == nil {
            idleSplitSecondProjectID = preferredPromptProject(in: projects)?.id
        }

        let totalMinutes = max(Int(pendingIdleDuration / 60), 0)
        if totalMinutes > 1 {
            let clamped = min(max(idleSplitFirstDurationMinutes, 1), totalMinutes - 1)
            idleSplitFirstDurationMinutes = clamped
        } else {
            idleSplitFirstDurationMinutes = 1
        }
    }

    private func preferredPromptProject(in projects: [ProjectRecord]? = nil) -> ProjectRecord? {
        let candidates = projects ?? recentPromptProjects
        guard !candidates.isEmpty else {
            return nil
        }

        if let latestProjectID = latestProjectCheckIn()?.project?.id,
           let latestProject = candidates.first(where: { $0.id == latestProjectID }) {
            return latestProject
        }

        return candidates.first
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

    func recoverSchedulerState(eventDate: Date) {
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
        if !snapshot.isIdlePending {
            selectedPromptProjectID = nil
            idleSplitSecondProjectID = nil
            idleSplitFirstDurationMinutes = 1
        }

        schedulePromptTimerIfNeeded()
    }

    private var shouldPresentPendingIdlePrompt: Bool {
        isIdlePending && schedulerStateRecord.idleResolvedAt != nil
    }

    var detachedCheckInPromptState: CheckInPromptState {
        guard !isMenuBarWindowVisible else {
            return .hidden
        }

        return checkInPromptState
    }

    private func schedulePromptTimerIfNeeded() {
        scheduledPromptTimer?.invalidate()
        scheduledPromptTimer = nil

        guard let nextRuntimeUpdateAt = nextRuntimeUpdateAt(referenceDate: clock.now) else {
            return
        }

        let interval = nextRuntimeUpdateAt.timeIntervalSince(clock.now)
        guard interval > 0 else {
            handleScheduledPromptTimerFired()
            return
        }

        scheduledPromptTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleScheduledPromptTimerFired()
            }
        }
    }

    private func handleScheduledPromptTimerFired() {
        scheduledPromptTimer?.invalidate()
        scheduledPromptTimer = nil
        recoverSchedulerState(eventDate: clock.now)
        presentCheckInPromptIfNeeded()
    }

    func nextRuntimeUpdateAt(referenceDate: Date) -> Date? {
        if shouldPresentPendingIdlePrompt || isPromptOverdue {
            return nil
        }

        let candidates = [nextCheckInAt, delayedUntilAt, silenceEndsAt].compactMap { $0 }
        return candidates.filter { $0 > referenceDate }.min()
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
